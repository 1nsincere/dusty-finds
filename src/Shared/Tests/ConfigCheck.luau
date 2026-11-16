-- ConfigCheck.luau (ReplicatedStorage.Shared.Tests.ConfigCheck)
-- Purpose: checks the Config data is complete and consistent. Prints one PASS or FAIL line per check.
-- Owner: Dev 1 (Ace). Depends on: all Config/* modules.
-- Run in the Studio command bar (Edit mode): require(game.ReplicatedStorage.Shared.Tests.ConfigCheck).run()
-- Never edit a check just to make it pass: fix the Config if it's wrong, and note a wrong doc in docs/WHILE_AWAY.md.

local Config = script.Parent.Parent:WaitForChild("Config")
local Economy = require(Config:WaitForChild("Economy"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Crates = require(Config:WaitForChild("Crates"))
local Items = require(Config:WaitForChild("Items"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Customers = require(Config:WaitForChild("Customers"))

local ConfigCheck = {}

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function contains(list: { any }, value: any): boolean
	return table.find(list, value) ~= nil
end

function ConfigCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0

	local function check(name: string, ok: boolean, detail: string?)
		if ok then
			passCount += 1
			table.insert(lines, "PASS " .. name)
		else
			failCount += 1
			table.insert(lines, "FAIL " .. name .. (if detail then "  -> " .. detail else ""))
		end
	end

	-- 1. Crate odds add up to exactly 100, and only name real rarities
	for _, crateId in sortedKeys(Crates) do
		local crate = Crates[crateId]
		local sum, unknown = 0, {}
		for rarity, pct in crate.odds do
			sum += pct
			if Rarities[rarity] == nil then
				table.insert(unknown, rarity)
			end
		end
		check(`crate {crateId}: odds add up to 100`, sum == 100, `sum is {sum}`)
		check(`crate {crateId}: odds only use known rarities`, #unknown == 0, table.concat(unknown, ", "))
		check(`crate {crateId}: odds list every rarity`, (function()
			for rarity in Rarities do
				if crate.odds[rarity] == nil then
					return false
				end
			end
			return true
		end)())
	end

	-- 2 and 3. Every item has its fields, a valid recipe, and a known rarity and category
	local requiredFields = { "id", "name", "tier", "rarity", "category", "baseValue", "recipe" }
	for _, itemId in sortedKeys(Items) do
		local item = Items[itemId]
		local missing = {}
		for _, field in requiredFields do
			if item[field] == nil then
				table.insert(missing, field)
			end
		end
		check(`item {itemId}: has all required fields`, #missing == 0, "missing " .. table.concat(missing, ", "))
		check(`item {itemId}: id matches its key`, item.id == itemId)
		check(`item {itemId}: baseValue is a positive number`, type(item.baseValue) == "number" and item.baseValue > 0)
		check(`item {itemId}: tier is 1 or 2`, item.tier == 1 or item.tier == 2)

		local badStep = nil
		if type(item.recipe) ~= "table" or #item.recipe == 0 then
			badStep = "recipe is empty or missing"
		else
			for i, step in item.recipe do
				if type(step) ~= "table" or not contains(Economy.StepTypes, step.type) then
					badStep = `step {i} has type {tostring(type(step) == "table" and step.type or step)}`
					break
				end
			end
		end
		check(`item {itemId}: recipe has steps and all use the six allowed types`, badStep == nil, badStep)

		check(`item {itemId}: rarity {tostring(item.rarity)} exists`, Rarities[item.rarity] ~= nil)
		check(`item {itemId}: category {tostring(item.category)} exists`, contains(Economy.Categories, item.category))
	end

	-- 4. Every crate has at least one item of each rarity it can roll (odds above 0) in its tier
	for _, crateId in sortedKeys(Crates) do
		local crate = Crates[crateId]
		local missing = {}
		for rarity, pct in crate.odds do
			if pct > 0 then
				local found = false
				for _, item in Items do
					if item.tier == crate.tier and item.rarity == rarity then
						found = true
						break
					end
				end
				if not found then
					table.insert(missing, rarity)
				end
			end
		end
		table.sort(missing)
		check(
			`crate {crateId}: tier {crate.tier} has an item for every rarity it can roll`,
			#missing == 0,
			"no item for " .. table.concat(missing, ", ")
		)
	end

	-- 5. Upgrade costs and requiredLevel lists are as long as maxLevel
	for _, upgradeId in sortedKeys(Upgrades) do
		local up = Upgrades[upgradeId]
		check(`upgrade {upgradeId}: id matches its key`, up.id == upgradeId)
		check(
			`upgrade {upgradeId}: costs has {up.maxLevel} entries`,
			type(up.costs) == "table" and #up.costs == up.maxLevel,
			`costs has {type(up.costs) == "table" and #up.costs or "none"}`
		)
		check(
			`upgrade {upgradeId}: requiredLevel has {up.maxLevel} entries`,
			type(up.requiredLevel) == "table" and #up.requiredLevel == up.maxLevel,
			`requiredLevel has {type(up.requiredLevel) == "table" and #up.requiredLevel or "none"}`
		)
		check(`upgrade {upgradeId}: required levels never go down`, (function()
			for i = 2, #up.requiredLevel do
				if up.requiredLevel[i] < up.requiredLevel[i - 1] then
					return false
				end
			end
			return true
		end)())
		-- `requires` = another upgrade that must be owned first (UpgradeService must check it, not just the level)
		if up.requires ~= nil then
			check(`upgrade {upgradeId}: requires "{up.requires}", which is an existing upgrade`, Upgrades[up.requires] ~= nil)
		end
		-- `decorSlots` = plot DecorSlots models this upgrade shows (one per level, names unique across all upgrades)
		if up.decorSlots ~= nil then
			check(`upgrade {upgradeId}: decorSlots has {up.maxLevel} entries`, type(up.decorSlots) == "table" and #up.decorSlots == up.maxLevel)
			check(`upgrade {upgradeId}: decorSlots names are not used by another upgrade`, (function()
				for otherId, other in Upgrades do
					if otherId ~= upgradeId and other.decorSlots ~= nil then
						for _, name in other.decorSlots do
							if table.find(up.decorSlots, name) then
								return false
							end
						end
					end
				end
				return true
			end)())
		end
		-- Ace's decision: all decor unlocks at level 1
		if up.tab == "Decor" then
			check(`upgrade {upgradeId}: decor unlocks at level 1`, (function()
				for _, level in up.requiredLevel do
					if level ~= 1 then
						return false
					end
				end
				return true
			end)())
		end
	end
	check(
		"Fish Tank requires the Back Room and Fountain requires the Showroom (docs/02 §6)",
		Upgrades.FishTank ~= nil
			and Upgrades.Fountain ~= nil
			and Upgrades.FishTank.requires == "BackRoom"
			and Upgrades.Fountain.requires == "Showroom"
	)

	-- 6. Item counts: 20 total, 12 in tier 1, 8 in tier 2
	local total, tier1, tier2 = 0, 0, 0
	for _, item in Items do
		total += 1
		if item.tier == 1 then
			tier1 += 1
		elseif item.tier == 2 then
			tier2 += 1
		end
	end
	check("item count is 22 (20 MVP + 2 Relics)", total == 22, `found {total}`)
	check("tier 1 has 12 items", tier1 == 12, `found {tier1}`)
	check("tier 2 has 10 items (8 + 2 Relics)", tier2 == 10, `found {tier2}`)

	-- 6b. Special pulls (Relics + Time Capsule): Relic never in a crate's odds, chances are sane, relics exist for the tiers that roll them
	check("no crate lists Relic in its odds above 0", (function()
		for _, crate in Crates do
			if (crate.odds.Relic or 0) ~= 0 then
				return false
			end
		end
		return true
	end)())
	check("Relic chances are between 0 and 5% and name real crates", (function()
		for crateId, chance in Economy.RelicChance do
			if Crates[crateId] == nil or Crates[crateId].price <= 0 or chance <= 0 or chance > 0.05 then
				return false
			end
		end
		return true
	end)())
	check("every crate with a Relic chance has a Relic item in its tier", (function()
		for crateId in Economy.RelicChance do
			local found = false
			for _, item in Items do
				if item.rarity == "Relic" and item.tier == Crates[crateId].tier then
					found = true
				end
			end
			if not found then
				return false
			end
		end
		return true
	end)())
	check("Time Capsule chances name real bought crates, odds add up to 100", (function()
		local sum = 0
		for _, pct in Economy.TimeCapsuleOdds do
			sum += pct
		end
		for crateId, chance in Economy.TimeCapsuleChance do
			if Crates[crateId] == nil or Crates[crateId].price <= 0 or chance <= 0 or chance > 0.2 then
				return false
			end
		end
		return sum == 100 and Economy.TimeCapsuleBonusItems >= 1
	end)())
	check("Free Delivery never rolls a Relic or a capsule", Economy.RelicChance.FreeDelivery == nil and Economy.TimeCapsuleChance.FreeDelivery == nil)

	-- Extra: rarities and customers are consistent
	local seenIndexes, dupIndex = {}, false
	for _, rarity in Rarities do
		if seenIndexes[rarity.index] then
			dupIndex = true
		end
		seenIndexes[rarity.index] = true
	end
	check("rarities have 6 different index values", not dupIndex and #sortedKeys(Rarities) == 6)
	for _, customerId in sortedKeys(Customers) do
		local c = Customers[customerId]
		check(
			`customer {customerId}: id matches key, positive weight and speed, known preferred rarity`,
			c.id == customerId
				and c.weight > 0
				and c.walkSpeed > 0
				and (c.prefersMinRarity == nil or Rarities[c.prefersMinRarity] ~= nil)
		)
	end
	check("there are 4 customer types", #sortedKeys(Customers) == 4)

	for _, line in lines do
		print(line)
	end
	print(`[ConfigCheck] {passCount} passed, {failCount} failed`)
	return passCount, failCount, table.concat(lines, "\n") .. `\n[ConfigCheck] {passCount} passed, {failCount} failed`
end

return ConfigCheck
