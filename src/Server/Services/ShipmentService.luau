-- ShipmentService.luau
-- Purpose: boxes of mystery items: Free Delivery, buying crates, rolling contents, opening boxes (docs/01 B1-B3).
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, InventoryService, CollectionBookService, PlotService,
-- Shared.Config (Crates, Items, Rarities, Economy). All rolls use Random.new() on the server (CLAUDE.md §4 rule 8).
-- Contents are rolled when the box is bought/claimed and saved as Unopened items; opening only reveals them.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local ShipmentService = {}
local DEBUG = true
local log = Log.new("ShipmentService", DEBUG)

local rng = Random.new()
local DataService, EconomyService, InventoryService, CollectionBookService, PlotService = nil, nil, nil, nil, nil

-- Rarity names from lowest to highest, so rolls are in a fixed order.
local rarityOrder: { string } = {}
for id in Rarities do
	table.insert(rarityOrder, id)
end
table.sort(rarityOrder, function(a, b)
	return Rarities[a].index < Rarities[b].index
end)

-- Item ids of one tier and rarity, sorted so a seeded Random gives the same result every time.
local function itemsOf(tier: number, rarity: string): { string }
	local ids = {}
	for id, def in Items do
		if def.tier == tier and def.rarity == rarity then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Tests call this so the buying tests are deterministic (the Time Capsule chance uses the module Random).
function ShipmentService.SetRandom(random: Random)
	rng = random
end

-- Rolls ONE item for a crate: rarity from the crate's odds, then a random item of that rarity in the crate's tier,
-- then a 2% Golden chance. `random` is optional (tests pass a seeded Random). Returns itemId, golden.
function ShipmentService.RollItem(crateId: string, random: Random?): (string?, boolean)
	local crate = Crates[crateId]
	if crate == nil then
		return nil, false
	end
	local r = random or rng

	-- Special pull 1, LOST MASTERPIECE: a tiny chance per item to be a Relic. Checked first; never Golden; Free Delivery has no entry.
	local relicChance = Economy.RelicChance[crateId]
	if relicChance and r:NextNumber() < relicChance then
		local relics = itemsOf(crate.tier, "Relic")
		if #relics > 0 then
			return relics[r:NextInteger(1, #relics)], false
		end
	end

	local roll = r:NextNumber() * 100
	local running = 0
	local chosen = nil
	for _, rarity in rarityOrder do
		local chance = crate.odds[rarity] or 0
		if chance > 0 then
			running += chance
			if roll < running then
				chosen = rarity
				break
			end
		end
	end
	if chosen == nil then -- rounding at the very top of the range: use the highest rarity with a chance
		for i = #rarityOrder, 1, -1 do
			if (crate.odds[rarityOrder[i]] or 0) > 0 then
				chosen = rarityOrder[i]
				break
			end
		end
	end

	local pool = itemsOf(crate.tier, chosen)
	if #pool == 0 then
		log.warn("no items for", crateId, "tier", crate.tier, chosen)
		return nil, false
	end
	local itemId = pool[r:NextInteger(1, #pool)]
	local golden = r:NextNumber() < Economy.GoldenChance
	return itemId, golden
end

-- Adds one box (a crate's worth of Unopened items) to the inventory. Returns the uids, or nil plus a reason.
local function addBox(player: Player, crateId: string): ({ string }?, string?)
	local crate = Crates[crateId]
	local boxId = HttpService:GenerateGUID(false)
	local uids: { string } = {}
	for _ = 1, crate.itemCount do
		local itemId, golden = ShipmentService.RollItem(crateId)
		local uid = itemId and InventoryService.Add(player, itemId, {
			state = "Unopened",
			golden = golden,
			crateId = crateId,
			boxId = boxId,
		})
		if uid == nil then
			for _, added in uids do -- undo the partial box
				InventoryService.Remove(player, added)
			end
			return nil, "addFailed"
		end
		table.insert(uids, uid)
	end
	return uids, nil
end

local function notify(player: any, kind: string, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, kind, text)
	end
end

-- Special pull 2, TIME CAPSULE: a bought crate may hold a sealed capsule = extra bonus items from better odds (Rare, Epic, Legendary).
-- The bonus items join the same box (same boxId), so the box simply holds more items; no new data field and no new remote.
-- Returns how many bonus items were added (0 if the crate had no capsule or nothing could be added).
function ShipmentService.MaybeAddTimeCapsule(player: Player, crateId: string, boxUids: { string }, random: Random?): number
	local chance = Economy.TimeCapsuleChance[crateId]
	local crate = Crates[crateId]
	local r = random or rng
	if chance == nil or crate == nil or r:NextNumber() >= chance or #boxUids == 0 then
		return 0
	end
	local first = InventoryService.Get(player, boxUids[1])
	local boxId = first and first.boxId
	local added = 0
	for _ = 1, Economy.TimeCapsuleBonusItems do
		local roll = r:NextNumber() * 100
		local running, chosen = 0, "Rare"
		for _, rarity in { "Rare", "Epic", "Legendary" } do
			running += Economy.TimeCapsuleOdds[rarity] or 0
			if roll < running then
				chosen = rarity
				break
			end
		end
		local pool = itemsOf(crate.tier, chosen)
		if #pool > 0 then
			local uid = InventoryService.Add(player, pool[r:NextInteger(1, #pool)], {
				state = "Unopened",
				golden = r:NextNumber() < Economy.GoldenChance,
				crateId = crateId,
				boxId = boxId,
			})
			if uid then
				table.insert(boxUids, uid)
				added += 1
			end
		end
	end
	if added > 0 then
		notify(player, "Delivery", "⏳ TIME CAPSULE! Your crate held a sealed capsule: bonus treasures inside!")
	end
	return added
end

-- The Warehouse supply counter (a Part placed in Studio). nil if this place has no warehouse.
local function supplyCounter(): BasePart?
	local env = workspace:FindFirstChild("Environment")
	local districts = env and env:FindFirstChild("Districts")
	local warehouse = districts and districts:FindFirstChild("Warehouse")
	local counter = warehouse and warehouse:FindFirstChild("SupplyCounter")
	return if counter and counter:IsA("BasePart") then counter else nil
end

-- True when the player is close enough to the Warehouse supply counter to buy crates (Economy.SupplyMaxStuds).
function ShipmentService.IsNearSupply(player: Player): boolean
	local counter = supplyCounter()
	return counter ~= nil and Validate.withinDistance(player, counter, Economy.SupplyMaxStuds)
end

-- Buys a crate with cash. Returns ok, reason, uids.
-- Reasons: unknown, free (use the free delivery), noData, level, tooManyBoxes, cash, addFailed.
function ShipmentService.BuyCrate(player: Player, crateId: string): (boolean, string?, { string }?)
	if not Validate.isConfigId(crateId, Crates) then
		return false, "unknown", nil
	end
	local crate = Crates[crateId]
	if crate.price <= 0 then
		return false, "free", nil
	end
	local level = DataService.GetValue(player, "level")
	if type(level) ~= "number" then
		return false, "noData", nil
	end
	if level < crate.requiredLevel then
		return false, "level", nil
	end
	local boxes = InventoryService.CountWaitingBoxes(player)
	if boxes >= Economy.MaxWaitingBoxes then
		return false, "tooManyBoxes", nil
	end
	if not EconomyService.Spend(player, crate.price) then
		return false, "cash", nil
	end
	local uids, reason = addBox(player, crateId)
	if uids == nil then
		EconomyService.AddCash(player, crate.price, "Refund")
		return false, reason, nil
	end
	ShipmentService.MaybeAddTimeCapsule(player, crateId, uids)
	log.info(`bought {crateId}: {#uids} items`)
	notify(player, "Delivery", "Crate delivered!")
	return true, nil, uids
end

-- Claims the free delivery if the timer has elapsed and no free box is waiting.
-- Reasons: noData, tooSoon, alreadyWaiting, tooManyBoxes, addFailed. Returns ok, reason, uids.
function ShipmentService.ClaimFreeDelivery(player: Player, now: number?): (boolean, string?, { string }?)
	local last = DataService.GetValue(player, "timers.lastFreeDelivery")
	if type(last) ~= "number" then
		return false, "noData", nil
	end
	local time = now or os.time()
	if time - last < Economy.FreeDeliveryIntervalSeconds then
		return false, "tooSoon", nil
	end
	local boxes, freeWaiting = InventoryService.CountWaitingBoxes(player)
	if freeWaiting >= Economy.FreeDeliveryMaxWaiting then
		return false, "alreadyWaiting", nil
	end
	if boxes >= Economy.MaxWaitingBoxes then
		return false, "tooManyBoxes", nil
	end
	local uids, reason = addBox(player, "FreeDelivery")
	if uids == nil then
		return false, reason, nil
	end
	DataService.Set(player, "timers.lastFreeDelivery", time)
	notify(player, "Delivery", "Free delivery arrived!")
	return true, nil, uids
end

-- A brand-new player (never had a free delivery) gets the guaranteed first box: Economy.FirstBoxItemId, not golden.
function ShipmentService.GrantFirstBox(player: Player): boolean
	local last = DataService.GetValue(player, "timers.lastFreeDelivery")
	if last ~= 0 then
		return false -- nil = no data, otherwise they already had their first delivery
	end
	local uid = InventoryService.Add(player, Economy.FirstBoxItemId, {
		state = "Unopened",
		golden = false,
		crateId = "FreeDelivery",
		boxId = HttpService:GenerateGUID(false),
	})
	if uid == nil then
		return false
	end
	DataService.Set(player, "timers.lastFreeDelivery", os.time())
	log.info(`first box for {player.Name}`)
	return true
end

-- Opens an Unopened item: it becomes Dirty (needs inventory room), the collection records it, first finds pay a bonus.
-- Returns ok, reason, info = { itemId, golden, isNew, bonus }.
function ShipmentService.OpenBox(player: Player, uid: string): (boolean, string?, { [string]: any }?)
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem", nil
	end
	if item.state ~= "Unopened" then
		return false, "notUnopened", nil
	end
	local ok, reason = InventoryService.Update(player, uid, { state = "Dirty" })
	if not ok then
		if reason == "full" then
			notify(player, "Info", "Your inventory is full. Sell something or buy Storage Racks.")
		end
		return false, reason, nil
	end

	local def = Items[item.itemId]
	local isNew = CollectionBookService.RecordFound(player, item.itemId, item.golden) == true
	local bonus = 0
	if isNew then
		bonus = Rarities[def.rarity].firstFindBonus[def.tier] or 0
		if bonus > 0 then
			EconomyService.AddCash(player, bonus, "Bonus")
		end
	end

	if Validate.isPlayer(player) then
		Remotes.BoxOpened:FireClient(player, uid, item.itemId, item.golden, isNew)
	end
	if def.rarity == "Relic" then
		-- unique wording for the rarest pull in the game, shown to everyone on the server
		local name = if Validate.isPlayer(player) then player.DisplayName else tostring(player.Name)
		Remotes.Announcement:FireAllClients(`✨ LOST MASTERPIECE! {name} unearthed the {def.name}!`, def.rarity)
	elseif def.rarity == "Legendary" then
		local name = if Validate.isPlayer(player) then player.DisplayName else tostring(player.Name)
		Remotes.Announcement:FireAllClients(`{name} found a Legendary {def.name}!`, def.rarity)
	end
	return true, nil, { itemId = item.itemId, golden = item.golden, isNew = isNew, bonus = bonus }
end

function ShipmentService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	InventoryService = services.InventoryService
	CollectionBookService = services.CollectionBookService
	PlotService = services.PlotService
	log.info("Init")
end

function ShipmentService.Start()
	Remotes.RequestOpenBox.OnServerEvent:Connect(function(player, uid)
		if not Validate.rateLimit(player, "RequestOpenBox", 3) or type(uid) ~= "string" then
			return
		end
		-- Boxes are opened at the door: the player must be near their own DeliveryPoint.
		local plot = PlotService.GetPlot(player)
		local point = plot and plot:FindFirstChild("DeliveryPoint")
		if point == nil or not Validate.withinDistance(player, point, Economy.InteractMaxStuds) then
			return
		end
		ShipmentService.OpenBox(player, uid)
	end)

	Remotes.RequestBuyCrate.OnServerEvent:Connect(function(player, crateId)
		if not Validate.rateLimit(player, "RequestBuyCrate", 3) or type(crateId) ~= "string" then
			return
		end
		-- Crates are sold at the Supply Warehouse (Environment.Districts.Warehouse.SupplyCounter), not from anywhere:
		-- the player has to walk there. The server checks it so the client can't skip the walk.
		if not ShipmentService.IsNearSupply(player) then
			notify(player, "Info", "📦 Crates are sold at the Supply Warehouse, at the south end of Workshop Lane.")
			return
		end
		local ok, reason = ShipmentService.BuyCrate(player, crateId)
		if not ok and reason == "cash" then
			notify(player, "Info", "Not enough cash for that crate.")
		elseif not ok and reason == "tooManyBoxes" then
			notify(player, "Info", "Open your waiting boxes first.")
		elseif not ok and reason == "level" then
			notify(player, "Info", `Reach level {Crates[crateId].requiredLevel} to order that crate.`)
		end
	end)

	Remotes.RequestClaimFreeDelivery.OnServerEvent:Connect(function(player)
		if not Validate.rateLimit(player, "RequestClaimFreeDelivery", 2) then
			return
		end
		local plot = PlotService.GetPlot(player)
		local point = plot and plot:FindFirstChild("DeliveryPoint")
		if point == nil or not Validate.withinDistance(player, point, Economy.InteractMaxStuds) then
			return
		end
		ShipmentService.ClaimFreeDelivery(player)
	end)

	-- New players get their guaranteed first box once their data is loaded.
	DataService.OnPlayerLoaded(function(player)
		ShipmentService.GrantFirstBox(player)
	end)
	log.info("Start")
end

return ShipmentService
