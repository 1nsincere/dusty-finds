-- InventoryService.luau
-- Purpose: owns the player's items: add, remove, update, capacity, waiting-box count, and Quick Sell (docs/01 B4, B10).
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, PlotService, Shared.Config (Items, Economy, Upgrades).
-- Other services change items ONLY through this module, so every item always has valid fields.
-- Unopened, Displayed and Exhibited items do not count towards capacity (docs/01 B4).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local InventoryService = {}
local DEBUG = true
local log = Log.new("InventoryService", DEBUG)

local VALID_STATES = { Unopened = true, Dirty = true, InProgress = true, Restored = true, Displayed = true, Exhibited = true }
local NOT_COUNTED = { Unopened = true, Displayed = true, Exhibited = true }

local DataService, EconomyService, PlotService, CollectionBookService = nil, nil, nil, nil
local DisplayService = nil -- optional: tests may run without it

-- uids come from HttpService:GenerateGUID. Only letters, digits and dashes are allowed, because a "." would
-- change the DataService path ("inventory.<uid>.state").
local function isUid(uid: any): boolean
	return type(uid) == "string" and #uid > 0 and #uid <= 64 and string.match(uid, "^[%w%-]+$") ~= nil
end

local function itemPath(uid: string): string
	return "inventory." .. uid
end

function InventoryService.GetCapacity(player: Player): number
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	return Formulas.inventoryCapacity(upgrades.StorageRacks or 0)
end

-- Number of items that use up capacity.
function InventoryService.CountUsed(player: Player): number
	local inventory = DataService.GetValue(player, "inventory") or {}
	local used = 0
	for _, item in inventory do
		if not NOT_COUNTED[item.state] then
			used += 1
		end
	end
	return used
end

function InventoryService.HasRoom(player: Player): boolean
	return InventoryService.CountUsed(player) < InventoryService.GetCapacity(player)
end

-- A copy of one item, or nil.
function InventoryService.Get(player: Player, uid: string)
	if not isUid(uid) then
		return nil
	end
	return DataService.GetValue(player, itemPath(uid))
end

-- Waiting boxes = distinct boxIds among Unopened items; `freeWaiting` = how many of those are Free Delivery boxes.
function InventoryService.CountWaitingBoxes(player: Player): (number, number)
	local inventory = DataService.GetValue(player, "inventory") or {}
	local seen: { [string]: boolean } = {}
	local boxes, freeWaiting = 0, 0
	for uid, item in inventory do
		if item.state == "Unopened" then
			local boxId = item.boxId or uid -- an item without a box counts as its own box
			if not seen[boxId] then
				seen[boxId] = true
				boxes += 1
				if item.crateId == "FreeDelivery" then
					freeWaiting += 1
				end
			end
		end
	end
	return boxes, freeWaiting
end

-- Creates an item. opts: golden, state (default "Unopened"), crateId, boxId. Returns uid, or nil plus a reason.
-- Unopened items skip the capacity check (it is checked when the box is opened).
function InventoryService.Add(player: Player, itemId: string, opts: { [string]: any }?): (string?, string?)
	opts = opts or {}
	if not Validate.isConfigId(itemId, Items) then
		return nil, "unknownItem"
	end
	local state = opts.state or "Unopened"
	if not VALID_STATES[state] then
		return nil, "badState"
	end
	if not NOT_COUNTED[state] and not InventoryService.HasRoom(player) then
		return nil, "full"
	end

	local uid = HttpService:GenerateGUID(false)
	local item = {
		uid = uid,
		itemId = itemId,
		golden = opts.golden == true,
		state = state,
		stepIndex = 1,
		stepScores = {},
		acquiredAt = os.time(),
		crateId = if type(opts.crateId) == "string" then opts.crateId else nil,
		boxId = if type(opts.boxId) == "string" then opts.boxId else nil,
	}
	if not DataService.Set(player, itemPath(uid), item) then
		return nil, "saveFailed"
	end
	return uid, nil
end

function InventoryService.Remove(player: Player, uid: string): boolean
	if not isUid(uid) or InventoryService.Get(player, uid) == nil then
		return false
	end
	return DataService.Set(player, itemPath(uid), nil)
end

local function validField(name: string, value: any): boolean
	if name == "state" then
		return type(value) == "string" and VALID_STATES[value] == true
	elseif name == "stepIndex" then
		return Validate.isInteger(value, 1, 20)
	elseif name == "stepScores" then
		if type(value) ~= "table" or #value > 20 then
			return false
		end
		for _, score in value do
			if not Validate.isNumber(score, 0, 100) then
				return false
			end
		end
		return true
	elseif name == "stars" then
		return Validate.isInteger(value, 1, 3)
	elseif name == "slot" then
		return Validate.isInteger(value, 1, 64)
	end
	return false -- uid, itemId, golden, acquiredAt, crateId, boxId can't be changed after creation
end

-- Changes allowed fields of one item: state, stepIndex, stepScores, stars, slot.
-- All-or-nothing: every field is checked before anything is written. Returns ok, reason.
function InventoryService.Update(player: Player, uid: string, changes: { [string]: any }): (boolean, string?)
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem"
	end
	if type(changes) ~= "table" then
		return false, "badChanges"
	end
	for name, value in changes do
		if not validField(name, value) then
			return false, "badField:" .. tostring(name)
		end
	end
	-- Moving an uncounted item (e.g. Unopened) into a counted state needs room.
	local newState = changes.state
	if newState and NOT_COUNTED[item.state] and not NOT_COUNTED[newState] and not InventoryService.HasRoom(player) then
		return false, "full"
	end
	for name, value in changes do
		if not DataService.Set(player, itemPath(uid) .. "." .. name, value) then
			return false, "saveFailed"
		end
	end
	if changes.state ~= nil or item.state == "Exhibited" then
		CollectionBookService.RefreshRating(player) -- exhibits give rating points
	end
	return true, nil
end

-- A key set to nil is simply absent from a Lua table, so Update can't clear a field: use this for stars or slot.
function InventoryService.ClearField(player: Player, uid: string, name: string): boolean
	if (name ~= "stars" and name ~= "slot") or InventoryService.Get(player, uid) == nil then
		return false
	end
	return DataService.Set(player, itemPath(uid) .. "." .. name, nil)
end

-- Sells a Restored item for 70% of its base price (no wish, no tip). Returns ok, reason, amount.
-- The caller (remote handler) has already checked distance to the counter.
function InventoryService.QuickSell(player: Player, uid: string): (boolean, string?, number?)
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem", nil
	end
	if item.state ~= "Restored" or type(item.stars) ~= "number" then
		return false, "notRestored", nil
	end
	local amount = Formulas.quickSellPrice(item.itemId, item.stars, item.golden)
	if amount <= 0 then
		return false, "noPrice", nil
	end
	if not InventoryService.Remove(player, uid) then
		return false, "removeFailed", nil
	end
	EconomyService.AddCash(player, amount, "Sale")
	local sold = DataService.GetValue(player, "stats.sold") or 0
	DataService.Set(player, "stats.sold", sold + 1)
	if Validate.isPlayer(player) then
		Remotes.SaleMade:FireClient(player, amount, false, 0)
	end
	return true, nil, amount
end

-- A customer buys a Displayed item (called by CustomerService / DisplayService, Dev 3). The server works out the whole
-- price, so the caller can't invent one: price = sellPrice (wish x1.25 if wishMatched), + 10% if `checkout`, + a tip
-- (chance = 5% + 5% x shop rating stars + opts.tipBonus; amount 10-25% of the price).
-- opts: wishMatched (boolean), checkout (boolean), tipBonus (the customer type's tipBonus), random (tests only).
-- Returns ok, reason, { price, bonus, tip, total }. Reasons: noItem, notDisplayed, noPrice, removeFailed.
function InventoryService.CompleteSale(player: Player, uid: string, opts: { [string]: any }?): (boolean, string?, { [string]: number }?)
	opts = opts or {}
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem", nil
	end
	if item.state ~= "Displayed" or type(item.stars) ~= "number" then
		return false, "notDisplayed", nil
	end
	local wishMatched = opts.wishMatched == true
	local price = Formulas.sellPrice(item.itemId, item.stars, item.golden, wishMatched)
	if price <= 0 then
		return false, "noPrice", nil
	end

	local bonus = if opts.checkout == true then Formulas.checkoutBonus(price) else 0
	local random: Random = opts.random or Random.new()
	local tip = 0
	local chance = Formulas.tipChance(CollectionBookService.GetRatingStars(player), opts.tipBonus)
	if random:NextNumber() < chance then
		tip = Formulas.tipAmount(price, random:NextNumber(Economy.TipMinFraction, Economy.TipMaxFraction))
	end

	if not InventoryService.Remove(player, uid) then
		return false, "removeFailed", nil
	end
	if DisplayService then
		DisplayService.SyncSlots(player) -- the shelf is empty now: clear its ItemId / Golden / Stars attributes
	end
	local total = price + bonus + tip
	EconomyService.AddCash(player, total, "Sale")
	local sold = DataService.GetValue(player, "stats.sold") or 0
	DataService.Set(player, "stats.sold", sold + 1)
	if Validate.isPlayer(player) then
		Remotes.SaleMade:FireClient(player, total, wishMatched, tip)
	end
	return true, nil, { price = price, bonus = bonus, tip = tip, total = total }
end

function InventoryService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	PlotService = services.PlotService
	CollectionBookService = services.CollectionBookService
	DisplayService = services.DisplayService
	log.info("Init")
end

function InventoryService.Start()
	Remotes.RequestQuickSell.OnServerEvent:Connect(function(player, uid)
		if not Validate.rateLimit(player, "RequestQuickSell", 3) then
			return
		end
		if not isUid(uid) then
			return
		end
		local plot = PlotService.GetPlot(player)
		local counter = plot and plot:FindFirstChild("Counter")
		if counter == nil or not Validate.withinDistance(player, counter, Economy.InteractMaxStuds) then
			return
		end
		InventoryService.QuickSell(player, uid)
	end)
	log.info("Start")
end

return InventoryService
