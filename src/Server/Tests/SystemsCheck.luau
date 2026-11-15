-- SystemsCheck.luau (ServerScriptService.Server.Tests.SystemsCheck)
-- Purpose: tests EconomyService, InventoryService, CollectionBookService, UpgradeService and ShipmentService.
-- Owner: Dev 1 (Ace). Depends on: those services, Shared.Config, Shared.Formulas.
-- Safe by design: copies of the services are wired to a FAKE in-memory DataService and mock players, so it never
-- touches PlayerData_DEV or the running game. Run in the Studio command bar while Playing (Server):
--   require(game.ServerScriptService.Server.Tests.SystemsCheck).run()
-- Expected numbers are worked out by hand from docs/01 and docs/02, not read back from the code under test.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SystemsCheck = {}

-- Same shape as the template in DataService (docs/03 §10.5).
local function newData()
	return {
		version = 1, cash = 100, xp = 0, level = 1, inventory = {}, upgrades = {}, collection = {},
		likes = { received = 0, givenToday = {}, rewardedToday = 0, day = 0 },
		stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
		timers = { lastFreeDelivery = 0 },
		tutorial = { step = 0, done = false },
		settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
	}
end

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

-- A minimal stand-in for DataService (same function names, same refusals that matter to these services).
local function makeFakeDataService()
	local store: { [any]: any } = {}
	local fake = {}
	function fake.Get(p)
		return store[p] and deepCopy(store[p])
	end
	function fake.GetValue(p, path)
		local node = store[p]
		if node == nil or type(path) ~= "string" then
			return nil
		end
		for _, part in string.split(path, ".") do
			if type(node) ~= "table" then
				return nil
			end
			node = node[part]
		end
		return deepCopy(node)
	end
	function fake.Set(p, path, value)
		local node = store[p]
		if node == nil then
			return false
		end
		local parts = string.split(path, ".")
		if store[p][parts[1]] == nil then
			return false
		end
		if value == nil and #parts == 1 then
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
	fake._store = store
	return fake
end

function SystemsCheck.run()
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

	-- Fresh copies of the services (a required module is cached, so we clone to get untouched instances).
	local kit = Instance.new("Folder")
	kit.Name = "SystemsCheckKit"
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	ServerScriptService.Server.Lib:Clone().Parent = kit
	for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "UpgradeService", "ShipmentService" } do
		ServerScriptService.Server.Services[name]:Clone().Parent = services
	end
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local Config = ReplicatedStorage.Shared.Config
		local Crates = require(Config.Crates)
		local Items = require(Config.Items)

		local fakeDS = makeFakeDataService()
		local refreshCalls = 0
		local plotStub = {
			RefreshSlots = function()
				refreshCalls += 1
			end,
			GetPlot = function()
				return nil
			end,
		}
		local S: { [string]: any } = { DataService = fakeDS, PlotService = plotStub }
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "UpgradeService", "ShipmentService" } do
			S[name] = require(services[name])
		end
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "UpgradeService", "ShipmentService" } do
			S[name].Init(S)
		end
		local Economy, Inventory, Collection, Upgrade, Shipment =
			S.EconomyService, S.InventoryService, S.CollectionBookService, S.UpgradeService, S.ShipmentService

		local nextId = 0
		local function newPlayer(): any
			nextId += 1
			local p = { UserId = 9000 + nextId, Name = "Mock" .. nextId, DisplayName = "Mock" .. nextId }
			fakeDS._store[p] = newData()
			return p
		end
		local function cash(p): number
			return fakeDS.GetValue(p, "cash")
		end

		-- ===== EconomyService =====
		local p = newPlayer()
		check("Economy: AddCash 50 -> 150", Economy.AddCash(p, 50) and cash(p) == 150)
		local before = cash(p)
		for label, bad in { negative = -5, fraction = 1.5, nan = 0 / 0, inf = math.huge, text = "9", missing = nil } do
			check("Economy: AddCash rejects " .. label, Economy.AddCash(p, bad) == false and cash(p) == before)
		end
		check("Economy: Spend 30 -> 120", Economy.Spend(p, 30) and cash(p) == 120)
		check("Economy: Spend more than owned refused, cash unchanged", Economy.Spend(p, 121) == false and cash(p) == 120)
		check("Economy: Spend 0 is allowed", Economy.Spend(p, 0) and cash(p) == 120)
		check("Economy: Spend rejects negative and fraction", Economy.Spend(p, -1) == false and Economy.Spend(p, 0.5) == false and cash(p) == 120)
		check("Economy: CanAfford", Economy.CanAfford(p, 120) and not Economy.CanAfford(p, 121) and not Economy.CanAfford(p, -1))
		Economy.AddCash(p, 40, "Sale")
		check("Economy: reason Sale counts into stats.earned", fakeDS.GetValue(p, "stats.earned") == 40)
		Economy.AddCash(p, 10, "Bonus")
		check("Economy: other reasons don't count as earned", fakeDS.GetValue(p, "stats.earned") == 40)

		local q = newPlayer() -- cash 100, level 1, xp 0
		check("Economy: 39 XP stays level 1", select(2, Economy.AddXp(q, 39)) == 0 and fakeDS.GetValue(q, "level") == 1 and fakeDS.GetValue(q, "xp") == 39)
		local _, gained = Economy.AddXp(q, 1)
		check("Economy: 40 XP total reaches level 2, xp resets", gained == 1 and fakeDS.GetValue(q, "level") == 2 and fakeDS.GetValue(q, "xp") == 0)
		check("Economy: level-up pays $50 x new level (100 + 100)", cash(q) == 200, cash(q))
		_, gained = Economy.AddXp(q, 121 + 232) -- exactly Lv 2->3 and 3->4
		check("Economy: one big gain passes two levels", gained == 2 and fakeDS.GetValue(q, "level") == 4 and fakeDS.GetValue(q, "xp") == 0)
		check("Economy: rewards for both levels (150 + 200)", cash(q) == 200 + 150 + 200, cash(q))
		check("Economy: AddXp rejects bad amounts", Economy.AddXp(q, -1) == false and Economy.AddXp(q, 2.5) == false and Economy.AddXp(q, 0 / 0) == false)
		local r = newPlayer()
		Economy.AddXp(r, 1000000)
		check("Economy: huge XP stops at the cap (level 15, xp 0)", fakeDS.GetValue(r, "level") == 15 and fakeDS.GetValue(r, "xp") == 0)
		check("Economy: all rewards paid (100 + 50 x (2+...+15) = 6050)", cash(r) == 6050, cash(r))
		check("Economy: XP at the cap changes nothing", select(2, Economy.AddXp(r, 500)) == 0 and fakeDS.GetValue(r, "level") == 15 and fakeDS.GetValue(r, "xp") == 0)

		-- ===== InventoryService =====
		local i = newPlayer()
		check("Inventory: default capacity 8", Inventory.GetCapacity(i) == 8)
		fakeDS.Set(i, "upgrades.StorageRacks", 2)
		check("Inventory: Storage Racks L2 -> capacity 24", Inventory.GetCapacity(i) == 24)
		fakeDS.Set(i, "upgrades.StorageRacks", nil)
		local uids = {}
		for n = 1, 8 do
			local uid = Inventory.Add(i, "RubberDuck", { state = "Dirty" })
			table.insert(uids, uid)
		end
		check("Inventory: 8 Dirty items fill the inventory", #uids == 8 and Inventory.CountUsed(i) == 8 and not Inventory.HasRoom(i))
		local uid9, reason9 = Inventory.Add(i, "RubberDuck", { state = "Dirty" })
		check("Inventory: 9th counted item refused (full)", uid9 == nil and reason9 == "full")
		local boxUid = Inventory.Add(i, "Teacup")
		check("Inventory: Unopened items are allowed when full and not counted", boxUid ~= nil and Inventory.CountUsed(i) == 8)
		local okOpen, reasonOpen = Inventory.Update(i, boxUid, { state = "Dirty" })
		check("Inventory: opening (Unopened -> Dirty) refused when full", okOpen == false and reasonOpen == "full")
		check("Inventory: item stays Unopened after refusal", Inventory.Get(i, boxUid).state == "Unopened")
		check("Inventory: unknown item refused", select(2, Inventory.Add(i, "NoSuchItem")) == "unknownItem")
		check("Inventory: bad state refused", select(2, Inventory.Add(i, "Teacup", { state = "Broken" })) == "badState")
		check("Inventory: new item has the right fields", (function()
			local item = Inventory.Get(i, boxUid)
			return item.itemId == "Teacup" and item.golden == false and item.stepIndex == 1 and type(item.stepScores) == "table"
				and type(item.acquiredAt) == "number" and item.uid == boxUid
		end)())
		check("Inventory: Update state ok", Inventory.Update(i, uids[1], { state = "InProgress", stepIndex = 2, stepScores = { 80 } }) and Inventory.Get(i, uids[1]).stepIndex == 2)
		check("Inventory: Update stars/slot ok", Inventory.Update(i, uids[1], { state = "Restored", stars = 3 }) and Inventory.Get(i, uids[1]).stars == 3)
		local good = Inventory.Get(i, uids[2]).state
		local okBad = Inventory.Update(i, uids[2], { state = "Restored", stars = 9 })
		check("Inventory: Update is all-or-nothing (bad stars rejects the state change too)", okBad == false and Inventory.Get(i, uids[2]).state == good)
		check("Inventory: can't change itemId/golden/uid", Inventory.Update(i, uids[2], { itemId = "Jukebox" }) == false and Inventory.Update(i, uids[2], { golden = true }) == false and Inventory.Get(i, uids[2]).itemId == "RubberDuck")
		check("Inventory: bad field values rejected", Inventory.Update(i, uids[2], { stepIndex = 0 }) == false and Inventory.Update(i, uids[2], { stepScores = { 101 } }) == false and Inventory.Update(i, uids[2], { slot = 1.5 }) == false and Inventory.Update(i, uids[2], { state = 5 }) == false)
		check("Inventory: ClearField removes stars", Inventory.ClearField(i, uids[1], "stars") and Inventory.Get(i, uids[1]).stars == nil)
		check("Inventory: uid with a dot is refused everywhere", Inventory.Get(i, "a.b") == nil and Inventory.Remove(i, "a.b") == false and Inventory.Update(i, "a.b", { state = "Dirty" }) == false)
		check("Inventory: Get of unknown uid is nil", Inventory.Get(i, "00000000-0000-0000-0000-000000000000") == nil)
		check("Inventory: Remove works once", Inventory.Remove(i, uids[3]) and Inventory.Get(i, uids[3]) == nil and Inventory.Remove(i, uids[3]) == false)
		check("Inventory: capacity frees up after Remove", Inventory.HasRoom(i))

		-- waiting boxes: one box of 3 items + one free box = 2 boxes, 1 free
		local w = newPlayer()
		for _ = 1, 3 do
			Inventory.Add(w, "RubberDuck", { crateId = "Starter", boxId = "box-A" })
		end
		Inventory.Add(w, "RubberDuck", { crateId = "FreeDelivery", boxId = "box-B" })
		local boxes, free = Inventory.CountWaitingBoxes(w)
		check("Inventory: 3 items of one box + a free box = 2 boxes, 1 free", boxes == 2 and free == 1, `{boxes},{free}`)

		-- Quick sell: values from FormulasCheck (RubberDuck 2 stars = $8, Golden 2 stars = $25)
		local s = newPlayer()
		local duck = Inventory.Add(s, "RubberDuck", { state = "Restored" })
		Inventory.Update(s, duck, { stars = 2 })
		local sellOk, _, amount = Inventory.QuickSell(s, duck)
		check("QuickSell: Rubber Duck 2 stars pays $8", sellOk and amount == 8 and cash(s) == 108, cash(s))
		check("QuickSell: item is gone, sold +1, earned +8", Inventory.Get(s, duck) == nil and fakeDS.GetValue(s, "stats.sold") == 1 and fakeDS.GetValue(s, "stats.earned") == 8)
		local goldDuck = Inventory.Add(s, "RubberDuck", { state = "Restored", golden = true })
		Inventory.Update(s, goldDuck, { stars = 2 })
		check("QuickSell: Golden Rubber Duck 2 stars pays $25", select(3, Inventory.QuickSell(s, goldDuck)) == 25)
		local dirty = Inventory.Add(s, "RubberDuck", { state = "Dirty" })
		check("QuickSell: a Dirty item can't be sold", Inventory.QuickSell(s, dirty) == false and Inventory.Get(s, dirty) ~= nil)
		check("QuickSell: unknown uid refused", Inventory.QuickSell(s, "nope") == false)
		local displayed = Inventory.Add(s, "RubberDuck", { state = "Displayed" })
		check("QuickSell: a Displayed item can't be quick sold", Inventory.QuickSell(s, displayed) == false)

		-- ===== CollectionBookService =====
		local c = newPlayer()
		check("Collection: first find returns true", Collection.RecordFound(c, "TinRobot", false) == true)
		check("Collection: entry saved", fakeDS.GetValue(c, "collection.TinRobot.found") == true and fakeDS.GetValue(c, "collection.TinRobot.bestStars") == 0)
		check("Collection: second find returns false", Collection.RecordFound(c, "TinRobot", false) == false)
		check("Collection: finding a Golden later marks golden", Collection.RecordFound(c, "TinRobot", true) == false and fakeDS.GetValue(c, "collection.TinRobot.golden") == true)
		check("Collection: unknown item returns nil", Collection.RecordFound(c, "Nope", false) == nil)
		check("Collection: RecordRestored keeps the best stars", Collection.RecordRestored(c, "TinRobot", 2) and Collection.RecordRestored(c, "TinRobot", 1) and fakeDS.GetValue(c, "collection.TinRobot.bestStars") == 2)
		check("Collection: RecordRestored raises stars", Collection.RecordRestored(c, "TinRobot", 3) and fakeDS.GetValue(c, "collection.TinRobot.bestStars") == 3)
		check("Collection: RecordRestored creates an entry for a new item", Collection.RecordRestored(c, "Teacup", 1) and fakeDS.GetValue(c, "collection.Teacup.bestStars") == 1)
		check("Collection: RecordRestored rejects bad stars", Collection.RecordRestored(c, "Teacup", 4) == false and Collection.RecordRestored(c, "Teacup", 0) == false)

		-- rating points (docs/02 §6): Back Room 3 + Showroom 8 = 11; plants L2 = 2; exhibits: Epic 4, Golden Legendary 8 x 2 = 16
		local g = newPlayer()
		check("Rating: no upgrades = 0 points, 1 star", Collection.GetRatingPoints(g) == 0 and Collection.GetRatingStars(g) == 1)
		fakeDS.Set(g, "upgrades.BackRoom", 1)
		fakeDS.Set(g, "upgrades.Showroom", 1)
		check("Rating: Back Room + Showroom = 11 points", Collection.GetRatingPoints(g) == 11, Collection.GetRatingPoints(g))
		fakeDS.Set(g, "upgrades.PottedPlants", 2)
		check("Rating: Potted Plants L2 adds 2 (total owned, not 1+2)", Collection.GetRatingPoints(g) == 13, Collection.GetRatingPoints(g))
		Inventory.Add(g, "TinRobot", { state = "Exhibited" })
		check("Rating: exhibited Epic adds 4", Collection.GetRatingPoints(g) == 17, Collection.GetRatingPoints(g))
		Inventory.Add(g, "Gramophone", { state = "Exhibited", golden = true })
		check("Rating: exhibited Golden Legendary adds 16", Collection.GetRatingPoints(g) == 33, Collection.GetRatingPoints(g))
		Inventory.Add(g, "ToyCar", { state = "Displayed" })
		check("Rating: displayed (for sale) items add nothing", Collection.GetRatingPoints(g) == 33)
		check("Rating: 33 points = 3 stars", Collection.GetRatingStars(g) == 3)

		-- ===== UpgradeService =====
		local u = newPlayer()
		fakeDS.Set(u, "cash", 100000)
		check("Upgrade: unknown id refused", select(2, Upgrade.BuyUpgrade(u, "Nope")) == "unknown" and select(2, Upgrade.BuyUpgrade(u, 5)) == "unknown")
		local bought, _, lvl = Upgrade.BuyUpgrade(u, "CleaningBrush")
		check("Upgrade: Brush L1 costs $150", bought and lvl == 1 and cash(u) == 100000 - 150 and fakeDS.GetValue(u, "upgrades.CleaningBrush") == 1)
		check("Upgrade: purchase refreshes plot slots", refreshCalls == 1)
		check("Upgrade: Brush L2 needs player level 5", select(2, Upgrade.BuyUpgrade(u, "CleaningBrush")) == "level" and cash(u) == 100000 - 150)
		fakeDS.Set(u, "level", 5)
		check("Upgrade: Brush L2 at level 5 costs $1500", Upgrade.BuyUpgrade(u, "CleaningBrush") and cash(u) == 100000 - 150 - 1500)
		fakeDS.Set(u, "level", 10)
		Upgrade.BuyUpgrade(u, "CleaningBrush")
		check("Upgrade: Brush L4 does not exist (maxed)", select(2, Upgrade.BuyUpgrade(u, "CleaningBrush")) == "maxed")
		check("Upgrade: Fish Tank refused without the Back Room (even at level 10)", select(2, Upgrade.BuyUpgrade(u, "FishTank")) == "requires" and fakeDS.GetValue(u, "upgrades.FishTank") == nil)
		check("Upgrade: Fountain refused without the Showroom", select(2, Upgrade.BuyUpgrade(u, "Fountain")) == "requires")
		check("Upgrade: Back Room needs level 4 (ok at 10), $2500", (function()
			local before2 = cash(u)
			return Upgrade.BuyUpgrade(u, "BackRoom") and cash(u) == before2 - 2500
		end)())
		check("Upgrade: Fish Tank allowed once the Back Room is owned ($3000)", (function()
			local before2 = cash(u)
			return Upgrade.BuyUpgrade(u, "FishTank") and cash(u) == before2 - 3000
		end)())
		local poor = newPlayer() -- $100, level 1
		check("Upgrade: not enough cash refused, cash unchanged", select(2, Upgrade.BuyUpgrade(poor, "Rug")) == "cash" and cash(poor) == 100 and fakeDS.GetValue(poor, "upgrades.Rug") == nil)
		check("Upgrade: affordable decor works ($80 plant)", Upgrade.BuyUpgrade(poor, "PottedPlants") and cash(poor) == 20 and fakeDS.GetValue(poor, "upgrades.PottedPlants") == 1)
		check("Upgrade: no data refused", select(2, Upgrade.BuyUpgrade({ UserId = 1, Name = "ghost" }, "Rug")) == "noData")

		-- ===== ShipmentService: rolls =====
		local seeded = Random.new(12345)
		local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
		local goldenCount, total, valueSum = 0, 200000, 0
		for _ = 1, total do
			local itemId, golden = Shipment.RollItem("Starter", seeded)
			local def = Items[itemId]
			counts[def.rarity] += 1
			valueSum += def.baseValue
			if golden then
				goldenCount += 1
			end
			if def.tier ~= 1 then
				check("Shipment: Starter only drops tier 1", false, itemId)
				break
			end
		end
		local function near(actual: number, expected: number, tolerance: number): boolean
			return math.abs(actual - expected) <= tolerance
		end
		check("Shipment: Starter Common ~60%", near(counts.Common / total * 100, 60, 1), counts.Common / total * 100)
		check("Shipment: Starter Uncommon ~25%", near(counts.Uncommon / total * 100, 25, 1))
		check("Shipment: Starter Rare ~10%", near(counts.Rare / total * 100, 10, 1))
		check("Shipment: Starter Epic ~4%", near(counts.Epic / total * 100, 4, 0.5))
		check("Shipment: Starter Legendary ~1%", near(counts.Legendary / total * 100, 1, 0.4))
		check("Shipment: Golden ~2%", near(goldenCount / total * 100, 2, 0.4), goldenCount / total * 100)
		check("Shipment: Starter average item value ~ $37.50 (docs/02 §3)", near(valueSum / total, 37.5, 1.5), valueSum / total)
		seeded = Random.new(999)
		local fleaSum, fleaTier2 = 0, true
		for _ = 1, total do
			local itemId = Shipment.RollItem("FleaMarket", seeded)
			fleaSum += Items[itemId].baseValue
			fleaTier2 = fleaTier2 and Items[itemId].tier == 2
		end
		check("Shipment: Flea Market only drops tier 2", fleaTier2)
		check("Shipment: Flea Market average ~ $204 (docs/02 §3)", near(fleaSum / total, 204, 8), fleaSum / total)
		local freeCommonOnlyUpTo = true
		seeded = Random.new(7)
		for _ = 1, 20000 do
			local itemId = Shipment.RollItem("FreeDelivery", seeded)
			local rarity = Items[itemId].rarity
			if rarity == "Epic" or rarity == "Legendary" then
				freeCommonOnlyUpTo = false
			end
		end
		check("Shipment: Free Delivery never drops Epic or Legendary", freeCommonOnlyUpTo)
		check("Shipment: unknown crate rolls nothing", Shipment.RollItem("Nope") == nil)
		local a1, a2 = Shipment.RollItem("Starter", Random.new(5)), Shipment.RollItem("Starter", Random.new(5))
		check("Shipment: same seed gives the same item", a1 == a2)

		-- ===== ShipmentService: buying =====
		local b = newPlayer()
		fakeDS.Set(b, "cash", 1000)
		local okBuy, _, boughtUids = Shipment.BuyCrate(b, "Starter")
		check("Shipment: Starter crate costs $50 and adds 3 Unopened items", okBuy and #boughtUids == 3 and cash(b) == 950)
		check("Shipment: the 3 items share one box and are Unopened", (function()
			local first = Inventory.Get(b, boughtUids[1])
			local boxCount = Inventory.CountWaitingBoxes(b)
			return first.state == "Unopened" and first.crateId == "Starter" and boxCount == 1
				and Inventory.Get(b, boughtUids[3]).boxId == first.boxId
		end)())
		check("Shipment: Flea Market needs level 5", select(2, Shipment.BuyCrate(b, "FleaMarket")) == "level" and cash(b) == 950)
		check("Shipment: Free Delivery can't be bought", select(2, Shipment.BuyCrate(b, "FreeDelivery")) == "free")
		check("Shipment: unknown / bad crate id refused", select(2, Shipment.BuyCrate(b, "Nope")) == "unknown" and select(2, Shipment.BuyCrate(b, 5)) == "unknown")
		Shipment.BuyCrate(b, "Starter")
		Shipment.BuyCrate(b, "Starter")
		check("Shipment: 3 waiting boxes now", Inventory.CountWaitingBoxes(b) == 3 and cash(b) == 850)
		check("Shipment: 4th box refused (max 3 waiting), no money taken", select(2, Shipment.BuyCrate(b, "Starter")) == "tooManyBoxes" and cash(b) == 850)
		local broke = newPlayer()
		fakeDS.Set(broke, "cash", 49)
		check("Shipment: $49 can't buy a $50 crate, no items added", select(2, Shipment.BuyCrate(broke, "Starter")) == "cash" and select(1, Inventory.CountWaitingBoxes(broke)) == 0)
		fakeDS.Set(b, "level", 5)
		Inventory.Remove(b, boughtUids[1])
		-- (removing one item doesn't clear the box; box still waiting)
		check("Shipment: removing one item doesn't free a box slot", Inventory.CountWaitingBoxes(b) == 3)

		-- ===== ShipmentService: first box and free delivery =====
		local f = newPlayer()
		check("Shipment: new player gets the first box (RubberDuck)", Shipment.GrantFirstBox(f))
		local firstUid = next(fakeDS.GetValue(f, "inventory"))
		check("Shipment: first box is an Unopened, non-golden Rubber Duck", (function()
			local item = Inventory.Get(f, firstUid)
			return item.itemId == "RubberDuck" and item.state == "Unopened" and item.golden == false and item.crateId == "FreeDelivery"
		end)())
		check("Shipment: first box starts the free delivery timer", fakeDS.GetValue(f, "timers.lastFreeDelivery") > 0)
		check("Shipment: first box is granted only once", Shipment.GrantFirstBox(f) == false and Inventory.CountWaitingBoxes(f) == 1)
		local t0 = fakeDS.GetValue(f, "timers.lastFreeDelivery")
		check("Shipment: free delivery refused before 180 s", select(2, Shipment.ClaimFreeDelivery(f, t0 + 179)) == "tooSoon")
		check("Shipment: free delivery refused while the first free box still waits", select(2, Shipment.ClaimFreeDelivery(f, t0 + 180)) == "alreadyWaiting")
		Inventory.Remove(f, firstUid)
		local claimed, _, claimUids = Shipment.ClaimFreeDelivery(f, t0 + 180)
		check("Shipment: free delivery after 180 s adds 1 Unopened item", claimed and #claimUids == 1 and fakeDS.GetValue(f, "timers.lastFreeDelivery") == t0 + 180)
		check("Shipment: second claim right after is refused", select(2, Shipment.ClaimFreeDelivery(f, t0 + 181)) == "tooSoon")
		check("Shipment: GrantFirstBox needs loaded data", Shipment.GrantFirstBox({ UserId = 2, Name = "ghost" }) == false)

		-- ===== ShipmentService: opening =====
		local o = newPlayer()
		local oUid = Inventory.Add(o, "TinRobot") -- Epic, tier 1: first-find bonus $120 (docs/02 §2)
		local opened, _, info = Shipment.OpenBox(o, oUid)
		check("Open: Unopened -> Dirty", opened and Inventory.Get(o, oUid).state == "Dirty")
		check("Open: first find is NEW and pays $120 (Epic, tier 1)", info.isNew == true and info.bonus == 120 and cash(o) == 220, cash(o))
		check("Open: collection now has TinRobot", fakeDS.GetValue(o, "collection.TinRobot.found") == true)
		check("Open: opening the same item again refused", select(2, Shipment.OpenBox(o, oUid)) == "notUnopened")
		local oUid2 = Inventory.Add(o, "TinRobot")
		local _, _, info2 = Shipment.OpenBox(o, oUid2)
		check("Open: second TinRobot is not NEW and pays no bonus", info2.isNew == false and info2.bonus == 0 and cash(o) == 220)
		local tier2Uid = Inventory.Add(o, "Jukebox") -- Legendary; check which tier
		local _, _, info3 = Shipment.OpenBox(o, tier2Uid)
		local jukebox = Items.Jukebox
		check("Open: Legendary first find pays the tier-correct bonus", info3.bonus == require(Config.Rarities).Legendary.firstFindBonus[jukebox.tier], info3.bonus)
		check("Open: unknown uid refused", select(2, Shipment.OpenBox(o, "zzz")) == "noItem")
		local fullPlayer = newPlayer()
		for _ = 1, 8 do
			Inventory.Add(fullPlayer, "RubberDuck", { state = "Dirty" })
		end
		local fullBox = Inventory.Add(fullPlayer, "Teacup")
		check("Open: refused when the inventory is full, box stays closed, no bonus", select(2, Shipment.OpenBox(fullPlayer, fullBox)) == "full" and Inventory.Get(fullPlayer, fullBox).state == "Unopened" and cash(fullPlayer) == 100)

		-- Crate data sanity: every crate item count matches Config
		check("Config: Starter crate gives 3 items", Crates.Starter.itemCount == 3)
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end

	for _, line in lines do
		print(line)
	end
	print(`[SystemsCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return SystemsCheck
