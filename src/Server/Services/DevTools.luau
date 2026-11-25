-- DevTools.luau
-- Purpose: Studio-ONLY test commands (give cash, set level, give items or boxes, max upgrades, reset a test profile).
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, InventoryService, ShipmentService, PlotService, Config.
-- Does nothing outside Studio: no remote, no object, no commands. Inside Studio it creates a BindableFunction
-- ServerStorage.DevTools (never visible to clients) that you call from the command bar while Playing (Server):
--   game.ServerStorage.DevTools:Invoke("help")    -- see docs/STUDIO_TESTING.md for every command

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local DevTools = {}
local DEBUG = true
local log = Log.new("DevTools", DEBUG)

local S: { [string]: any } = {}

local commands: { [string]: any } = {} -- each command returns (ok, value)

function commands.help()
	local names = {}
	for name in commands do
		table.insert(names, name)
	end
	table.sort(names)
	return true, "commands: " .. table.concat(names, ", ")
end

-- giveCash(player, amount)
function commands.giveCash(player: Player, amount: any)
	if not Validate.isInteger(amount, 0, 1e9) then
		return false, "amount must be a whole number 0 - 1,000,000,000"
	end
	return S.EconomyService.AddCash(player, amount, "Dev"), nil
end

-- setLevel(player, level): sets level directly and clears XP (no level-up rewards)
function commands.setLevel(player: Player, level: any)
	if not Validate.isInteger(level, 1, Economy.MaxLevel) then
		return false, `level must be 1 - {Economy.MaxLevel}`
	end
	S.DataService.Set(player, "xp", 0)
	return S.DataService.Set(player, "level", level), nil
end

-- addXp(player, amount): goes through EconomyService, so level-ups and their rewards happen like in the real game
function commands.addXp(player: Player, amount: any)
	if not Validate.isInteger(amount, 0, 1e9) then
		return false, "amount must be a whole number 0 - 1,000,000,000"
	end
	return S.EconomyService.AddXp(player, amount)
end

-- giveItem(player, itemId, state?, stars?, golden?): state defaults to "Dirty"; Restored/Displayed/Exhibited get stars (default 2)
function commands.giveItem(player: Player, itemId: any, state: any, stars: any, golden: any)
	if not Validate.isConfigId(itemId, Items) then
		return false, "unknown itemId"
	end
	local itemState = state or "Dirty"
	local uid, reason = S.InventoryService.Add(player, itemId, { state = itemState, golden = golden == true })
	if uid == nil then
		return false, reason
	end
	if itemState == "Restored" or itemState == "Displayed" or itemState == "Exhibited" then
		S.InventoryService.Update(player, uid, { stars = stars or 2 })
	end
	return true, uid
end

-- giveBox(player, crateId): a rolled box of Unopened items, like a bought crate but free
function commands.giveBox(player: Player, crateId: any)
	if not Validate.isConfigId(crateId, Crates) then
		return false, "unknown crateId"
	end
	local boxId = HttpService:GenerateGUID(false)
	local uids = {}
	for _ = 1, Crates[crateId].itemCount do
		local itemId, golden = S.ShipmentService.RollItem(crateId)
		local uid = itemId and S.InventoryService.Add(player, itemId, { state = "Unopened", golden = golden, crateId = crateId, boxId = boxId })
		if uid then
			table.insert(uids, uid)
		end
	end
	return #uids > 0, uids
end

-- autoRestore(player, uid, score?): runs a whole recipe through the REAL RestorationService rules (session, step order,
-- minimum times via a synthetic clock, stars, XP, collection) so the loop can be tested without the minigames.
-- score defaults to 100 for every step. Returns the final result { stars, xp, value, average } or the refusal reason.
function commands.autoRestore(player: Player, uid: any, score: any)
	if type(uid) ~= "string" then
		return false, "uid must be a string (see dump)"
	end
	local stepScore = if score == nil then 100 else score
	if not Validate.isNumber(stepScore) then
		return false, "score must be a number 0 - 100"
	end
	local Res = S.RestorationService
	local ok, reason, info = Res.StartRestore(player, uid, "Bench1", 0)
	if not ok then
		return false, reason
	end
	local session = Res.GetSession(player)
	local clock = 0
	local last
	for stepIndex = info.stepIndex, #info.recipe do
		clock += Economy.MinStepSeconds[info.recipe[stepIndex].type] or 0
		local stepOk, stepReason, result = Res.ReportStepComplete(player, uid, stepIndex, stepScore, session.id, clock)
		if not stepOk then
			Res.ExitRestore(player, uid)
			return false, stepReason
		end
		last = result
	end
	return true, last
end

-- whyStuck(player): a plain-language list of what the player can do next, or why they can't progress (first-10-minutes check)
function commands.whyStuck(player: Player)
	local data = S.DataService.Get(player)
	if data == nil then
		return false, "no data loaded"
	end
	local lines = {}
	local counts = { Unopened = 0, Dirty = 0, InProgress = 0, Restored = 0, Displayed = 0, Exhibited = 0 }
	for _, item in data.inventory do
		counts[item.state] = (counts[item.state] or 0) + 1
	end
	local capacity = S.InventoryService.GetCapacity(player)
	local counted = counts.Dirty + counts.InProgress + counts.Restored + counts.Displayed + counts.Exhibited
	table.insert(lines, `cash ${data.cash}, level {data.level}; inventory {counted}/{capacity} (Unopened boxes {counts.Unopened}, Dirty {counts.Dirty}, InProgress {counts.InProgress}, Restored {counts.Restored}, on shelves {counts.Displayed}, exhibits {counts.Exhibited})`)
	local cheapest = math.huge
	for _, crate in Crates do
		if crate.price > 0 and crate.requiredLevel <= data.level then
			cheapest = math.min(cheapest, crate.price)
		end
	end
	local problems = 0
	if counts.Unopened > 0 then
		table.insert(lines, `NEXT: open a box at the delivery point ({counts.Unopened} waiting)` .. (if counted >= capacity then " - BLOCKED: the inventory is full" else ""))
		if counted >= capacity then
			problems += 1
		end
	end
	if counts.Dirty + counts.InProgress > 0 then
		table.insert(lines, `NEXT: restore a Dirty item at the bench ({counts.Dirty + counts.InProgress} waiting)`)
	end
	if counts.Restored > 0 then
		table.insert(lines, `NEXT: put a Restored item on a shelf or pedestal ({counts.Restored} waiting)`)
	end
	if counts.Displayed > 0 then
		table.insert(lines, `customers can buy {counts.Displayed} displayed item(s)`)
	end
	if counted >= capacity and counts.Restored + counts.Displayed + counts.Exhibited == 0 then
		problems += 1
		table.insert(lines, "STUCK: the inventory is full of items that can't be sold yet (Dirty items can't be quick-sold). Needs the restoration UI, or buy Storage Racks, or this DevTools: autoRestore / resetProfile.")
	end
	if counted == 0 and counts.Unopened == 0 then
		if data.cash >= cheapest then
			table.insert(lines, `NEXT: buy a crate at the Supply Warehouse (cheapest ${cheapest})`)
		else
			problems += 1
			table.insert(lines, `STUCK: no items, no boxes and only ${data.cash} (cheapest crate ${cheapest}). Claim the free delivery when it is ready.`)
		end
	end
	local sessionNow = S.RestorationService.GetSession(player)
	if sessionNow then
		table.insert(lines, `restoration session open on {sessionNow.uid} (step {sessionNow.stepIndex})`)
	end
	table.insert(lines, if problems == 0 then "verdict: not stuck" else `verdict: {problems} problem(s)`)
	return true, lines
end

-- e2e(player): walks the player through the whole loop on the LIVE services (see Tests/EndToEndCheck), then restores the profile
function commands.e2e(player: Player)
	local EndToEndCheck = require(script.Parent.Parent.Tests.EndToEndCheck)
	local lines, passed, failed = EndToEndCheck.run(S, player, function(command: string, ...)
		local handler = commands[command]
		if handler == nil then
			return false, "unknown command"
		end
		local ok, success, value = pcall(handler, player, ...)
		if not ok then
			return false, "command errored: " .. tostring(success)
		end
		return success, value
	end)
	return failed == 0, { passed = passed, failed = failed, lines = lines }
end

-- testAll(player, withE2E?): runs EVERY automated check one after another and returns one summary (name, passed, failed, first failures).
-- Each check works on copies and fake data, so your profile is safe. withE2E = true also walks the live loop (about 70 s, restores your profile after).
local ALL_CHECKS = {
	{ "ConfigCheck", function() return ReplicatedStorage.Shared:FindFirstChild("Tests") and ReplicatedStorage.Shared.Tests:FindFirstChild("ConfigCheck") end },
	{ "SystemsCheck", function() return script.Parent.Parent.Tests:FindFirstChild("SystemsCheck") end },
	{ "PlotCheck", function() return script.Parent.Parent.Tests:FindFirstChild("PlotCheck") end, true },
	{ "DisplayCheck", function() return script.Parent.Parent.Tests:FindFirstChild("DisplayCheck") end },
	{ "CustomerCheck", function() return script.Parent.Parent.Tests:FindFirstChild("CustomerCheck") end },
	{ "RestorationCheck", function() return script.Parent.Parent.Tests:FindFirstChild("RestorationCheck") end },
	{ "SettingsCheck", function() return script.Parent.Parent.Tests:FindFirstChild("SettingsCheck") end },
	{ "TutorialCheck", function() return script.Parent.Parent.Tests:FindFirstChild("TutorialCheck") end },
	{ "MinigamesCheck", function() return script.Parent.Parent.Tests:FindFirstChild("MinigamesCheck") end },
	{ "CashierCheck", function() return script.Parent.Parent.Tests:FindFirstChild("CashierCheck") end }, -- Dev 3: till speed/mistake rules
	{ "StorageShelfCheck", function() return script.Parent.Parent.Tests:FindFirstChild("StorageShelfCheck") end }, -- Dev 3: storage room shelf rule
	{ "SkinCheck", function() return script.Parent.Parent.Tests:FindFirstChild("SkinCheck") end }, -- Dev 3: skins stall stock + buy / apply / draw
	{ "LayoutCheck", function() return script.Parent.Parent.Tests:FindFirstChild("LayoutCheck") end }, -- Dev 1: edit-mode layout rules (RequestSaveLayout)
	{ "PersonalityCheck", function() return script.Parent.Parent.Tests:FindFirstChild("PersonalityCheck") end }, -- Dev 1: customer personalities + haggle roll + buy chance
	{ "PaintCheck", function() return script.Parent.Parent.Tests:FindFirstChild("PaintCheck") end }, -- Dev 1: paints (buy / apply / draw) + skin wishlist
	{ "DevToolsCheck", function() return script.Parent.Parent.Tests:FindFirstChild("DevToolsCheck") end, true },
}

function commands.testAll(player: Player, withE2E: any)
	local summary = {}
	local totalPassed, totalFailed = 0, 0
	for _, entry in ALL_CHECKS do
		local name, find, commandBarOnly = entry[1], entry[2], entry[3]
		local module = find()
		if commandBarOnly then
			-- these two clone scripts and read their Source, which only the Studio command bar may do; running them here would
			-- crash halfway and leave a copy of the plots in Workspace
			table.insert(summary, `{name}: SKIPPED here, run it from the command bar: require(game.ServerScriptService.Server.Tests.{name}).run()`)
		elseif module == nil then
			table.insert(summary, `{name}: MISSING (not in this place)`)
			totalFailed += 1
		else
			local ok, lines, passed, failed = pcall(function()
				local first, second, third = require(module).run()
				if type(first) == "number" then
					return {}, first, second -- ConfigCheck returns pass, fail, text
				end
				return first, second, third
			end)
			if not ok and string.find(tostring(lines), "capability", 1, true) then
				-- PlotCheck and DevToolsCheck clone scripts and read their Source: only the Studio command bar may do that
				table.insert(summary, `{name}: SKIPPED here (run it from the command bar: require(game.ServerScriptService.Server.Tests.{name}).run())`)
			elseif not ok then
				totalFailed += 1
				table.insert(summary, `{name}: CRASHED {tostring(lines)}`)
			else
				passed, failed = tonumber(passed) or 0, tonumber(failed) or 0
				totalPassed += passed
				totalFailed += failed
				local text = `{name}: {passed} passed, {failed} failed`
				if failed > 0 and type(lines) == "table" then
					for _, line in lines do
						if string.sub(line, 1, 4) == "FAIL" then
							text ..= "\n    " .. line
							break
						end
					end
				end
				table.insert(summary, text)
			end
		end
	end
	if withE2E == true then
		local ok, success, value = pcall(commands.e2e, player)
		if ok and value then
			totalPassed += value.passed
			totalFailed += value.failed
			table.insert(summary, `EndToEnd (live loop): {value.passed} passed, {value.failed} failed`)
		else
			totalFailed += 1
			table.insert(summary, "EndToEnd: CRASHED " .. tostring(success))
		end
	end
	table.insert(summary, `ALL: {totalPassed} passed, {totalFailed} failed -> {if totalFailed == 0 then "GREEN" else "RED"}`)
	return totalFailed == 0, summary
end

-- maxUpgrades(player): every upgrade to its max level for free (also shows decor and slots)
function commands.maxUpgrades(player: Player)
	for id, def in Upgrades do
		S.DataService.Set(player, "upgrades." .. id, def.maxLevel)
	end
	S.PlotService.RefreshSlots(player)
	return true, nil
end

-- resetProfile(player): back to a brand-new player (default data, first Rubber Duck box again). Test profiles only.
function commands.resetProfile(player: Player)
	for key, value in S.DataService.GetTemplate() do
		if key ~= "version" then
			S.DataService.Set(player, key, value)
		end
	end
	S.PlotService.RefreshSlots(player)
	S.DisplayService.SyncSlots(player) -- the shelves are empty now: clear their ItemId / Golden / Stars attributes
	S.ShipmentService.GrantFirstBox(player)
	return true, nil
end

-- dump(player): a copy of all saved data
function commands.dump(player: Player)
	return true, S.DataService.Get(player)
end

local function run(command: any, player: any, ...: any)
	if type(command) ~= "string" or commands[command] == nil then
		return false, "unknown command (try 'help')"
	end
	if command ~= "help" and not Validate.isPlayer(player) then
		return false, "second argument must be a Player"
	end
	local ok, success, value = pcall(commands[command], player, ...)
	if not ok then
		return false, "command errored: " .. tostring(success)
	end
	return success, value
end

function DevTools.Init(services)
	S = services
end

function DevTools.Start()
	if not RunService:IsStudio() then
		return -- live servers get no tools at all
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DevTools"
	fn.OnInvoke = run
	fn.Parent = ServerStorage
	log.info("Studio only: ServerStorage.DevTools ready. Try: game.ServerStorage.DevTools:Invoke('help')")
end

return DevTools
