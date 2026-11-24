-- DataService.luau
-- Purpose: owns every player's saved data: loads it with ProfileStore, releases it, and is the ONLY way to read/write it.
-- Owner: Dev 1 (Ace). Depends on: ServerScriptService.Packages.ProfileStore, Shared.Remotes, Server.Lib.Validate.
-- Safe by design: no profile = no access. Reads return COPIES, writes go through Set (which re-checks that the
-- profile is still active), and a failed load kicks the player instead of ever creating a blank profile.
-- Spec: docs/03_Architecture.md §9 and §10.5. ProfileStore API checked against the installed source (see STATUS.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(script.Parent.Parent.Lib.Validate)

local DataService = {}
local DEBUG = true

-- Live and test data are kept apart so testing in Studio never touches real players' data.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_DEV" else "PlayerData_v1"
local LOAD_FAILED_MESSAGE = "We couldn't load your saved data. Your progress is safe. Please rejoin in a minute."
local SESSION_LOST_MESSAGE = "Your data was opened on another server. Please rejoin."
local INITIAL_STATE_TIMEOUT = 60 -- seconds a client may wait for its profile to finish loading
local MAX_VALUE_DEPTH = 8 -- deepest table we accept in Set (also stops circular tables)

-- Docs/03 §10.5 (same shape as Types.PlayerData). Changing a field changes saved data: ask the team first
-- (CLAUDE.md §6.6). Adding a field later is safe: Reconcile() fills it in for existing players.
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
	-- shelf / pedestal skins (Sean, Ace OK 2026-11-24; SkinService): owned = { [skinId] = true }; shelf / pedestal =
	-- the skin id in use, "" = the classic look. Old saves get this from Reconcile().
	skins = { owned = {}, shelf = "", pedestal = "" },
}

local store = nil
local profiles = {} -- [Player] = Profile (only while loaded and active)
local loading = {} -- [Player] = true while a load is in progress (stops double loads)
local releasing = {} -- [Player] = true while WE end their session on purpose (so it isn't treated as a lost session)
local removed = {} -- [Player] = true once PlayerRemoving fired (Parent can still be Players then, so Parent alone isn't enough)
local snapshotExtras = {} -- [key] = function(player) -> value, added to GetInitialState
local loadedCallbacks = {} -- functions(player) called right after a profile loads
local releasingCallbacks = {} -- functions(player) called just before a profile is released

local function log(...)
	if DEBUG then
		print("[DataService]", ...)
	end
end

-- Plain-table copy, so callers never share tables with the live saved data.
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

-- True if `value` can be saved by ProfileStore: strings, booleans, finite numbers, and plain tables of those.
-- A table must be either all string keys, or a gap-free list 1..n (ProfileStore errors on anything else, and a
-- failing save is retried forever, so we refuse bad values up front).
local function isStorable(value: any, depth: number): boolean
	local kind = type(value)
	if kind == "string" or kind == "boolean" then
		return true
	elseif kind == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge -- no NaN or infinity
	elseif kind ~= "table" or depth > MAX_VALUE_DEPTH then
		return false -- Instances, functions, userdata, or too deep / circular
	end

	local count, stringKeys, numberKeys = 0, 0, 0
	for k, v in value do
		count += 1
		if type(k) == "string" then
			stringKeys += 1
		elseif type(k) == "number" then
			numberKeys += 1
		else
			return false
		end
		if not isStorable(v, depth + 1) then
			return false
		end
	end
	if stringKeys > 0 and numberKeys > 0 then
		return false -- mixed table
	end
	if numberKeys > 0 and numberKeys ~= #value then
		return false -- gaps or non-integer keys in a list
	end
	return count == stringKeys + numberKeys
end

-- Placeholder for future data-version upgrades. Add one `if data.version < N` block per change.
local function migrate(data)
	if data.version < TEMPLATE.version then
		data.version = TEMPLATE.version
	end
	-- Items that were removed from Config (the item-mix change, 2026-11-16) must not stay in an old profile: every service
	-- looks items up in Config and would error on an unknown id. Drops them quietly (a few test profiles only; no live players yet).
	local Items = require(ReplicatedStorage.Shared.Config.Items)
	if type(data.inventory) == "table" then
		for uid, item in data.inventory do
			if type(item) ~= "table" or Items[item.itemId] == nil then
				data.inventory[uid] = nil
			end
		end
	end
	if type(data.collection) == "table" then
		for itemId in data.collection do
			if Items[itemId] == nil then
				data.collection[itemId] = nil
			end
		end
	end
end

-- Run every callback in a list. One broken service must not stop the others, so each runs inside pcall.
local function fire(callbacks: { (Player) -> () }, player: Player)
	for _, callback in callbacks do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("[DataService] a callback errored:", err)
		end
	end
end

-- Returns the profile only if this player's profile is loaded AND still active.
local function activeProfile(player: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	return profile
end

local function loadPlayer(player: Player)
	local key = "Player_" .. player.UserId
	-- Cancel: stop waiting for the session if the player already left.
	-- pcall: StartSessionAsync throws on some problems (e.g. "already loaded in this session"); a throw must end in a
	-- kick, never in a player stuck with no data.
	local ok, result = pcall(function()
		return store:StartSessionAsync(key, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)
	local profile = if ok then result else nil

	if profile == nil then
		-- Never create a blank profile here: that could overwrite the player's real saved data later.
		if not ok then
			warn("[DataService] StartSessionAsync errored for", player.Name, ":", result)
		end
		if player.Parent == Players and not removed[player] then
			warn("[DataService] could not start a data session for", player.Name, "- kicking, nothing was changed")
			player:Kick(LOAD_FAILED_MESSAGE)
		end
		return
	end

	-- Player left while we were loading: release the profile so it saves and unlocks. `removed` covers the moment
	-- between PlayerRemoving firing and Parent becoming nil; without it we would keep a profile (and its session
	-- lock) for a player who is already gone.
	if removed[player] or player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:Reconcile() -- fill in any fields added to the template since this player last played
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if releasing[player] then
			releasing[player] = nil -- we ended it ourselves (player leaving): nothing to kick
			return
		end
		if player.Parent == Players then
			-- Another server took the profile: don't let the player keep playing with data that won't save.
			warn("[DataService] session for", player.Name, "ended while they were still in the game - kicking")
			player:Kick(SESSION_LOST_MESSAGE)
		end
	end)

	profiles[player] = profile
	log(`profile loaded for {player.Name}: cash={profile.Data.cash} level={profile.Data.level}`)
	fire(loadedCallbacks, player)
end

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return -- already loading or loaded (Start's catch-up loop and PlayerAdded can both see the same player)
	end
	loading[player] = true
	-- Safety net: any unexpected error in loading must still clear `loading` and not leave the player without data.
	local ok, err = pcall(loadPlayer, player)
	loading[player] = nil
	local wasRemoved = removed[player]
	removed[player] = nil -- this load is over, so nothing else needs the flag (onPlayerRemoving left it for us)
	if not ok then
		warn("[DataService] loading failed for", player.Name, ":", err)
		if profiles[player] == nil and player.Parent == Players and not wasRemoved then
			player:Kick(LOAD_FAILED_MESSAGE)
		end
	end
end

local function onPlayerRemoving(player: Player)
	removed[player] = true -- first thing: an in-flight load checks this before registering its profile
	local profile = profiles[player]
	if profile then
		fire(releasingCallbacks, player) -- services can read the data one last time
		releasing[player] = true -- tells OnSessionEnd this is a normal release, not a lost session
		profile:EndSession() -- saves, then triggers OnSessionEnd, which clears profiles[player]
		log("session ended for", player.Name)
	end
	releasing[player] = nil
	if not loading[player] then
		removed[player] = nil -- no load in flight; if one is, onPlayerAdded clears the flag when it finishes
	end
	loading[player] = nil
end

-- ===== Public API for other services (server only) =====

-- True once this player's profile is loaded and active.
function DataService.IsLoaded(player: Player): boolean
	return activeProfile(player) ~= nil
end

-- A read-only COPY of all the player's data, or nil if the profile isn't loaded. Changing the copy changes nothing:
-- use DataService.Set to write.
function DataService.Get(player: Player)
	local profile = activeProfile(player)
	if profile == nil then
		return nil
	end
	return deepCopy(profile.Data)
end

-- A copy of one value by path, e.g. GetValue(player, "cash") or GetValue(player, "upgrades.CleaningBrush").
-- Returns nil if the profile isn't loaded or the path doesn't exist.
function DataService.GetValue(player: Player, path: string): any
	local profile = activeProfile(player)
	if profile == nil or type(path) ~= "string" or path == "" then
		return nil
	end
	local node: any = profile.Data
	for _, part in string.split(path, ".") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return deepCopy(node)
end

-- Set one value by path, e.g. Set(player, "cash", 150) or Set(player, "upgrades.CleaningBrush", 1), then push the
-- change to that player's client. Returns true if it was saved into the profile, false if it was refused:
--   - profile not loaded / already released    - path's first part isn't a field of the template (or is `version`)
--   - value can't be saved (NaN, Instance...)   - value type differs from the existing value (e.g. cash = "abc")
--   - nil on a top-level field (nil is allowed deeper down, to remove e.g. one inventory item)
function DataService.Set(player: Player, path: string, value: any): boolean
	local profile = activeProfile(player)
	if profile == nil or type(path) ~= "string" or path == "" then
		return false
	end

	local parts = string.split(path, ".")
	local root = parts[1]
	if root == "version" or TEMPLATE[root] == nil then
		warn("[DataService] Set refused: unknown or protected field", path)
		return false
	end
	if value == nil and #parts == 1 then
		warn("[DataService] Set refused: can't delete top-level field", path)
		return false
	end
	if value ~= nil and not isStorable(value, 1) then
		warn("[DataService] Set refused: value can't be saved at", path)
		return false
	end

	local node = profile.Data
	for i = 1, #parts - 1 do
		local nextNode = node[parts[i]]
		if type(nextNode) ~= "table" then
			warn("[DataService] Set refused: bad path", path)
			return false
		end
		node = nextNode
	end

	local lastKey = parts[#parts]
	local old = node[lastKey]
	if old ~= nil and value ~= nil and type(old) ~= type(value) then
		warn(`[DataService] Set refused: {path} is a {type(old)}, got a {type(value)}`)
		return false
	end

	node[lastKey] = deepCopy(value) -- store our own copy so the caller can't keep editing it
	Remotes.StateChanged:FireClient(player, path, deepCopy(value))
	return true
end

-- Sends a value to the client that is NOT saved data (e.g. the shop rating, worked out by another service).
function DataService.Push(player: Player, path: string, value: any)
	if Validate.isPlayer(player) then
		Remotes.StateChanged:FireClient(player, path, deepCopy(value))
	end
end

-- Adds a derived (not saved) value to the first snapshot a client gets, e.g. "rating". fn(player) -> value.
function DataService.AddSnapshotExtra(key: string, fn: (Player) -> any)
	snapshotExtras[key] = fn
end

-- A fresh copy of the default player data. Only DevTools uses it (to reset a Studio test profile).
function DataService.GetTemplate()
	return deepCopy(TEMPLATE)
end

-- Call `callback(player)` once a player's profile is loaded (also for players already loaded).
-- Services that need data at join (e.g. PlotService) should wait for this instead of polling.
function DataService.OnPlayerLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in profiles do
		if DataService.IsLoaded(player) then
			task.spawn(callback, player)
		end
	end
end

-- Call `callback(player)` just before a player's profile is released (data is still readable inside it).
function DataService.OnPlayerReleasing(callback: (Player) -> ())
	table.insert(releasingCallbacks, callback)
end

function DataService.Init(_services)
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
	log(`Init, store = {STORE_NAME}`)
end

function DataService.Start()
	-- ProfileStore reports problems through these signals. Saving keeps retrying by itself; we just make it visible.
	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(`[DataService] ProfileStore error ({storeName}/{profileKey}): {message}`)
	end)
	ProfileStore.OnOverwrite:Connect(function(storeName, profileKey)
		warn(`[DataService] ProfileStore: {storeName}/{profileKey} was changed by something other than ProfileStore`)
	end)
	ProfileStore.OnCriticalToggle:Connect(function(isCritical)
		if isCritical then
			warn("[DataService] CRITICAL: many DataStore errors in a row, saves may be delayed")
		else
			log("DataStore errors cleared, saving is back to normal")
		end
	end)

	-- A client asks once for its full data after joining. We wait (with a limit) for the profile to load.
	Remotes.GetInitialState.OnServerInvoke = function(player)
		if not Validate.rateLimit(player, "GetInitialState", 2) then
			return nil
		end
		local waited = 0
		while not DataService.IsLoaded(player) do
			if player.Parent ~= Players or waited >= INITIAL_STATE_TIMEOUT then
				return nil
			end
			task.wait(0.25)
			waited += 0.25
		end
		local snapshot = DataService.Get(player)
		if snapshot then
			for key, fn in snapshotExtras do -- derived values such as "rating"
				local ok, value = pcall(fn, player)
				if ok then
					snapshot[key] = value
				end
			end
		end
		return snapshot
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players who joined before Start ran (can happen in Studio). onPlayerAdded ignores anyone already loading.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	log(`Start, DataStoreState = {ProfileStore.DataStoreState}`)
end

return DataService
