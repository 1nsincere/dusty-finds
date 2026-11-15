-- DevToolsCheck.luau (ServerScriptService.Server.Tests.DevToolsCheck)
-- Purpose: tests the Studio-only DevTools commands against COPIES of the services and a FAKE in-memory DataService.
-- Owner: Dev 1 (Ace). Depends on: DevTools and the services it calls.
-- Never touches PlayerData_DEV: resetProfile / maxUpgrades would overwrite a real test profile, so they only run on fake data.
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.DevToolsCheck).run()

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local DevToolsCheck = {}

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

local TEMPLATE = {
	version = 1, cash = 100, xp = 0, level = 1, inventory = {}, upgrades = {}, collection = {},
	likes = { received = 0, givenToday = {}, rewardedToday = 0, day = 0 },
	stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
	timers = { lastFreeDelivery = 0 },
	tutorial = { step = 0, done = false },
	settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
}

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
	function fake.GetTemplate()
		return deepCopy(TEMPLATE)
	end
	function fake.OnPlayerLoaded() end
	function fake.OnPlayerReleasing() end
	return fake
end

function DevToolsCheck.run()
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

	local player = game.Players:GetPlayers()[1]
	if player == nil then
		return { "FAIL needs one player in the game (Play first)" }, 0, 1
	end

	local kit = Instance.new("Folder")
	kit.Name = "DevToolsCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local names = { "EconomyService", "InventoryService", "CollectionBookService", "ShipmentService", "DevTools" }
	for _, name in names do
		ServerScriptService.Server.Services[name]:Clone().Parent = services
	end
	local devSource = services.DevTools
	-- the copy uses its own object name so it can't collide with the real ServerStorage.DevTools
	devSource.Source = string.gsub(devSource.Source, 'fn%.Name = "DevTools"', 'fn.Name = "DevToolsCheckCopy"')
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local fakeDS = makeFakeDataService()
		fakeDS._store[player] = deepCopy(TEMPLATE)
		local refreshCalls = 0
		local S: { [string]: any } = {
			DataService = fakeDS,
			PlotService = { RefreshSlots = function() refreshCalls += 1 end, GetPlot = function() return nil end },
		}
		for _, name in names do
			S[name] = require(services[name])
		end
		for _, name in names do
			S[name].Init(S)
		end
		S.DevTools.Start()
		local fn = ServerStorage:FindFirstChild("DevToolsCheckCopy")
		check("Studio: the command object exists", fn ~= nil)
		if fn == nil then
			return
		end
		local function call(...)
			return fn:Invoke(...)
		end
		local function data()
			return fakeDS.Get(player)
		end

		local helpOk, helpText = call("help")
		check("help lists the commands", helpOk and string.find(helpText, "giveCash") ~= nil and string.find(helpText, "resetProfile") ~= nil)
		check("giveCash 500", call("giveCash", player, 500) and data().cash == 600)
		check("giveCash rejects bad amounts", call("giveCash", player, -5) == false and call("giveCash", player, 1.5) == false and call("giveCash", player, "9") == false and data().cash == 600)
		check("setLevel 5 clears xp", call("setLevel", player, 5) and data().level == 5 and data().xp == 0)
		check("setLevel rejects 0 and 99", call("setLevel", player, 0) == false and call("setLevel", player, 99) == false and data().level == 5)

		check("addXp adds progress", call("addXp", player, 10) and data().xp == 10 and data().level == 5)
		check("addXp rejects bad amounts", call("addXp", player, -1) == false and call("addXp", player, 2.5) == false and data().xp == 10)

		local itemOk, uid = call("giveItem", player, "TinRobot", "Restored", 3, true)
		local item = data().inventory[uid]
		check("giveItem: restored golden TinRobot with 3 stars", itemOk and item.state == "Restored" and item.stars == 3 and item.golden == true and item.itemId == "TinRobot")
		local _, uid2 = call("giveItem", player, "Teacup")
		check("giveItem defaults to a Dirty item", data().inventory[uid2].state == "Dirty")
		check("giveItem rejects unknown items", call("giveItem", player, "Nope") == false)

		local boxOk, uids = call("giveBox", player, "Starter")
		check("giveBox gives 3 Unopened items in one box", boxOk and #uids == 3 and data().inventory[uids[1]].state == "Unopened" and data().inventory[uids[1]].boxId == data().inventory[uids[3]].boxId)
		check("giveBox rejects unknown crates", call("giveBox", player, "Nope") == false)

		check("maxUpgrades sets every upgrade to max and refreshes the plot", call("maxUpgrades", player) and data().upgrades.CleaningBrush == 3 and data().upgrades.PottedPlants == 2 and data().upgrades.Showroom == 1 and refreshCalls == 1)

		check("resetProfile returns to a new player", call("resetProfile", player) and data().cash == 100 and data().level == 1 and next(data().upgrades) == nil and next(data().collection) == nil)
		local remaining = 0
		local only
		for _, it in data().inventory do
			remaining += 1
			only = it
		end
		check("resetProfile leaves only the first Rubber Duck box", remaining == 1 and only.itemId == "RubberDuck" and only.state == "Unopened")
		check("resetProfile keeps the version field", data().version == 1)

		check("unknown command refused", call("nope", player) == false)
		check("a non-player argument is refused", call("giveCash", {}, 5) == false and call("giveCash", nil, 5) == false)
		check("a command that errors is caught, not thrown", select(1, call("giveItem", player, "Teacup", "Broken")) == false)
	end)

	kit:Destroy()
	local leftover = ServerStorage:FindFirstChild("DevToolsCheckCopy")
	if leftover then
		leftover:Destroy()
	end
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[DevToolsCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return DevToolsCheck
