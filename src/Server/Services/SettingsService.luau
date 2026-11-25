-- SettingsService.luau
-- Purpose: saves the player's settings (RequestSaveSettings) and counts playtime (stats.playSeconds).
-- Owner: Dev 1 (Ace) for the server rules; the settings screen that calls it is Dev 3 (SettingsController).
-- Depends on: DataService, Shared.Remotes. Server only.
-- Settings are validated hard: only the known keys, only true/false. A client can never write anything else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SettingsService = {}
local DEBUG = true
local log = Log.new("SettingsService", DEBUG)

-- The keys a client may change (they match `settings` in the data template). Add a key here AND in the template.
local KNOWN_KEYS = { music = true, sfx = true, reduceEffects = true, announcements = true }
-- auto sell: one key per allowed rarity, built from config so the list lives in one place (Economy.AutoSellRarities)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
for _, rarity in Economy.AutoSellRarities do
	KNOWN_KEYS["autoSell" .. rarity] = true
end
local PLAYTIME_TICK_SECONDS = 30 -- how often playtime is added while playing (also added when the player leaves)

local DataService = nil
local lastTick: { [any]: number } = {} -- [Player] = clock time of the last playtime update

-- Saves some or all settings. `settings` = { music = false, ... }: partial is fine.
-- All-or-nothing: if any key is unknown or any value is not a boolean, nothing is saved.
-- Returns ok, reason (notTable, empty, badKey, badValue, saveFailed).
function SettingsService.Save(player: any, settings: any): (boolean, string?)
	if type(settings) ~= "table" then
		return false, "notTable"
	end
	local count = 0
	for key, value in settings do
		count += 1
		if type(key) ~= "string" or not KNOWN_KEYS[key] then
			return false, "badKey"
		end
		if type(value) ~= "boolean" then
			return false, "badValue"
		end
	end
	if count == 0 then
		return false, "empty"
	end
	for key, value in settings do
		if not DataService.Set(player, "settings." .. key, value) then
			return false, "saveFailed"
		end
	end
	return true, nil
end

-- Playtime ---------------------------------------------------------------------------------------------------------

-- Starts counting for a player (called when their data loads). `now` is optional (tests pass a fake clock).
function SettingsService.StartTracking(player: any, now: number?)
	lastTick[player] = now or os.clock()
end

-- Adds the whole seconds since the last update to stats.playSeconds. The leftover fraction is kept for next time,
-- so nothing is lost. Returns the seconds added (0 if the player isn't tracked or data isn't loaded).
function SettingsService.AddPlaytime(player: any, now: number?): number
	local last = lastTick[player]
	if last == nil then
		return 0
	end
	local time = now or os.clock()
	local seconds = math.floor(time - last)
	if seconds < 1 then
		return 0
	end
	local total = DataService.GetValue(player, "stats.playSeconds")
	if type(total) ~= "number" then
		return 0
	end
	lastTick[player] = last + seconds
	DataService.Set(player, "stats.playSeconds", total + seconds)
	return seconds
end

function SettingsService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function SettingsService.Start()
	Remotes.RequestSaveSettings.OnServerEvent:Connect(function(player, settings)
		if not Validate.rateLimit(player, "RequestSaveSettings", 2) then
			return
		end
		local ok, reason = SettingsService.Save(player, settings)
		if not ok then
			log.warn(`{player.Name}: settings refused ({reason})`)
		end
	end)

	DataService.OnPlayerLoaded(function(player)
		SettingsService.StartTracking(player)
	end)
	DataService.OnPlayerReleasing(function(player)
		SettingsService.AddPlaytime(player) -- last partial interval, while the data can still be written
		lastTick[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(PLAYTIME_TICK_SECONDS)
			for player in lastTick do
				local ok, err = pcall(SettingsService.AddPlaytime, player)
				if not ok then
					log.warn("playtime update failed:", tostring(err))
				end
			end
		end
	end)
	log.info("Start")
end

return SettingsService
