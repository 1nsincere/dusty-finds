-- CustomerService.luau (ServerScriptService.Server.Services.CustomerService)
-- Purpose: the DECISIONS of customer AI (docs/01 B9, docs/02 §5), with no models, walking or UI: when a customer
-- arrives, which type and wish it has, which displayed item it picks, and what happens at checkout.
-- Owner: Dev 1 (Ace) for these server rules (agreed with Sean so only one person edits this file). Sean's
-- CustomerNpcService (models, walking, counter queue, Checkout prompt, 8 s auto-checkout) calls these functions and
-- reacts through SetSpawnHandler / SetRemovedHandler. Depends on: DataService, DisplayService, InventoryService,
-- CollectionBookService, Shared.Config (Customers, Economy, Items, Rarities), Shared.Formulas.
--
-- The flow, for one customer (everything per player/shop):
--   TrySpawn   -> a customer record exists (counts towards the cap)           -> spawn handler is called
--   ChooseItem -> an item is reserved for it (or nil: leave sad)              <- the NPC walks to that shelf slot
--   Checkout   -> the sale is paid by InventoryService.CompleteSale            <- Checkout prompt (+10%) or auto after
--                                                                                 Economy.AutoCheckoutSeconds (tapped = false)
--   Leave      -> gives up without buying (reservation released)
-- EVERY way a customer disappears ends in one place and calls the removed handler with a reason:
--   "paid" (Checkout worked), "failed" (Checkout failed), "left" (Leave), "nothing" (ChooseItem found no item),
--   "timeout" (Sweep), "playerLeft" (the shop owner left), "spawnFailed" (the spawn handler errored).


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local CustomerTypes = require(ReplicatedStorage.Shared.Config.Customers)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local CustomerService = {}
local DEBUG = true
local log = Log.new("CustomerService", DEBUG)

local DataService, DisplayService, InventoryService, CollectionBookService = nil, nil, nil, nil

-- Safety net: a customer that nobody finished (NPC destroyed, script error) is removed after this long so it can't
-- block the shop's customer cap forever. Longer than any normal visit (walk + browse + 8 s checkout).
local MAX_CUSTOMER_SECONDS = 420 -- long enough for a visit with thinking, coming back and waiting for the owner at the till
local WISH_FROM_DISPLAY_CHANCE = 0.7 -- docs/01 B9: 70% of wishes are chosen from categories currently on display
local PICK_ATTEMPTS = 3 -- how many times ChooseItem retries when a reservation fails (another customer was faster)

type Customer = {
	id: string,
	typeId: string,
	wish: string, -- a category from Economy.Categories
	spawnedAt: number,
	uid: string?, -- the reserved item, once chosen
	wishMatched: boolean,
	noTip: boolean?, -- a declined haggler who stayed: pays full price but never tips
	priceMult: number?, -- a haggle the owner accepted: the sale price is multiplied by this (0.5-1)
}

local customers: { [any]: { [string]: Customer } } = {} -- [Player][customerId] = Customer
local nextSpawnAt: { [any]: number } = {} -- [Player] = clock time of the next allowed arrival
local counter = 0
local spawnHandler: ((Player, Customer) -> ())? = nil
local removedHandler: ((Player, string, string) -> ())? = nil -- (player, customerId, reason)

local function countCustomers(player: any): number
	local n = 0
	for _ in customers[player] or {} do
		n += 1
	end
	return n
end

-- The ONE place a customer disappears: releases the reserved item, forgets the record, tells the NPC side (reason, see
-- the header). The handler runs in its own thread (NPC code may yield) and an error in it can't break the caller.
local function removeCustomer(player: any, customerId: string, reason: string)
	local mine = customers[player]
	local customer = mine and mine[customerId]
	if not customer then
		return
	end
	if customer.uid then
		DisplayService.Release(player, customer.uid, customer.id)
	end
	mine[customerId] = nil
	local handler = removedHandler
	if handler then
		task.spawn(function()
			local ok, err = pcall(handler, player, customerId, reason)
			if not ok then
				log.warn("removed handler failed:", tostring(err))
			end
		end)
	end
end

-- Weighted random customer type id (weights from Config/Customers).
function CustomerService.PickType(random: Random?): string
	local rng = random or Random.new()
	local total = 0
	for _, def in CustomerTypes do
		total += def.weight
	end
	local roll = rng:NextNumber() * total
	local ids = {}
	for id in CustomerTypes do
		table.insert(ids, id)
	end
	table.sort(ids) -- fixed order, so the same seed always gives the same type
	for _, id in ids do
		roll -= CustomerTypes[id].weight
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

-- A wish category. 70% of the time one of the categories on display right now (so it can be satisfied), otherwise any.
-- `available` is DisplayService.GetAvailable(player).
function CustomerService.PickWish(available: { { [string]: any } }, random: Random?): string
	local rng = random or Random.new()
	local onDisplay: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, entry in available do
		local def = Items[entry.itemId]
		if def and not seen[def.category] then
			seen[def.category] = true
			table.insert(onDisplay, def.category)
		end
	end
	table.sort(onDisplay)
	if #onDisplay > 0 and rng:NextNumber() < WISH_FROM_DISPLAY_CHANCE then
		return onDisplay[rng:NextInteger(1, #onDisplay)]
	end
	return Economy.Categories[rng:NextInteger(1, #Economy.Categories)]
end

-- Picks one item for a customer from `available`. Collectors (prefersMinRarity) only look at that rarity or better if
-- any is displayed; then a wish match wins, otherwise any random item. Returns the entry and whether the wish matched.
function CustomerService.PickItem(typeId: string, wish: string, available: { { [string]: any } }, random: Random?): ({ [string]: any }?, boolean)
	if #available == 0 then
		return nil, false
	end
	local rng = random or Random.new()
	local pool = available
	local minRarity = CustomerTypes[typeId] and CustomerTypes[typeId].prefersMinRarity
	if minRarity and Rarities[minRarity] then
		local better = {}
		for _, entry in available do
			local def = Items[entry.itemId]
			if def and Rarities[def.rarity].index >= Rarities[minRarity].index then
				table.insert(better, entry)
			end
		end
		if #better > 0 then
			pool = better
		end
	end
	local matches = {}
	for _, entry in pool do
		if Items[entry.itemId] and Items[entry.itemId].category == wish then
			table.insert(matches, entry)
		end
	end
	if #matches > 0 then
		return matches[rng:NextInteger(1, #matches)], true
	end
	return pool[rng:NextInteger(1, #pool)], false
end

-- Most customers inside the shop at once: 3, or 5 with the Showroom (docs/02 §5).
function CustomerService.MaxCustomers(player: any): number
	if (DataService.GetValue(player, "upgrades.Showroom") or 0) > 0 then
		return Economy.MaxCustomersShowroom
	end
	return Economy.MaxCustomers
end

-- Seconds between arrivals for this shop (Shop Sign level and rating stars).
function CustomerService.SpawnInterval(player: any): number
	local sign = DataService.GetValue(player, "upgrades.ShopSign") or 0
	return Formulas.customerSpawnInterval(sign, CollectionBookService.GetRatingStars(player))
end

-- Lets a customer in if: the shop has something for sale, there is room, and the arrival timer has elapsed.
-- Returns the new customer record, or nil + reason (noData, tooSoon, full, noItems).
function CustomerService.TrySpawn(player: any, now: number?, random: Random?): (Customer?, string?)
	local time = now or os.clock()
	if DataService.GetValue(player, "inventory") == nil then
		return nil, "noData"
	end
	if nextSpawnAt[player] and time < nextSpawnAt[player] then
		return nil, "tooSoon"
	end
	if countCustomers(player) >= CustomerService.MaxCustomers(player) then
		return nil, "full"
	end
	local available = DisplayService.GetAvailable(player)
	if #available == 0 then
		return nil, "noItems"
	end
	local rng = random or Random.new()
	counter += 1
	local customer: Customer = {
		id = "C" .. counter,
		typeId = CustomerService.PickType(rng),
		wish = CustomerService.PickWish(available, rng),
		spawnedAt = time,
		uid = nil,
		wishMatched = false,
	}
	customers[player] = customers[player] or {}
	customers[player][customer.id] = customer
	nextSpawnAt[player] = time + CustomerService.SpawnInterval(player)
	log.info(`{customer.typeId} ({customer.wish}) arrives at {player.Name}'s shop`)
	return customer, nil
end

-- The customer picks an item and reserves it so the owner can't take it off the shelf meanwhile.
-- Returns { uid, itemId, slot, wishMatched } or nil, reason (noCustomer, alreadyChose, nothing).
-- "nothing" means no item could be reserved: the customer is removed (leave sad).
function CustomerService.ChooseItem(player: any, customerId: any, random: Random?): ({ [string]: any }?, string?)
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if not customer then
		return nil, "noCustomer"
	end
	if customer.uid then
		return nil, "alreadyChose"
	end
	for _ = 1, PICK_ATTEMPTS do
		local entry, matched = CustomerService.PickItem(customer.typeId, customer.wish, DisplayService.GetAvailable(player), random)
		if entry == nil then
			break
		end
		if DisplayService.Reserve(player, entry.uid, customer.id) then
			customer.uid = entry.uid
			customer.wishMatched = matched
			return { uid = entry.uid, itemId = entry.itemId, slot = entry.slot, wishMatched = matched }, nil
		end
	end
	removeCustomer(player, customer.id, "nothing")
	return nil, "nothing"
end

-- The customer looks at the item it reserved and decides (2026-11-25). Returns outcome, reason:
--   "buy"   -> go to the counter and wait for the owner
--   "think" -> "let me think about it": CustomerService.Reconsider, wander off, maybe come back
--   "pass"  -> leaves with a critique (reason: scratched | notWanted | plainShop | pricey)
-- The chance to buy grows with the SHOP RATING (a 5-star shop sells much more than a 1-star one), a little with the item's stars and
-- a wish match (Formulas.buyChance). `returning` = this customer already thought it over once: more likely to buy, never thinks twice.
function CustomerService.Judge(player: any, customerId: any, random: Random?, returning: boolean?): (string?, string?)
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if not customer or customer.uid == nil then
		return nil, "noItem"
	end
	local item = InventoryService.Get(player, customer.uid)
	local ratingStars = CollectionBookService.GetRatingStars(player)
	local itemStars = if item and type(item.stars) == "number" then item.stars else 2
	local rng = random or Random.new()
	local personality = CustomerTypes[customer.typeId] or {}
	local chance = Formulas.buyChance(ratingStars, itemStars, customer.wishMatched, (if returning then Economy.ThinkReturnBonus else 0) + (personality.buyBonus or 0))
	if rng:NextNumber() < chance then
		return "buy", nil
	end
	local reason
	if itemStars <= 1 then
		reason = "scratched"
	elseif not customer.wishMatched then
		reason = "notWanted"
	elseif ratingStars <= 2 then
		reason = "plainShop"
	else
		reason = "pricey"
	end
	if not returning and rng:NextNumber() < Economy.ThinkShare then
		return "think", reason
	end
	return "pass", reason
end

-- Haggling: does a customer of this type ask for a discount at the till, and how much? Returns the discount fraction (0.05 steps),
-- or nil for no haggle. Pure apart from the random it is given.
function CustomerService.HaggleOffer(typeId: string, random: Random?): number?
	local def = CustomerTypes[typeId]
	if def == nil or type(def.haggleChance) ~= "number" or def.haggleDiscount == nil then
		return nil
	end
	local rng = random or Random.new()
	if rng:NextNumber() >= def.haggleChance then
		return nil
	end
	local raw = rng:NextNumber(def.haggleDiscount[1], def.haggleDiscount[2])
	local step = Economy.HaggleStep
	return math.clamp(math.floor(raw / step + 0.5) * step, step, 0.5)
end

-- The owner declined a haggle and the customer stayed: full price, no tip.
function CustomerService.SetNoTip(player: any, customerId: any)
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if customer then
		customer.noTip = true
	end
end

-- The owner accepted a haggle: the sale will be at price x mult (clamped 0.5-1; the till and the sale both use it).
function CustomerService.SetPriceMult(player: any, customerId: any, mult: number): boolean
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if not customer or type(mult) ~= "number" or mult ~= mult then
		return false
	end
	customer.priceMult = math.clamp(mult, 0.5, 1)
	return true
end

-- A thinking customer puts the item back: the reservation is released and it can choose again later (or never come back).
function CustomerService.Reconsider(player: any, customerId: any): boolean
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if not customer or customer.uid == nil then
		return false
	end
	DisplayService.Release(player, customer.uid, customer.id)
	customer.uid = nil
	customer.wishMatched = false
	return true
end

-- Pays the sale. `tapped` = the owner tapped Checkout (+10%); false = auto checkout. Removes the customer.
-- Returns ok, reason, result = { price, bonus, tip, total } (the same table InventoryService.CompleteSale gives).
-- Reasons: noCustomer, noItem (no item chosen yet), or CompleteSale's own (notDisplayed, noPrice, removeFailed).
-- tapped = served at the till with the right change first try (+checkout bonus); served = served at the till at all
-- (tip possible). Auto-checkout passes neither: no bonus, no tip.
-- bonusFraction (optional, Dev 3 2026-11-23): the till's speed/mistake result; replaces the +10% with price x fraction.
function CustomerService.Checkout(player: any, customerId: any, tapped: boolean, random: Random?, served: boolean?, bonusFraction: number?): (boolean, string?, { [string]: number }?)
	local customer = customers[player] and type(customerId) == "string" and customers[player][customerId]
	if not customer then
		return false, "noCustomer", nil
	end
	if customer.uid == nil then
		return false, "noItem", nil
	end
	local ok, reason, result = InventoryService.CompleteSale(player, customer.uid, {
		wishMatched = customer.wishMatched,
		checkout = tapped == true,
		tipBonus = CustomerTypes[customer.typeId].tipBonus,
		random = random,
		bonusFraction = bonusFraction,
		priceMult = customer.priceMult,
		noTip = (tapped ~= true and served ~= true) or customer.noTip == true, -- a declined haggler who stayed never tips
	})
	removeCustomer(player, customer.id, if ok then "paid" else "failed") -- also releases the reservation
	if not ok then
		return false, reason, nil
	end
	return true, nil, result
end

-- The customer leaves without buying (reservation released, spot freed). `reason` is passed to the removed handler.
function CustomerService.Leave(player: any, customerId: any, reason: string?)
	if type(customerId) == "string" then
		removeCustomer(player, customerId, reason or "left")
	end
end

-- Removes every customer of a shop (the owner left). Returns how many.
function CustomerService.RemoveAll(player: any, reason: string?): number
	local removed = 0
	for id in table.clone(customers[player] or {}) do
		removeCustomer(player, id, reason or "playerLeft")
		removed += 1
	end
	return removed
end

-- Removes customers older than MAX_CUSTOMER_SECONDS (a stuck NPC must not block the cap). Returns how many.
function CustomerService.Sweep(player: any, now: number?): number
	local time = now or os.clock()
	local removed = 0
	for id, customer in table.clone(customers[player] or {}) do
		if time - customer.spawnedAt > MAX_CUSTOMER_SECONDS then
			removeCustomer(player, id, "timeout")
			removed += 1
		end
	end
	return removed
end

-- One step for one shop (the loop in Start calls this every second): sweep stuck customers, let a new one in when it is
-- time, and hand it to the spawn handler IN ITS OWN THREAD (NPC code yields while walking: it must never block
-- arrivals for other shops). Returns the new customer or nil.
function CustomerService.Tick(player: any, now: number?, random: Random?): Customer?
	if spawnHandler == nil then
		return nil
	end
	CustomerService.Sweep(player, now)
	local customer = CustomerService.TrySpawn(player, now, random)
	if customer then
		local handler = spawnHandler
		task.spawn(function()
			local ok, err = pcall(handler, player, customer)
			if not ok then
				log.warn("spawn handler failed:", tostring(err))
				removeCustomer(player, customer.id, "spawnFailed")
			end
		end)
	end
	return customer
end

function CustomerService.GetCustomers(player: any): { [string]: Customer }
	return customers[player] or {}
end

-- Sean's NPC code registers here: `handler(player, customer)` is called when a customer arrives (spawn the model).
-- Without a handler nothing spawns, so adopting this file changes nothing until the NPC side exists.
function CustomerService.SetSpawnHandler(handler: ((Player, Customer) -> ())?)
	spawnHandler = handler
end

-- Sean's NPC code registers here too: `handler(player, customerId, reason)` is called whenever a customer is gone for
-- any reason (see the header list), so the model can walk out or be destroyed. It runs in its own thread.
function CustomerService.SetRemovedHandler(handler: ((Player, string, string) -> ())?)
	removedHandler = handler
end

function CustomerService.Init(services)
	DataService = services.DataService
	DisplayService = services.DisplayService
	InventoryService = services.InventoryService
	CollectionBookService = services.CollectionBookService
	log.info("Init")
end

function CustomerService.Start()
	DataService.OnPlayerReleasing(function(player)
		CustomerService.RemoveAll(player, "playerLeft") -- tells the NPC side so models don't stay behind
		customers[player] = nil
		nextSpawnAt[player] = nil
	end)

	-- One tick per second for every player in the game (see Tick). Each step is wrapped so one bad shop can't stop the loop.
	task.spawn(function()
		while true do
			task.wait(1)
			if spawnHandler then
				for _, player in Players:GetPlayers() do
					if Validate.isPlayer(player) and DataService.IsLoaded(player) then
						local ok, err = pcall(CustomerService.Tick, player)
						if not ok then
							log.warn("tick failed:", tostring(err))
						end
					end
				end
			end
		end
	end)
	log.info("Start")
end

return CustomerService
