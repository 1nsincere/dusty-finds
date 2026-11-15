-- ClientState.luau (StarterPlayerScripts.Client.ClientState)
-- Purpose: this client's read-only mirror of MY saved data. Loads once with GetInitialState, then stays up to
-- date from StateChanged(path, value). UI reads from here; it never changes data (the server owns everything).
-- Owner: Dev 3 (Sean). Depends on: Shared.Remotes (GetInitialState, StateChanged), DataService on the server.
-- Use: ClientState.Get("cash"), ClientState.OnChanged("cash", function(path, value) ... end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = {}
local DEBUG = true

local LOAD_ATTEMPTS = 3
local RETRY_DELAY = 3 -- seconds; the server rate-limits GetInitialState to one call per 2 s

local data: { [string]: any }? = nil
local pending: { { path: string, value: any } } = {} -- changes that arrive before the first snapshot
local listeners: { { prefix: string, callback: (string, any) -> () } } = {}

local function log(...)
	if DEBUG then
		print("[ClientState]", ...)
	end
end

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

local function splitPath(path: string): { string }
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	return parts
end

-- Writes one change into `data`. A nil value means the key was removed (e.g. an item was sold).
local function applyChange(path: string, value: any)
	if data == nil then
		return
	end
	local parts = splitPath(path)
	if #parts == 0 then
		return
	end
	local node = data
	for i = 1, #parts - 1 do
		if type(node[parts[i]]) ~= "table" then
			node[parts[i]] = {}
		end
		node = node[parts[i]]
	end
	node[parts[#parts]] = value
end

-- Tells listeners whose prefix matches: "inventory" hears "inventory.<uid>"; "cash" hears only "cash".
local function notify(path: string, value: any)
	for _, listener in listeners do
		local prefix = listener.prefix
		if prefix == "" or path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "." then
			task.spawn(listener.callback, path, deepCopy(value))
		end
	end
end

-- Called by Main.local.luau BEFORE controllers start, so they can read data right away.
-- Yields until the server answers (it waits for the profile to load). Returns true if data arrived.
function ClientState.Load(): boolean
	-- Listen first, so a change sent while we wait for the snapshot is not lost.
	Remotes.StateChanged.OnClientEvent:Connect(function(path, value)
		if type(path) ~= "string" then
			return
		end
		if data == nil then
			table.insert(pending, { path = path, value = value })
			return
		end
		applyChange(path, value)
		notify(path, value)
	end)

	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return Remotes.GetInitialState:InvokeServer()
		end)
		if ok and type(result) == "table" then
			data = result
			-- Replay early changes in order: the last one for a path is the newest value, so the end state is right.
			for _, change in pending do
				applyChange(change.path, change.value)
			end
			pending = {}
			log(`loaded: cash={data.cash} level={data.level} xp={data.xp}`)
			return true
		end
		warn(`[ClientState] GetInitialState failed (attempt {attempt}/{LOAD_ATTEMPTS}):`, ok and "no data" or result)
		if attempt < LOAD_ATTEMPTS then
			task.wait(RETRY_DELAY)
		end
	end
	warn("[ClientState] could not load my data; UI will show placeholders")
	return false
end

function ClientState.IsLoaded(): boolean
	return data ~= nil
end

-- Returns a copy of the value at `path` (e.g. "cash", "upgrades.CleaningBrush"), or nil if missing/not loaded.
-- It's a copy so UI code can't accidentally edit the mirror.
function ClientState.Get(path: string): any
	if data == nil then
		return nil
	end
	local node: any = data
	for _, part in splitPath(path) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return deepCopy(node)
end

-- Calls `callback(path, value)` whenever the server changes `prefix` or anything inside it.
-- Returns an object with :Disconnect() for screens that close.
function ClientState.OnChanged(prefix: string, callback: (string, any) -> ())
	local listener = { prefix = prefix, callback = callback }
	table.insert(listeners, listener)
	return {
		Disconnect = function()
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end,
	}
end

return ClientState
