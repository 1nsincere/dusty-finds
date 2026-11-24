-- StorageShelfCheck.luau (ServerScriptService.Server.Tests.StorageShelfCheck)
-- Purpose: tests StorageShelfService.Pick, the rule for which unrestored items go on the storage room shelves:
-- only Dirty / InProgress, rarest first, golden before plain, stable order, the bench item skipped, "+N more" count.
-- Pure: fake inventories, no players, never touches a profile.
-- Owner: Dev 3 (Sean). Depends on: Services.StorageShelfService (Pick), Shared.Config (Items, Rarities).
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.StorageShelfCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StorageShelfCheck = {}

function StorageShelfCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0
	local function check(name: string, cond: boolean, detail: any?)
		if cond then
			passCount += 1
			table.insert(lines, "PASS " .. name)
		else
			failCount += 1
			table.insert(lines, `FAIL {name}{if detail ~= nil then " -> " .. tostring(detail) else ""}`)
		end
	end

	local Items = require(ReplicatedStorage.Shared.Config.Items)
	local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
	local Pick = require(script.Parent.Parent.Services.StorageShelfService).Pick

	-- find real item ids by rarity so the test follows Config
	local byRarity = {}
	for id, def in Items do
		byRarity[def.rarity] = byRarity[def.rarity] or {}
		table.insert(byRarity[def.rarity], id)
	end
	for _, list in byRarity do
		table.sort(list)
	end
	local common, rare, legendary = byRarity.Common[1], byRarity.Rare[1], byRarity.Legendary[1]
	check("Config has Common, Rare and Legendary items", common ~= nil and rare ~= nil and legendary ~= nil)

	local inv = {
		a = { itemId = common, state = "Dirty" },
		b = { itemId = rare, state = "InProgress" },
		c = { itemId = legendary, state = "Dirty" },
		d = { itemId = common, state = "Restored", stars = 3 },
		e = { itemId = common, state = "Displayed", stars = 2 },
		f = { itemId = common, state = "Unopened" },
		g = { itemId = common, state = "Dirty", golden = true },
	}
	local shown, more = Pick(inv, nil, 16)
	local uids = {}
	for _, s in shown do
		table.insert(uids, s.uid)
	end
	check("only Dirty and InProgress are shown", #shown == 4 and more == 0, table.concat(uids, ","))
	check("rarest first: Legendary, Rare, then Commons", shown[1].uid == "c" and shown[2].uid == "b", table.concat(uids, ","))
	check("golden before plain at the same rarity", shown[3].uid == "g" and shown[4].uid == "a", table.concat(uids, ","))
	check("golden flag is passed on", shown[3].golden == true and shown[4].golden == false)
	check("Restored / Displayed / Unopened never shown", not table.find(uids, "d") and not table.find(uids, "e") and not table.find(uids, "f"))

	local skipped = Pick(inv, "c", 16)
	check("the item on the bench is not shown twice", skipped[1].uid == "b" and #skipped == 3)

	local big = {}
	for i = 1, 20 do
		big[string.format("u%02d", i)] = { itemId = common, state = "Dirty" }
	end
	local fit, extra = Pick(big, nil, 16)
	check("20 dirty items: 16 shown, +4 more", #fit == 16 and extra == 4, `{#fit} +{extra}`)
	check("same rarity: stable order by item then uid", fit[1].uid == "u01" and fit[16].uid == "u16")
	local again = Pick(big, nil, 16)
	local same = true
	for i = 1, 16 do
		if again[i].uid ~= fit[i].uid then
			same = false
		end
	end
	check("calling again gives the same order (items don't jump around)", same)

	check("empty inventory: nothing, 0 more", #(Pick({}, nil, 16)) == 0 and select(2, Pick({}, nil, 16)) == 0)
	check("nil inventory (data not loaded): nothing", #(Pick(nil, nil, 16)) == 0)
	check("unknown item id is ignored", #(Pick({ x = { itemId = "NotAnItem", state = "Dirty" } }, nil, 16)) == 0)
	check("rarity index exists for every rarity used", Rarities.Common.index < Rarities.Rare.index and Rarities.Rare.index < Rarities.Legendary.index)

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[StorageShelfCheck]", line)
		end
	end
	print(`[StorageShelfCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return StorageShelfCheck
