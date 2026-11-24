-- StorageShelfService.luau (ServerScriptService.Server.Services.StorageShelfService)
-- Purpose: the storage room shelves. Shows each owner's UNRESTORED items (Dirty / InProgress) on their plot's
-- StorageShelves/Slot1..16, rarest first, so the owner and visitors see what is waiting to be restored. It only writes
-- attributes (same idea as DisplayService.SyncSlots): ItemId + Golden on each slot part, and More (how many did not fit)
-- on the StorageShelves folder. StorageShelfController draws the item models for every player.
-- Read-only on data: it never changes the inventory. No remotes.
-- Owner: Dev 3 (Sean). Depends on: DataService.GetValue, PlotService.GetPlot, RestorationService.GetSession (the item
-- on the bench right now is not shown twice), Shared.Config (Items, Rarities), Workspace.Plots.PlotN.StorageShelves.
-- Why a 0.5 s check instead of an event: the server has no "inventory changed" signal and this needs none; it only
-- writes when something actually changed, and 6 players x ~40 items is tiny.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local StorageShelfService = {}
local DEBUG = true
local log = Log.new("StorageShelfService", DEBUG)

local CHECK_EVERY = 0.5 -- seconds
local SHOWN_STATES = { Dirty = true, InProgress = true }

local DataService, PlotService, RestorationService = nil, nil, nil
local lastPlot: { [Player]: Instance } = {} -- remembered so the shelves can be cleared after the player has left
local lastKey: { [Player]: string } = {} -- what we wrote last time, to skip identical writes

-- Pure rule (tested by Tests/StorageShelfCheck): which unrestored items go on the shelves, in slot order.
-- inventory = { [uid] = item }, skipUid = the item on the bench (or nil), slotCount = how many slots there are.
-- Returns a list of { uid, itemId, golden } (rarest first; ties: golden first, then name, then uid so the order is
-- stable and items don't jump around), and how many did not fit.
function StorageShelfService.Pick(inventory: { [string]: any }?, skipUid: string?, slotCount: number): ({ { [string]: any } }, number)
	local list = {}
	for uid, item in (inventory or {}) do
		if type(item) == "table" and SHOWN_STATES[item.state] and uid ~= skipUid and Items[item.itemId] then
			local rarity = Rarities[Items[item.itemId].rarity]
			table.insert(list, { uid = uid, itemId = item.itemId, golden = item.golden == true, rank = rarity and rarity.index or 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		if a.golden ~= b.golden then
			return a.golden
		end
		if a.itemId ~= b.itemId then
			return a.itemId < b.itemId
		end
		return a.uid < b.uid
	end)
	local shown = {}
	for i = 1, math.min(slotCount, #list) do
		shown[i] = list[i]
	end
	return shown, math.max(0, #list - slotCount)
end

local function slotsOf(plot: Instance): { BasePart }
	local folder = plot:FindFirstChild("StorageShelves")
	local slots = {}
	for _, s in (folder and folder:GetChildren() or {}) do
		local index = s:GetAttribute("SlotIndex")
		if s:IsA("BasePart") and type(index) == "number" then
			slots[index] = s
		end
	end
	return slots
end

local function clearPlot(plot: Instance)
	for _, slot in slotsOf(plot) do
		slot:SetAttribute("ItemId", nil)
		slot:SetAttribute("Golden", nil)
	end
	local folder = plot:FindFirstChild("StorageShelves")
	if folder then
		folder:SetAttribute("More", nil)
	end
end

local function sync(player: Player)
	local plot = PlotService.GetPlot(player)
	if plot == nil then
		return
	end
	if lastPlot[player] and lastPlot[player] ~= plot then
		clearPlot(lastPlot[player]) -- moved to another plot (should not happen, but never leave stale items behind)
		lastKey[player] = nil
	end
	lastPlot[player] = plot
	local slots = slotsOf(plot)
	local session = RestorationService and RestorationService.GetSession(player)
	local shown, more = StorageShelfService.Pick(DataService.GetValue(player, "inventory"), session and session.uid, #slots)
	local parts = {}
	for i, entry in shown do
		parts[i] = entry.uid .. (if entry.golden then "*" else "")
	end
	local key = table.concat(parts, ",") .. "|" .. more
	if key == lastKey[player] then
		return
	end
	lastKey[player] = key
	for index, slot in slots do
		local entry = shown[index]
		slot:SetAttribute("ItemId", entry and entry.itemId or nil)
		slot:SetAttribute("Golden", if entry then entry.golden else nil)
	end
	plot.StorageShelves:SetAttribute("More", if more > 0 then more else nil)
	log.info(`{player.Name}: {#shown} unrestored item(s) on the storage shelves` .. (if more > 0 then ` (+{more} more)` else ""))
end

local function forget(player: Player)
	local plot = lastPlot[player]
	if plot then
		clearPlot(plot)
	end
	lastPlot[player] = nil
	lastKey[player] = nil
end

function StorageShelfService.Init(services)
	DataService = services.DataService
	PlotService = services.PlotService
	RestorationService = services.RestorationService
	log.info("Init")
end

function StorageShelfService.Start()
	-- every plot starts empty (no stale attributes from an earlier test in Studio)
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in (plots and plots:GetChildren() or {}) do
		clearPlot(plot)
	end
	Players.PlayerRemoving:Connect(forget)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(sync, player)
				if not ok then
					log.warn("sync failed for", player.Name, err)
				end
			end
		end
	end)
	log.info("Start")
end

return StorageShelfService
