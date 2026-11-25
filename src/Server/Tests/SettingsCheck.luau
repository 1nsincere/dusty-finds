-- SettingsCheck.luau (ServerScriptService.Server.Tests.SettingsCheck)
-- Purpose: tests SettingsService (save settings, playtime) on a COPY with a fake in-memory DataService and a fake clock.
-- Owner: Dev 1 (Ace). Never touches saved data. Run while Playing (Server):
--   require(game.ServerScriptService.Server.Tests.SettingsCheck).run()

local ServerScriptService = game:GetService("ServerScriptService")

local SettingsCheck = {}

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
		stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
		settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
	}
end

local function makeFakeDataService()
	local store: { [any]: any } = {}
	local fake = { _store = store }
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
		if node == nil then
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

function SettingsCheck.run()
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
	kit.Name = "SettingsCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	ServerScriptService.Server.Services.SettingsService:Clone().Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local fakeDS = makeFakeDataService()
		local Settings = require(services.SettingsService)
		Settings.Init({ DataService = fakeDS })

		local p = { UserId = 9001, Name = "Mock1", DisplayName = "Mock1" }
		fakeDS._store[p] = newData()
		local function settings()
			return fakeDS._store[p].settings
		end

		-- ===== settings =====
		check("save: one known key changes only that key", Settings.Save(p, { music = false }) and settings().music == false and settings().sfx == true)
		check("save: several keys at once", Settings.Save(p, { sfx = false, reduceEffects = true, announcements = false }) and settings().sfx == false and settings().reduceEffects == true and settings().announcements == false)
		check("save: setting it back works", Settings.Save(p, { music = true }) and settings().music == true)
		local before = deepCopy(settings())
		check("save: an unknown key is refused and nothing is saved", select(2, Settings.Save(p, { music = false, hack = true })) == "badKey" and settings().music == before.music)
		check("save: a non-boolean value is refused (number, text, nil-ish table)", select(2, Settings.Save(p, { music = 1 })) == "badValue" and select(2, Settings.Save(p, { music = "false" })) == "badValue" and select(2, Settings.Save(p, { music = {} })) == "badValue")
		check("save: one bad value refuses the whole request", select(2, Settings.Save(p, { sfx = true, music = "x" })) == "badValue" and settings().sfx == before.sfx)
		check("save: not a table is refused", select(2, Settings.Save(p, nil)) == "notTable" and select(2, Settings.Save(p, "music")) == "notTable" and select(2, Settings.Save(p, true)) == "notTable")
		check("save: an empty table is refused", select(2, Settings.Save(p, {})) == "empty")
		check("save: array-style tables (number keys) are refused", select(2, Settings.Save(p, { true, false })) == "badKey")
		check("save: nested keys can't reach other data (\"cash\" or dotted key)", select(2, Settings.Save(p, { cash = true })) == "badKey" and select(2, Settings.Save(p, { ["music.x"] = true })) == "badKey" and fakeDS._store[p].cash == 100)
		check("save: settings is still exactly the 4 known keys", (function()
			local n = 0
			for _ in settings() do
				n += 1
			end
			return n == 4
		end)())
		-- auto sell (2026-11-25): one key per Economy.AutoSellRarities entry; Legendary and up are not settings at all
		check("save: auto sell for Common and Epic is accepted", Settings.Save(p, { autoSellCommon = true, autoSellEpic = true }) and settings().autoSellCommon == true and settings().autoSellEpic == true)
		check("save: auto sell for Legendary / Mythic is refused", select(2, Settings.Save(p, { autoSellLegendary = true })) == "badKey" and select(2, Settings.Save(p, { autoSellMythic = true })) == "badKey" and settings().autoSellLegendary == nil)
		local stranger = { UserId = 9002, Name = "NoData", DisplayName = "NoData" }
		check("save: a player with no data fails safely", select(2, Settings.Save(stranger, { music = false })) == "saveFailed")

		-- ===== playtime =====
		check("playtime: untracked player adds nothing", Settings.AddPlaytime(p, 100) == 0)
		Settings.StartTracking(p, 1000)
		check("playtime: under 1 second adds nothing", Settings.AddPlaytime(p, 1000.9) == 0 and fakeDS._store[p].stats.playSeconds == 0)
		check("playtime: 30 seconds adds 30", Settings.AddPlaytime(p, 1030) == 30 and fakeDS._store[p].stats.playSeconds == 30)
		check("playtime: asking again right away adds nothing (no double counting)", Settings.AddPlaytime(p, 1030) == 0 and fakeDS._store[p].stats.playSeconds == 30)
		check("playtime: 45.7 s later adds 45, the 0.7 s is kept", Settings.AddPlaytime(p, 1075.7) == 45 and fakeDS._store[p].stats.playSeconds == 75)
		check("playtime: the kept fraction is used next time (0.7 + 0.3 = 1 more second)", Settings.AddPlaytime(p, 1076.7) == 1 and fakeDS._store[p].stats.playSeconds == 76)
		check("playtime: a clock that goes backwards adds nothing", Settings.AddPlaytime(p, 500) == 0 and fakeDS._store[p].stats.playSeconds == 76)
		local noData = { UserId = 9003, Name = "Gone", DisplayName = "Gone" }
		Settings.StartTracking(noData, 0)
		check("playtime: a tracked player whose data is gone adds nothing, no error", Settings.AddPlaytime(noData, 50) == 0)
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[SettingsCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return SettingsCheck
