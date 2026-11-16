-- RestorationCheck.luau (ServerScriptService.Server.Tests.RestorationCheck)
-- Purpose: tests the restoration rules (Services/RestorationService) on copies with a fake in-memory DataService.
-- Owner: Dev 1 (Ace). Depends on: RestorationService,EconomyService, InventoryService, CollectionBookService, Shared.Config.
-- Uses a fake clock (the service takes an optional `now`), so no waiting. Never touches saved data.
-- Run while Playing (Server): require(game.ServerScriptService.Server.Tests.RestorationCheck).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RestorationCheck = {}

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local c = {}
	for k, x in v do
		c[k] = deepCopy(x)
	end
	return c
end

local function newData()
	return {
		version = 1, cash = 100, xp = 0, level = 1, inventory = {}, upgrades = {}, collection = {},
		likes = { received = 0, givenToday = {}, rewardedToday = 0, day = 0 },
		stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
		timers = { lastFreeDelivery = 0 }, tutorial = { step = 0, done = false },
		settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
	}
end

local function makeFakeDataService()
	local store: { [any]: any } = {}
	local fake = { _store = store }
	function fake.Get(p)
		return store[p] and deepCopy(store[p])
	end
	function fake.GetValue(p, path)
		local node = store[p]
		for _, part in string.split(path, ".") do
			if type(node) ~= "table" then
				return nil
			end
			node = node[part]
		end
		return deepCopy(node)
	end
	function fake.Set(p, path, value)
		if fake.failPath ~= nil and string.find(path, fake.failPath, 1, true) ~= nil then
			return false -- test hook: simulate a failed save
		end
		local parts = string.split(path, ".")
		local node = store[p]
		if node == nil or node[parts[1]] == nil or (value == nil and #parts == 1) then
			return false
		end
		for i = 1, #parts - 1 do
			node = node[parts[i]]
			if type(node) ~= "table" then
				return false
			end
		end
		local old = node[parts[#parts]]
		if old ~= nil and value ~= nil and type(old) ~= type(value) then
			return false
		end
		node[parts[#parts]] = deepCopy(value)
		return true
	end
	function fake.OnPlayerLoaded() end
	function fake.OnPlayerReleasing() end
	return fake
end

function RestorationCheck.run()
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

	local kit = Instance.new("Folder")
	kit.Name = "RestorationKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	for _, name in { "EconomyService", "InventoryService", "CollectionBookService" } do
		ServerScriptService.Server.Services[name]:Clone().Parent = services
	end
	ServerScriptService.Server.Services.RestorationService:Clone().Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local Config = ReplicatedStorage.Shared.Config
		local Items = require(Config.Items)
		local Economy = require(Config.Economy)

		local fakeDS = makeFakeDataService()
		local S: { [string]: any } = { DataService = fakeDS, PlotService = { GetPlot = function() return nil end, RefreshSlots = function() end } }
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService" } do
			S[name] = require(services[name])
		end
		S.RestorationService = require(services.RestorationService)
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "RestorationService" } do
			S[name].Init(S)
		end
		local Inv, Res = S.InventoryService, S.RestorationService
		-- always sends the live session id, like the client would
		local function rep(player, uid, stepIndex, score, now)
			local session = Res.GetSession(player)
			return Res.ReportStepComplete(player, uid, stepIndex, score, session and session.id :: any, now)
		end

		local count = 0
		local function newPlayer(): any
			count += 1
			local p = { UserId = 7000 + count, Name = "Mock" .. count, DisplayName = "Mock" .. count }
			fakeDS._store[p] = newData()
			return p
		end
		local function data(p)
			return fakeDS.Get(p)
		end
		-- Reports every remaining step with `score`, advancing the fake clock by exactly the minimum time each time.
		-- Returns the last result.
		local function finishAll(p, uid, score, clock: number)
			local last
			local session = Res.GetSession(p)
			local item = Inv.Get(p, uid)
			local recipe = Items[item.itemId].recipe
			for stepIndex = session.stepIndex, #recipe do
				clock += Economy.MinStepSeconds[recipe[stepIndex].type]
				local _, _, result = rep(p, uid, stepIndex, score, clock)
				last = result
			end
			return last
		end

		-- ===== starting =====
		local p = newPlayer()
		local robot = Inv.Add(p, "TinRobot", { state = "Dirty" })
		local startOk, _, info = Res.StartRestore(p, robot, "Bench1", 0)
		check("start: Dirty item becomes InProgress, session opens at step 1", startOk and info.stepIndex == 1 and Inv.Get(p, robot).state == "InProgress" and Res.GetSession(p) ~= nil)
		check("start: recipe has the 5 TinRobot steps", #info.recipe == 5)
		check("start: a second start is refused while restoring", select(2, Res.StartRestore(p, robot, "Bench1", 0)) == "alreadyRestoring")
		Res.ExitRestore(p, robot)
		check("start: unknown uid refused", select(2, Res.StartRestore(p, "nope", "Bench1", 0)) == "noItem")
		local box = Inv.Add(p, "Teacup")
		check("start: an Unopened box can't be restored", select(2, Res.StartRestore(p, box, "Bench1", 0)) == "notRestorable")
		local done = Inv.Add(p, "Teacup", { state = "Restored" })
		check("start: a Restored item can't be restored again", select(2, Res.StartRestore(p, done, "Bench1", 0)) == "notRestorable")
		check("start: bad bench names refused", select(2, Res.StartRestore(p, robot, "Bench9", 0)) == "badBench" and select(2, Res.StartRestore(p, robot, 5, 0)) == "badBench")
		check("start: Bench2 needs the Back Room", select(2, Res.StartRestore(p, robot, "Bench2", 0)) == "noBackRoom")
		fakeDS.Set(p, "upgrades.BackRoom", 1)
		check("start: Bench2 works once the Back Room is owned", select(1, Res.StartRestore(p, robot, "Bench2", 0)))
		Res.ExitRestore(p, robot)

		-- ===== reporting steps =====
		Res.StartRestore(p, robot, "Bench1", 100)
		check("report: no active session for another uid", select(2, rep(p, "other", 1, 100, 200)) == "wrongItem")
		check("report: wrong step index refused (2 while on 1)", select(2, rep(p, robot, 2, 100, 200)) == "wrongStep")
		check("report: fractional / nil step index refused", select(2, rep(p, robot, 1.5, 100, 200)) == "wrongStep" and select(2, rep(p, robot, nil :: any, 100, 200)) == "wrongStep")
		check("report: bad scores refused", select(2, rep(p, robot, 1, 0 / 0, 200)) == "badScore" and select(2, rep(p, robot, 1, "100" :: any, 200)) == "badScore" and select(2, rep(p, robot, 1, nil :: any, 200)) == "badScore" and select(2, rep(p, robot, 1, math.huge, 200)) == "badScore")
		check("report: Wipe in 2.9 s is too fast", select(2, rep(p, robot, 1, 100, 102.9)) == "tooFast" and Inv.Get(p, robot).stepIndex == 1)
		local okStep, _, r1 = rep(p, robot, 1, 150, 103)
		check("report: Wipe at exactly 3 s is accepted, score clamped to 100", okStep and r1.finished == false and r1.stepIndex == 2 and Inv.Get(p, robot).stepScores[1] == 100)
		check("report: progress is saved in the item (stepIndex 2)", Inv.Get(p, robot).stepIndex == 2 and #Inv.Get(p, robot).stepScores == 1)
		check("report: the same step can't be reported twice", select(2, rep(p, robot, 1, 100, 110)) == "wrongStep")
		check("report: Scrape needs 4 s from the previous step", select(2, rep(p, robot, 2, 100, 106.9)) == "tooFast")
		local _, _, r2 = rep(p, robot, 2, -20, 107)
		check("report: negative score is clamped to 0", Inv.Get(p, robot).stepScores[2] == 0 and r2.stepIndex == 3)

		-- ===== exit and resume =====
		check("exit: wrong uid refused, right uid ends the session", Res.ExitRestore(p, "other") == false and Res.ExitRestore(p, robot) and Res.GetSession(p) == nil)
		check("exit: reporting after exit has no session", select(2, rep(p, robot, 3, 100, 500)) == "noSession")
		check("exit: the item keeps its progress (InProgress, step 3, 2 scores)", Inv.Get(p, robot).state == "InProgress" and Inv.Get(p, robot).stepIndex == 3 and #Inv.Get(p, robot).stepScores == 2)
		local _, _, resume = Res.StartRestore(p, robot, "Bench1", 1000)
		check("resume: starts again at step 3", resume.stepIndex == 3 and #Res.GetSession(p).scores == 2)
		local final = finishAll(p, robot, 100, 1000)
		-- scores 100, 0, then 100, 100, 100 = 400 / 5 = 80 average -> 2 stars (>= 70, < 90)
		check("finish: average 80 gives 2 stars", final.finished and final.stars == 2 and math.abs(final.average - 80) < 1e-9, final and final.stars)
		check("finish: item is Restored with 2 stars and 5 scores", Inv.Get(p, robot).state == "Restored" and Inv.Get(p, robot).stars == 2 and #Inv.Get(p, robot).stepScores == 5)

		-- ===== payouts =====
		local d = data(p)
		-- TinRobot is Epic (80 XP). 80 XP: level 1 needs 40 -> level 2 with 40 left; level-up pays $50 x 2 = $100.
		check("finish: Epic gives 80 XP (level 2, 40 xp left, +$100)", d.level == 2 and d.xp == 40 and d.cash == 200, `{d.level},{d.xp},{d.cash}`)
		check("finish: stats.restored is 1 and collection has best stars 2", d.stats.restored == 1 and d.collection.TinRobot.bestStars == 2)
		check("finish: value shown = sellPrice 2 stars ($180)", final.value == 180)
		check("finish: the session is closed", Res.GetSession(p) == nil)

		-- ===== quality maths and tools =====
		local q = newPlayer()
		local function restoreWith(player, itemId: string, score: number, opts)
			local uid = Inv.Add(player, itemId, opts or { state = "Dirty" })
			Res.StartRestore(player, uid, "Bench1", 0)
			local result = finishAll(player, uid, score, 0)
			Inv.Remove(player, uid) -- keep the inventory under its capacity of 8
			return result
		end
		check("quality: all 100 -> 3 stars", restoreWith(q, "TinRobot", 100).stars == 3)
		check("quality: all 90 -> 3 stars", restoreWith(q, "TinRobot", 90).stars == 3)
		check("quality: all 89 -> 2 stars", restoreWith(q, "TinRobot", 89).stars == 2)
		check("quality: all 70 -> 2 stars", restoreWith(q, "TinRobot", 70).stars == 2)
		check("quality: all 69 -> 1 star", restoreWith(q, "TinRobot", 69).stars == 1)
		check("quality: all 0 -> 1 star", restoreWith(q, "TinRobot", 0).stars == 1)
		fakeDS.Set(q, "upgrades.RepairToolkit", 3)
		fakeDS.Set(q, "upgrades.Polisher", 3)
		check("tools: Toolkit L3 + Polisher L3 = +10, so 60 reaches 70 = 2 stars", restoreWith(q, "TinRobot", 60).stars == 2)
		check("tools: bonus is capped at +10 (average 59 stays 1 star)", restoreWith(q, "TinRobot", 59).stars == 1)
		fakeDS.Set(q, "upgrades.RepairToolkit", 1)
		fakeDS.Set(q, "upgrades.Polisher", 1)
		check("tools: level 1 tools add nothing (average 60 stays 1 star)", restoreWith(q, "TinRobot", 60).stars == 1)

		local g = newPlayer()
		local goldResult = restoreWith(g, "TinRobot", 100, { state = "Dirty", golden = true })
		check("golden: 3 stars Golden TinRobot is worth $702 (180 x 1.3 x 3)", goldResult.value == 702, goldResult.value)
		local t2 = newPlayer()
		local vinyl = restoreWith(t2, "VinylRecord", 100)
		check("XP: tier 2 Common gives 10 x 2 = 20 XP", vinyl.xp == 20 and data(t2).xp == 20, vinyl.xp)

		-- ===== session ids, failed saves (docs/Restoration_Contract.md sections 2 and 3) =====
		local f = newPlayer()
		local fr = Inv.Add(f, "TinRobot", { state = "Dirty" })
		local _, _, i1 = Res.StartRestore(f, fr, "Bench1", 0)
		local firstId = i1.sessionId
		check("session: start returns a session id", type(firstId) == "number" and Res.GetSession(f).id == firstId)
		check("session: a wrong or missing id is refused as staleSession", select(2, Res.ReportStepComplete(f, fr, 1, 100, firstId + 99, 10)) == "staleSession" and select(2, Res.ReportStepComplete(f, fr, 1, 100, nil :: any, 10)) == "staleSession" and Inv.Get(f, fr).stepIndex == 1)
		Res.ExitRestore(f, fr)
		local _, _, i2 = Res.StartRestore(f, fr, "Bench1", 100)
		check("session: a new session gets a new id; the old id is stale", i2.sessionId ~= firstId and select(2, Res.ReportStepComplete(f, fr, 1, 100, firstId, 110)) == "staleSession")

		fakeDS.failPath = "stepIndex"
		local failOk, failReason = rep(f, fr, 1, 100, 110)
		check("save fails mid-recipe: refused with saveFailed", failOk == false and failReason == "saveFailed")
		check("save fails mid-recipe: session stays on step 1", Res.GetSession(f).stepIndex == 1 and #Res.GetSession(f).scores == 0)
		fakeDS.failPath = nil
		local retryOk, _, retry = rep(f, fr, 1, 100, 111)
		check("save fails mid-recipe: the same step works on retry", retryOk and retry.stepIndex == 2 and #Res.GetSession(f).scores == 1)
		-- a failed index save may leave one extra score in the item: resume must trim it
		fakeDS.failPath = "stepIndex"
		rep(f, fr, 2, 100, 120)
		fakeDS.failPath = nil
		check("save fails: an extra score may be saved in the item", #Inv.Get(f, fr).stepScores == 2 and Inv.Get(f, fr).stepIndex == 2)
		Res.ExitRestore(f, fr)
		local _, _, resumed = Res.StartRestore(f, fr, "Bench1", 200)
		check("resume trims the unfinished step's score", resumed.stepIndex == 2 and #Res.GetSession(f).scores == 1)

		-- final step: the state is saved last; a failure awards nothing and keeps the item InProgress
		local h = newPlayer()
		local hr = Inv.Add(h, "Teacup", { state = "Dirty" })
		Res.StartRestore(h, hr, "Bench1", 0)
		local recipe = Items.Teacup.recipe
		local clock = 0
		for stepIndex = 1, #recipe - 1 do
			clock += Economy.MinStepSeconds[recipe[stepIndex].type]
			rep(h, hr, stepIndex, 100, clock)
		end
		clock += Economy.MinStepSeconds[recipe[#recipe].type]
		fakeDS.failPath = ".state"
		local lastOk, lastReason = rep(h, hr, #recipe, 100, clock)
		check("final save fails: saveFailed, nothing awarded", lastOk == false and lastReason == "saveFailed" and data(h).xp == 0 and data(h).stats.restored == 0 and next(data(h).collection) == nil)
		check("final save fails: item is still InProgress and the session is open", Inv.Get(h, hr).state == "InProgress" and Res.GetSession(h) ~= nil)
		fakeDS.failPath = nil
		local lastRetry = select(3, rep(h, hr, #recipe, 100, clock))
		check("final step works on retry: Restored once, stats paid once", lastRetry ~= nil and lastRetry.finished and Inv.Get(h, hr).state == "Restored" and data(h).stats.restored == 1 and Res.GetSession(h) == nil)
		check("a Restored item can't be started again (no double reward)", select(2, Res.StartRestore(h, hr, "Bench1", 0)) == "notRestorable")
		check("report after the item is done has no session", select(2, Res.ReportStepComplete(h, hr, #recipe, 100, 1, clock + 10)) == "noSession")
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[RestorationCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return RestorationCheck
