-- DisplayService.luau (ServerScriptService.Server.Services.DisplayService)
-- Purpose: the SERVER rules for shelves and exhibit pedestals (docs/01 B9/B10, docs/03 §6): put a Restored item on a
-- display slot (for sale) or an exhibit slot (kept, gives rating points), take it off again, and let customers
-- reserve a Displayed item so it can't be removed while they walk to the counter.
-- Owner: Dev 1 (Ace) for these server rules (agreed with Sean so only one person edits this file); Dev 3 (Sean) draws
-- the shelves and the Inventory buttons on the client. Depends on: DataService, InventoryService, PlotService, Shared.Config.
-- The item itself is the single source of truth: state "Displayed"/"Exhibited" + `slot` number. Nothing else is saved.
-- Visitors can't see another player's data, so every slot Part also gets attributes ItemId (string), Golden (bool) and
-- Stars (number) while it holds an item; they are removed when it is empty (see SyncSlots).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local DisplayService = {}
local DEBUG = true
local log = Log.new("DisplayService", DEBUG)

local DataService, InventoryService, PlotService = nil, nil, nil

-- kind -> where the slots live in the plot, the part name prefix, and the item state used
local KINDS = {
	Display = { folder = "DisplaySlots", prefix = "Slot", state = "Displayed" },
	Exhibit = { folder = "ExhibitSlots", prefix = "Exhibit", state = "Exhibited" },
}
local MAX_SLOT_INDEX = 64 -- same bound as InventoryService's `slot` field

-- Customers who are walking to an item: [Player][uid] = customerId. In memory only (a reservation never needs saving).
local reservations: { [any]: { [string]: any } } = {}

-- The slot Part for (kind, index) in this player's plot, or nil.
local function slotPart(player: any, kind: string, slotIndex: number): Instance?
	local plot = PlotService.GetPlot(player)
	local info = KINDS[kind]
	local folder = plot and info and plot:FindFirstChild(info.folder)
	return folder and folder:FindFirstChild(info.prefix .. slotIndex)
end

-- The uid and item sitting in a slot, or nil.
local function occupant(player: any, kind: string, slotIndex: number): (string?, { [string]: any }?)
	local inventory = DataService.GetValue(player, "inventory") or {}
	for uid, item in inventory do
		if item.state == KINDS[kind].state and item.slot == slotIndex then
			return uid, item
		end
	end
	return nil, nil
end

-- A reservation only counts while the item is still on a shelf (a sold item can't stay reserved).
local function isReserved(player: any, uid: string): boolean
	local mine = reservations[player]
	if mine == nil or mine[uid] == nil then
		return false
	end
	local item = InventoryService.Get(player, uid)
	if item == nil or item.state ~= "Displayed" then
		mine[uid] = nil
		return false
	end
	return true
end

-- Makes every slot Part of this player's plot show what it holds: attributes ItemId / Golden / Stars while an item is
-- there, removed when empty. Safe to call any time (it rebuilds from the saved items). The client uses these so that
-- VISITORS can see someone else's shelves. Also called by InventoryService after a customer sale.
function DisplayService.SyncSlots(player: any)
	local plot = PlotService.GetPlot(player)
	if plot == nil then
		return
	end
	for kind, info in KINDS do
		local folder = plot:FindFirstChild(info.folder)
		if folder then
			for _, part in folder:GetChildren() do
				local index = part:GetAttribute("SlotIndex")
				-- a spot that is CLOSED (Enabled is exactly false: the second-floor pedestals were removed on 2026-11-26) can not
				-- hold an item: it goes back to the inventory (kept if the inventory is full, and tried again next time)
				if type(index) == "number" and part:GetAttribute("Enabled") == false then
					local uid = occupant(player, kind, index)
					if uid ~= nil and not isReserved(player, uid) and InventoryService.Update(player, uid, { state = "Restored" }) then
						InventoryService.ClearField(player, uid, "slot")
						log.info(`{kind} slot {index} is closed: item {uid} went back to the inventory`)
					end
				end
				local item = nil
				if type(index) == "number" then
					local _, found = occupant(player, kind, index)
					item = found
				end
				-- (not `a and b or nil`: that would turn Golden = false into nil)
				part:SetAttribute("ItemId", if item then item.itemId else nil)
				part:SetAttribute("Golden", if item then item.golden == true else nil)
				part:SetAttribute("Stars", if item then item.stars else nil)
			end
		end
	end
end

-- Shared by PlaceDisplay and PlaceExhibit.
-- Reasons: badKind, badSlot, noPlot, slotLocked, noItem, notRestored, slotTaken, saveFailed.
local function place(player: any, kind: string, uid: any, slotIndex: any): (boolean, string?)
	if KINDS[kind] == nil then
		return false, "badKind"
	end
	if not Validate.isInteger(slotIndex, 1, MAX_SLOT_INDEX) then
		return false, "badSlot"
	end
	if type(uid) ~= "string" then
		return false, "noItem"
	end
	if PlotService.GetPlot(player) == nil then
		return false, "noPlot"
	end
	local part = slotPart(player, kind, slotIndex)
	if part == nil then
		return false, "badSlot"
	end
	if part:GetAttribute("Enabled") ~= true then
		return false, "slotLocked"
	end
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem"
	end
	if item.state ~= "Restored" then
		return false, "notRestored"
	end
	if occupant(player, kind, slotIndex) ~= nil then
		return false, "slotTaken"
	end
	local ok = InventoryService.Update(player, uid, { state = KINDS[kind].state, slot = slotIndex })
	if not ok then
		return false, "saveFailed"
	end
	log.info(`{kind} slot {slotIndex} <- {item.itemId}`)
	DisplayService.SyncSlots(player)
	Analytics.Step(player, Analytics.STEP.DisplayedItem)
	return true, nil
end

-- Puts a Restored item on a shelf where customers can buy it. Returns ok, reason.
function DisplayService.PlaceDisplay(player: any, uid: any, slotIndex: any): (boolean, string?)
	return place(player, "Display", uid, slotIndex)
end

-- Puts a Restored item on an exhibit pedestal: kept, gives shop rating points, can't be sold by customers.
function DisplayService.PlaceExhibit(player: any, uid: any, slotIndex: any): (boolean, string?)
	return place(player, "Exhibit", uid, slotIndex)
end

-- Takes whatever is in a slot back to the inventory (state Restored). Returns ok, reason, uid.
-- Reasons: badKind, badSlot, empty, reserved (a customer is coming for it), full (no inventory room), saveFailed.
function DisplayService.RemoveFromSlot(player: any, kind: any, slotIndex: any): (boolean, string?, string?)
	if type(kind) ~= "string" or KINDS[kind] == nil then
		return false, "badKind", nil
	end
	if not Validate.isInteger(slotIndex, 1, MAX_SLOT_INDEX) then
		return false, "badSlot", nil
	end
	local uid = occupant(player, kind, slotIndex)
	if uid == nil then
		return false, "empty", nil
	end
	if isReserved(player, uid) then
		return false, "reserved", nil
	end
	local ok, reason = InventoryService.Update(player, uid, { state = "Restored" })
	if not ok then
		return false, if reason == "full" then "full" else "saveFailed", nil
	end
	InventoryService.ClearField(player, uid, "slot") -- not needed for correctness, keeps the item tidy
	DisplayService.SyncSlots(player)
	log.info(`{kind} slot {slotIndex} emptied`)
	return true, nil, uid
end

-- Is the item on display slot `slotIndex` reserved by a customer? (LayoutService: that shelf may not be moved now.)
function DisplayService.IsReservedAt(player: any, slotIndex: number): boolean
	local uid = occupant(player, "Display", slotIndex)
	return uid ~= nil and isReserved(player, uid)
end

-- For CustomerService: everything for sale right now that no customer has reserved, sorted by slot.
-- Each entry: { uid, slot, itemId, stars, golden }.
function DisplayService.GetAvailable(player: any): { { [string]: any } }
	local list = {}
	local inventory = DataService.GetValue(player, "inventory") or {}
	for uid, item in inventory do
		if item.state == "Displayed" and type(item.slot) == "number" and not isReserved(player, uid) then
			table.insert(list, { uid = uid, slot = item.slot, itemId = item.itemId, stars = item.stars, golden = item.golden })
		end
	end
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list
end

-- For CustomerService: a customer claims an item. One customer per item. Returns true if it worked.
function DisplayService.Reserve(player: any, uid: any, customerId: any): boolean
	if type(uid) ~= "string" or customerId == nil then
		return false
	end
	local item = InventoryService.Get(player, uid)
	if item == nil or item.state ~= "Displayed" or isReserved(player, uid) then
		return false
	end
	reservations[player] = reservations[player] or {}
	reservations[player][uid] = customerId
	return true
end

-- For CustomerService: the customer left without buying, or the sale is done (CompleteSale removes the item).
function DisplayService.Release(player: any, uid: any, customerId: any?)
	local mine = reservations[player]
	if mine == nil or type(uid) ~= "string" then
		return
	end
	if customerId == nil or mine[uid] == customerId then
		mine[uid] = nil
	end
end

-- Remote handlers --------------------------------------------------------------------------------------------------

local MESSAGES = {
	notRestored = "Only restored items can go on display.",
	slotTaken = "That spot is already used.",
	slotLocked = "That spot isn't unlocked yet. Buy more shelves in the shop.",
	reserved = "A customer is looking at that item right now.",
	full = "Your inventory is full. Sell something first.",
}

local function tell(player: Player, reason: string?)
	local text = reason and MESSAGES[reason]
	if text then
		Remotes.Notify:FireClient(player, "Info", text)
	end
end

-- The player must be standing near the slot they are using (same distance as the counter and the door).
local function nearSlot(player: Player, kind: string, slotIndex: number): boolean
	local part = slotPart(player, kind, slotIndex)
	return part ~= nil and part:IsA("BasePart") and Validate.withinDistance(player, part, Economy.InteractMaxStuds)
end

function DisplayService.Init(services)
	DataService = services.DataService
	InventoryService = services.InventoryService
	PlotService = services.PlotService
	log.info("Init")
end

function DisplayService.Start()
	Remotes.RequestPlaceDisplay.OnServerEvent:Connect(function(player, uid, slotIndex)
		if not Validate.rateLimit(player, "RequestPlaceDisplay", 4) or type(uid) ~= "string" then
			return
		end
		if not Validate.isInteger(slotIndex, 1, MAX_SLOT_INDEX) or not nearSlot(player, "Display", slotIndex) then
			return
		end
		local _, reason = DisplayService.PlaceDisplay(player, uid, slotIndex)
		tell(player, reason)
	end)

	Remotes.RequestPlaceExhibit.OnServerEvent:Connect(function(player, uid, slotIndex)
		if not Validate.rateLimit(player, "RequestPlaceExhibit", 4) or type(uid) ~= "string" then
			return
		end
		if not Validate.isInteger(slotIndex, 1, MAX_SLOT_INDEX) or not nearSlot(player, "Exhibit", slotIndex) then
			return
		end
		local _, reason = DisplayService.PlaceExhibit(player, uid, slotIndex)
		tell(player, reason)
	end)

	Remotes.RequestRemoveFromSlot.OnServerEvent:Connect(function(player, kind, slotIndex)
		if not Validate.rateLimit(player, "RequestRemoveFromSlot", 4) or type(kind) ~= "string" or KINDS[kind] == nil then
			return
		end
		if not Validate.isInteger(slotIndex, 1, MAX_SLOT_INDEX) or not nearSlot(player, kind, slotIndex) then
			return
		end
		local _, reason = DisplayService.RemoveFromSlot(player, kind, slotIndex)
		tell(player, reason)
	end)

	-- Their plot is assigned by PlotService in its own OnPlayerLoaded callback (registered earlier), so it exists now.
	DataService.OnPlayerLoaded(function(player)
		DisplayService.SyncSlots(player)
	end)
	DataService.OnPlayerReleasing(function(player)
		reservations[player] = nil
	end)
	log.info("Start")
end

return DisplayService
