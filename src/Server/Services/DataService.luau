-- DataService.luau
-- Purpose: load/save each player's data with ProfileStore, and send it to their client (docs/03 §9, §10.5).
-- Owner: Dev 1 (Ace). Depends on: ServerScriptService.Packages.ProfileStore, Shared.Remotes.
-- Other services read/write player data ONLY through DataService.Get / DataService.Set,
-- so every change that matters is pushed to the client with one StateChanged event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = {}
local DEBUG = true

-- Live and test data are kept apart so testing in Studio never touches real players' data.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_DEV" else "PlayerData_v1"
local KICK_MESSAGE = "Your data is still loading elsewhere. Please rejoin in a minute."
local INITIAL_STATE_TIMEOUT = 60 -- seconds a client may wait for its profile to finish loading

-- Docs/03 §10.5. Changing a field here changes saved data: ask the team first (CLAUDE.md §6.6).
local TEMPLATE = {
	version = 1,
	cash = 100,
	xp = 0,
	level = 1,
	inventory = {}, -- [uid] = ItemInstance
	upgrades = {}, -- [upgradeId] = level owned
	collection = {}, -- [itemId] = { found, bestStars, golden }
	likes = { received = 0, givenToday = {}, rewardedToday = 0, day = 0 },
	stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
	timers = { lastFreeDelivery = 0 },
	tutorial = { step = 0, done = false },
	settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
}

local store = nil
local profiles = {} -- [Player] = Profile (only while loaded)

local function log(...)
	if DEBUG then
		print("[DataService]", ...)
	end
end

-- Plain-table copy so the client snapshot can never share tables with the live data.
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Placeholder for future data-version upgrades. Add one `if data.version < N` block per change.
local function migrate(data)
	if data.version < TEMPLATE.version then
		data.version = TEMPLATE.version
	end
end

local function onPlayerAdded(player: Player)
	local key = "Player_" .. player.UserId
	-- Cancel: stop waiting for the session if the player already left.
	local profile = store:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			warn("[DataService] could not start session for", player.Name)
			player:Kick(KICK_MESSAGE)
		end
		return
	end

	-- Player left while we were loading: release the profile so it saves and unlocks.
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:Reconcile() -- fill in any fields added to the template since this player last played
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			-- Another server took the profile: don't let the player keep playing with unsaved data.
			player:Kick(KICK_MESSAGE)
		end
	end)

	profiles[player] = profile
	log(`profile loaded for {player.Name}: cash={profile.Data.cash} level={profile.Data.level}`)
	-- TODO (Stage 2): PlotService.AssignPlot(player) and rebuild the plot from data here.
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession() -- triggers OnSessionEnd, which clears profiles[player]
		log("session ended for", player.Name)
	end
end

-- The live data table for a player, or nil if the profile isn't loaded yet.
-- Server only. Treat it as read-only: change values with DataService.Set so the client hears about it.
function DataService.Get(player: Player)
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	return profile.Data
end

-- Set one value by path, e.g. Set(player, "cash", 150) or Set(player, "upgrades.CleaningBrush", 1),
-- then push the change to that player's client. Returns true if it worked.
function DataService.Set(player: Player, path: string, value: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(path) ~= "string" or path == "" then
		return false
	end
	local data = DataService.Get(player)
	if data == nil then
		return false
	end

	local parts = string.split(path, ".")
	local node = data
	for i = 1, #parts - 1 do
		local nextNode = node[parts[i]]
		if type(nextNode) ~= "table" then
			warn("[DataService] Set: bad path", path)
			return false
		end
		node = nextNode
	end
	node[parts[#parts]] = value

	Remotes.StateChanged:FireClient(player, path, deepCopy(value))
	return true
end

function DataService.Init(_services)
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
	log(`Init, store = {STORE_NAME}`)
end

function DataService.Start()
	-- A client asks once for its full data after joining. We wait (with a limit) for the profile to load.
	Remotes.GetInitialState.OnServerInvoke = function(player)
		local waited = 0
		while DataService.Get(player) == nil do
			if player.Parent ~= Players or waited >= INITIAL_STATE_TIMEOUT then
				return nil
			end
			task.wait(0.25)
			waited += 0.25
		end
		return deepCopy(DataService.Get(player))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players who joined before Start ran (can happen in Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	log(`Start, DataStoreState = {ProfileStore.DataStoreState}`)
end

return DataService
