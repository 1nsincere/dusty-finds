-- CustomerCheck.luau (ServerScriptService.Server.Tests.CustomerCheck)
-- Purpose: tests CustomerService on copies of the real services with a fake in-memory DataService, a fake plot and a
-- fake clock. Never touches saved data or the real Plots folder.
-- Owner: Dev 1 (Ace). Depends on: CustomerService, DisplayService, InventoryService, CollectionBookService, EconomyService.
-- Run while Playing (Server): require(game.ServerScriptService.Server.Tests.CustomerCheck).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CustomerCheck = {}

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

local function newData()
	return {
		version = 1, cash = 100, xp = 0, level = 1, inventory = {}, upgrades = {}, collection = {},
		likes = { received = 0, givenToday = {}, rewardedToday = 0, day = 0 },
		stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
		timers = { lastFreeDelivery = 0 }, tutorial = { step = 0, done = false },
		settings = { music = true, sfx = true, reduceEffects = false, announcements = true },
	}
end

local function makeFakeDataService()
	local store: { [any]: any } = {}
	local fake = { _store = store }
	function fake.Get(p)
		return store[p] and deepCopy(store[p])
	end
	function fake.GetValue(p, path)
		local node = store[p]
		for _, part in string.split(path, ".") do
			if type(node) ~= "table" then
				return nil
			end
			node = node[part]
		end
		return deepCopy(node)
	end
	function fake.Set(p, path, value)
		local parts = string.split(path, ".")
		local node = store[p]
		if node == nil or (value == nil and #parts == 1) then
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
	function fake.Push() end
	function fake.AddSnapshotExtra() end
	function fake.OnPlayerLoaded() end
	function fake.OnPlayerReleasing() end
	return fake
end

function CustomerCheck.run()
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

	local kit = Instance.new("Folder")
	kit.Name = "CustomerCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "DisplayService" } do
		ServerScriptService.Server.Services[name]:Clone().Parent = services
	end
	ServerScriptService.Server.Services.CustomerService:Clone().Parent = services
	kit.Parent = ServerScriptService

	local plotHolder = Instance.new("Folder")
	plotHolder.Name = "CustomerCheckPlots"
	plotHolder.Parent = ServerScriptService
	local function makePlot(): Model -- 6 display slots, all enabled
		local plot = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "DisplaySlots"
		folder.Parent = plot
		for i = 1, 6 do
			local part = Instance.new("Part")
			part.Name = "Slot" .. i
			part:SetAttribute("SlotIndex", i)
			part:SetAttribute("Enabled", true)
			part.Parent = folder
		end
		plot.Parent = plotHolder
		return plot
	end

	local ok, err = pcall(function()
		local Formulas = require(ReplicatedStorage.Shared.Formulas)
		local Economy = require(ReplicatedStorage.Shared.Config.Economy)

		local fakeDS = makeFakeDataService()
		local plotOf: { [any]: Model } = {}
		local plotStub = {
			GetPlot = function(p)
				return plotOf[p]
			end,
			RefreshSlots = function() end,
		}
		local S: { [string]: any } = { DataService = fakeDS, PlotService = plotStub }
		local names = { "EconomyService", "InventoryService", "CollectionBookService", "DisplayService" }
		for _, name in names do
			S[name] = require(services[name])
		end
		S.CustomerService = require(services.CustomerService)
		for _, name in names do
			S[name].Init(S)
		end
		S.CustomerService.Init(S) -- (Start is NOT called: it would start the real one-second spawn loop)
		local Inv, Disp, Cust = S.InventoryService, S.DisplayService, S.CustomerService

		local count = 0
		local function newPlayer(): any
			count += 1
			local p = { UserId = 9500 + count, Name = "Mock" .. count, DisplayName = "Mock" .. count }
			fakeDS._store[p] = newData()
			plotOf[p] = makePlot()
			return p
		end
		-- Puts a Restored 2-star item on the next free display slot. Returns its uid.
		local slotCounter: { [any]: number } = {}
		local function shelve(p, itemId: string): string
			local uid = Inv.Add(p, itemId, { state = "Restored" })
			Inv.Update(p, uid, { stars = 2 })
			slotCounter[p] = (slotCounter[p] or 0) + 1
			assert(Disp.PlaceDisplay(p, uid, slotCounter[p]), "test setup: could not place " .. itemId)
			return uid
		end
		local noTip = { NextNumber = function() return 0.99 end } -- roll 99%: never tips
		local tipRoll = { NextNumber = function() return 0.12 end } -- roll 12%: tips only with chance > 12%

		-- ===== types and wishes =====
		local tally: { [string]: number } = {}
		local rng = Random.new(1)
		for _ = 1, 20000 do
			local id = Cust.PickType(rng)
			tally[id] = (tally[id] or 0) + 1
		end
		-- weights 25 / 25 / 15 / 25 of 90
		check("type: Collector is ~16.7% of arrivals (weight 15 of 90)", math.abs(tally.Collector / 20000 - 15 / 90) < 0.02, tally.Collector / 20000)
		check("type: Kid, Grandpa and Teen are each ~27.8%", math.abs(tally.Kid / 20000 - 25 / 90) < 0.02 and math.abs(tally.Grandpa / 20000 - 25 / 90) < 0.02 and math.abs(tally.Teen / 20000 - 25 / 90) < 0.02)
		check("type: the same seed gives the same type", Cust.PickType(Random.new(7)) == Cust.PickType(Random.new(7)))

		local kitchenOnly = { { uid = "a", itemId = "Teacup", slot = 1 } }
		local kitchen = 0
		rng = Random.new(2)
		for _ = 1, 10000 do
			if Cust.PickWish(kitchenOnly, rng) == "Kitchen" then
				kitchen += 1
			end
		end
		-- 70% from the display (always Kitchen) + 30% x 1/5 random categories = 76%
		check("wish: ~76% Kitchen when only a Teacup is displayed (70% from display + 30% x 1/5)", math.abs(kitchen / 10000 - 0.76) < 0.02, kitchen / 10000)
		local valid = true
		for _ = 1, 200 do
			local w = Cust.PickWish({}, rng)
			if not table.find(Economy.Categories, w) then
				valid = false
			end
		end
		check("wish: with nothing displayed it is still a real category", valid)

		-- ===== choosing an item (pure) =====
		local duck = { uid = "d", itemId = "RubberDuck", slot = 1 } -- Toys, Common
		local cup = { uid = "c", itemId = "Teacup", slot = 2 } -- Kitchen, Common
		local box = { uid = "m", itemId = "MusicBox", slot = 3 } -- Music, Rare
		local picked, matched = Cust.PickItem("Kid", "Kitchen", { duck, cup }, Random.new(3))
		check("item: a wish match is chosen and flagged", picked.uid == "c" and matched == true)
		local sawDuck, sawCup = false, false
		for seed = 1, 40 do
			local entry, m = Cust.PickItem("Kid", "Music", { duck, cup }, Random.new(seed))
			sawDuck = sawDuck or entry.uid == "d"
			sawCup = sawCup or entry.uid == "c"
			if m then
				sawDuck = false
			end
		end
		check("item: no wish match picks a random item, not flagged", sawDuck and sawCup)
		picked, matched = Cust.PickItem("Collector", "Kitchen", { duck, cup, box }, Random.new(4))
		check("item: a Collector only looks at Rare+ when one is displayed (wish ignored)", picked.uid == "m" and matched == false)
		picked = Cust.PickItem("Collector", "Kitchen", { duck, cup }, Random.new(4))
		check("item: a Collector with only Commons displayed still buys something", picked ~= nil and (picked.uid == "c" or picked.uid == "d"))
		picked, matched = Cust.PickItem("Kid", "Music", { duck, cup, box }, Random.new(9))
		check("item: a Kid wishing for Music matches the Music Box", picked.uid == "m" and matched == true)
		check("item: nothing displayed gives nil", Cust.PickItem("Kid", "Toys", {}, Random.new(1)) == nil)

		-- ===== limits and timing =====
		local p = newPlayer()
		check("max customers: 3 by default, 5 with the Showroom", Cust.MaxCustomers(p) == 3 and (function()
			fakeDS.Set(p, "upgrades.Showroom", 1)
			local five = Cust.MaxCustomers(p) == 5
			fakeDS.Set(p, "upgrades.Showroom", 0)
			return five
		end)())
		check("interval: 30 s with no sign and 1 star", math.abs(Cust.SpawnInterval(p) - 30) < 1e-6)
		fakeDS.Set(p, "upgrades.ShopSign", 2)
		check("interval: Shop Sign level 2 gives 30 x 0.9^2 = 24.3 s", math.abs(Cust.SpawnInterval(p) - 24.3) < 1e-6, Cust.SpawnInterval(p))
		fakeDS.Set(p, "upgrades.ShopSign", 0)

		-- ===== spawning =====
		local stranger = { UserId = 1, Name = "NoData", DisplayName = "NoData" }
		check("spawn: a player with no data is refused", select(2, Cust.TrySpawn(stranger, 0)) == "noData")
		check("spawn: an empty shop gets no customers", select(2, Cust.TrySpawn(p, 0)) == "noItems")
		local teacup = shelve(p, "Teacup")
		local first, reason = Cust.TrySpawn(p, 100, Random.new(5))
		check("spawn: a customer arrives once something is displayed", first ~= nil and reason == nil and require(ReplicatedStorage.Shared.Config.Customers)[first.typeId] ~= nil)
		check("spawn: arrivals are spaced by the interval (29 s later is too soon)", select(2, Cust.TrySpawn(p, 129)) == "tooSoon")
		local second = Cust.TrySpawn(p, 130, Random.new(6))
		check("spawn: the next one comes after 30 s", second ~= nil and second.id ~= first.id)
		local third = Cust.TrySpawn(p, 160, Random.new(7))
		check("spawn: third customer fits (cap 3)", third ~= nil)
		check("spawn: the 4th is refused while 3 are inside", select(2, Cust.TrySpawn(p, 190)) == "full")
		fakeDS.Set(p, "upgrades.Showroom", 1)
		check("spawn: the Showroom raises the cap to 5", Cust.TrySpawn(p, 190, Random.new(8)) ~= nil)
		fakeDS.Set(p, "upgrades.Showroom", 0)

		-- ===== choosing + reservation =====
		check("choose: unknown customer", select(2, Cust.ChooseItem(p, "nope")) == "noCustomer" and select(2, Cust.ChooseItem(p, nil)) == "noCustomer")
		local choice = Cust.ChooseItem(p, first.id, Random.new(1))
		check("choose: the only displayed item is reserved for the customer", choice ~= nil and choice.uid == teacup and choice.itemId == "Teacup")
		check("choose: a reserved item can't be taken off the shelf", select(2, Disp.RemoveFromSlot(p, "Display", 1)) == "reserved")
		check("choose: a customer can only choose once", select(2, Cust.ChooseItem(p, first.id)) == "alreadyChose")
		check("choose: with every item reserved the next customer leaves sad (and is removed)", select(2, Cust.ChooseItem(p, second.id)) == "nothing" and Cust.GetCustomers(p)[second.id] == nil)

		-- ===== checkout =====
		check("checkout: before choosing there is nothing to pay", select(2, Cust.Checkout(p, third.id, true, noTip)) == "noItem")
		local cashBefore = fakeDS._store[p].cash
		local type1 = Cust.GetCustomers(p)[first.id]
		type1.typeId = "Kid"
		type1.wishMatched = true
		local paid, _, sale = Cust.Checkout(p, first.id, true, noTip)
		local price = Formulas.sellPrice("Teacup", 2, false, true)
		check("checkout: tapped Checkout pays the price with the wish bonus + 10%", paid and sale.price == price and sale.bonus == Formulas.checkoutBonus(price) and sale.tip == 0 and fakeDS._store[p].cash == cashBefore + price + sale.bonus, sale and sale.total)
		check("checkout: the item is sold and gone, the customer is gone", Inv.Get(p, teacup) == nil and Cust.GetCustomers(p)[first.id] == nil)
		check("checkout: paying twice is refused", select(2, Cust.Checkout(p, first.id, true, noTip)) == "noCustomer")

		-- auto checkout, tips
		local q = newPlayer()
		local lamp = shelve(q, "StickerAlbum")
		local c1 = Cust.TrySpawn(q, 0, Random.new(11))
		Cust.GetCustomers(q)[c1.id].typeId = "Kid"
		Cust.ChooseItem(q, c1.id, Random.new(1))
		local _, _, auto = Cust.Checkout(q, c1.id, false, tipRoll)
		check("checkout: auto checkout has no +10%", auto ~= nil and auto.bonus == 0 and Inv.Get(q, lamp) == nil)
		check("tip: a Kid (10% chance) does not tip on a 12% roll", auto.tip == 0)
		local lamp2 = shelve(q, "StickerAlbum")
		local c2 = Cust.TrySpawn(q, 100, Random.new(12))
		Cust.GetCustomers(q)[c2.id].typeId = "Collector"
		Cust.ChooseItem(q, c2.id, Random.new(1))
		local tipper = { NextNumber = function(_self, a, b)
			if a then
				return 0.2
			end
			return 0.12
		end }
		local _, _, tipSale = Cust.Checkout(q, c2.id, false, tipper, true) -- served at the till (an unserved auto checkout never tips)
		check("tip: a Collector (15% chance) tips on the same 12% roll, 20% of the price",tipSale ~= nil and tipSale.tip == Formulas.tipAmount(tipSale.price, 0.2) and tipSale.tip > 0, tipSale and tipSale.tip)
		check("checkout: the sold item left the shelf", Inv.Get(q, lamp2) == nil)

		-- leaving, sweeping, vanished items
		local r = newPlayer()
		local vase = shelve(r, "RubberDuck")
		local c3 = Cust.TrySpawn(r, 0, Random.new(13))
		Cust.ChooseItem(r, c3.id, Random.new(1))
		Cust.Leave(r, c3.id)
		check("leave: the reservation is released and the customer is gone", select(1, Disp.RemoveFromSlot(r, "Display", 1)) == true and Cust.GetCustomers(r)[c3.id] == nil)
		Disp.PlaceDisplay(r, vase, 1)
		local c4 = Cust.TrySpawn(r, 100, Random.new(14))
		Cust.ChooseItem(r, c4.id, Random.new(1))
		check("sweep: a customer inside for 419 s stays (limit is 420 s since 2026-11-25)", Cust.Sweep(r, 100 + 419) == 0 and Cust.GetCustomers(r)[c4.id] ~= nil)
		check("sweep: a stuck customer older than 420 s is removed and frees the item", Cust.Sweep(r, 100 + 421) == 1 and Cust.GetCustomers(r)[c4.id] == nil and Disp.GetAvailable(r)[1] ~= nil)
		local c5 = Cust.TrySpawn(r, 600, Random.new(15))
		Cust.ChooseItem(r, c5.id, Random.new(1))
		Inv.Remove(r, vase) -- the item vanishes before checkout
		local vOk, vReason = Cust.Checkout(r, c5.id, true, noTip)
		check("checkout: an item that vanished is refused safely and the customer leaves", vOk == false and vReason ~= nil and Cust.GetCustomers(r)[c5.id] == nil)
		-- ===== removed handler: every way a customer disappears reports a reason =====
		local removedLog: { [string]: string } = {}
		Cust.SetRemovedHandler(function(_player, customerId, reason)
			removedLog[customerId] = reason
		end)
		local s = newPlayer()
		shelve(s, "Teacup")
		local a1 = Cust.TrySpawn(s, 0, Random.new(21))
		Cust.ChooseItem(s, a1.id, Random.new(1))
		Cust.Checkout(s, a1.id, true, noTip)
		check("removed: a paid customer reports \"paid\"", removedLog[a1.id] == "paid")
		shelve(s, "Teacup")
		local a2 = Cust.TrySpawn(s, 100, Random.new(22))
		Cust.Leave(s, a2.id)
		check("removed: Leave reports \"left\" (or the reason you give)", removedLog[a2.id] == "left")
		local a3 = Cust.TrySpawn(s, 200, Random.new(23))
		Cust.Sweep(s, 200 + 421)
		check("removed: a swept customer reports \"timeout\"", removedLog[a3.id] == "timeout")
		local a4 = Cust.TrySpawn(s, 300, Random.new(24))
		local a5 = Cust.TrySpawn(s, 400, Random.new(25)) -- both arrive while the item is still free
		Cust.ChooseItem(s, a4.id, Random.new(1)) -- a4 takes the only item
		Cust.ChooseItem(s, a5.id, Random.new(1)) -- nothing left for a5
		check("removed: a failed ChooseItem reports \"nothing\"", removedLog[a5.id] == "nothing")
		check("removed: RemoveAll (owner left) reports \"playerLeft\" for each customer and releases their items", Cust.RemoveAll(s) == 1 and removedLog[a4.id] == "playerLeft" and next(Cust.GetCustomers(s)) == nil and Disp.GetAvailable(s)[1] ~= nil)
		check("removed: a customer that is already gone reports nothing twice", (function()
			removedLog[a4.id] = nil
			Cust.Leave(s, a4.id)
			return removedLog[a4.id] == nil
		end)())
		Cust.SetRemovedHandler(function()
			error("handler bug")
		end)
		local a6 = Cust.TrySpawn(s, 500, Random.new(26))
		check("removed: an error in the handler does not break the caller", pcall(Cust.Leave, s, a6.id) and Cust.GetCustomers(s)[a6.id] == nil)

		-- ===== spawn handler: own thread, errors handled =====
		local started, finished = 0, 0
		Cust.SetSpawnHandler(function()
			started += 1
			task.wait(0.3) -- NPC code walks for seconds: this must NOT block the loop
			finished += 1
		end)
		Cust.SetRemovedHandler(function(_player, customerId, reason)
			removedLog[customerId] = reason
		end)
		local t = newPlayer()
		shelve(t, "Teacup")
		local ticked = Cust.Tick(t, 0, Random.new(31))
		check("tick: the handler runs in its own thread (Tick returned while it is still waiting)", ticked ~= nil and started == 1 and finished == 0)
		Cust.SetSpawnHandler(function()
			error("npc bug")
		end)
		local broken = Cust.Tick(t, 500, Random.new(32)) -- 500 s: past the 420 s limit, so the first customer is swept too
		check("tick: a spawn handler that errors removes the customer with \"spawnFailed\"", broken ~= nil and Cust.GetCustomers(t)[broken.id] == nil and removedLog[broken.id] == "spawnFailed")
		check("tick: the same tick swept the customer stuck for 500 s (\"timeout\")", removedLog[ticked.id] == "timeout")
		Cust.SetSpawnHandler(nil)
		check("tick: without a handler nothing spawns", Cust.Tick(t, 1000, Random.new(33)) == nil)
		check("no spawn handler set: nothing is called, API is safe to import", pcall(Cust.SetSpawnHandler, nil))
	end)

	plotHolder:Destroy()
	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[CustomerCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return CustomerCheck
