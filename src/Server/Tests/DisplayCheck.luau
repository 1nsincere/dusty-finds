-- DisplayCheck.luau (ServerScriptService.Server.Tests.DisplayCheck)
-- Purpose: tests DisplayService on copies with a fake in-memory DataService
-- and a fake plot (real slot part names + Enabled attributes). Never touches saved data or the real Plots folder.
-- Owner: Dev 1 (Ace). Depends on: DisplayService, EconomyService, InventoryService, CollectionBookService, Shared.Config.
-- Run while Playing (Server): require(game.ServerScriptService.Server.Tests.DisplayCheck).run()

local ServerScriptService = game:GetService("ServerScriptService")

local DisplayCheck = {}

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
		if node == nil or node[parts[1]] == nil or (value == nil and #parts == 1) then
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

function DisplayCheck.run()
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
	kit.Name = "DisplayCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	for _, name in { "EconomyService", "InventoryService", "CollectionBookService" } do
		ServerScriptService.Server.Services[name]:Clone().Parent = services
	end
	ServerScriptService.Server.Services.DisplayService:Clone().Parent = services
	kit.Parent = ServerScriptService

	-- A fake plot: 4 display slots (1-3 enabled) and 2 exhibit slots (1 enabled), with the real part names.
	local plotHolder = Instance.new("Folder")
	plotHolder.Name = "DisplayCheckPlots"
	plotHolder.Parent = ServerScriptService
	local function makePlot(): Model
		local plot = Instance.new("Model")
		local function slots(folderName: string, prefix: string, slotCount: number, enabled: number)
			local folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = plot
			for i = 1, slotCount do
				local part = Instance.new("Part")
				part.Name = prefix .. i
				part:SetAttribute("SlotIndex", i)
				part:SetAttribute("Enabled", i <= enabled)
				part.Parent = folder
			end
		end
		slots("DisplaySlots", "Slot", 4, 3)
		slots("ExhibitSlots", "Exhibit", 2, 1)
		plot.Parent = plotHolder
		return plot
	end

	local ok, err = pcall(function()
		local fakeDS = makeFakeDataService()
		local plotOf: { [any]: Model } = {}
		local plotStub = {
			GetPlot = function(p)
				return plotOf[p]
			end,
			RefreshSlots = function() end,
		}
		local S: { [string]: any } = { DataService = fakeDS, PlotService = plotStub }
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService" } do
			S[name] = require(services[name])
		end
		S.DisplayService = require(services.DisplayService)
		for _, name in { "EconomyService", "InventoryService", "CollectionBookService", "DisplayService" } do
			S[name].Init(S)
		end
		local Inv, Disp, Collection = S.InventoryService, S.DisplayService, S.CollectionBookService

		local count = 0
		local function newPlayer(withPlot: boolean?): any
			count += 1
			local p = { UserId = 8000 + count, Name = "Mock" .. count, DisplayName = "Mock" .. count }
			fakeDS._store[p] = newData()
			if withPlot ~= false then
				plotOf[p] = makePlot()
			end
			return p
		end
		local function restored(p, itemId: string?): string
			local uid = Inv.Add(p, itemId or "Teacup", { state = "Restored" })
			Inv.Update(p, uid, { stars = 2 })
			return uid
		end

		-- ===== display =====
		local p = newPlayer()
		local a = restored(p)
		check("display: a Restored item goes on an enabled slot", select(1, Disp.PlaceDisplay(p, a, 1)))
		local item = Inv.Get(p, a)
		local slot1 = plotOf[p].DisplaySlots.Slot1
		check("attributes: the slot shows ItemId, Golden and Stars for visitors", slot1:GetAttribute("ItemId") == "Teacup" and slot1:GetAttribute("Golden") == false and slot1:GetAttribute("Stars") == 2)
		check("display: item is Displayed in slot 1", item.state == "Displayed" and item.slot == 1)
		local b = restored(p)
		check("display: a taken slot is refused", select(2, Disp.PlaceDisplay(p, b, 1)) == "slotTaken" and Inv.Get(p, b).state == "Restored")
		check("display: a locked slot is refused", select(2, Disp.PlaceDisplay(p, b, 4)) == "slotLocked")
		check("display: a slot that doesn't exist is refused", select(2, Disp.PlaceDisplay(p, b, 9)) == "badSlot")
		check(
			"display: bad slot values refused (0, 1.5, nil, text, nan)",
			select(2, Disp.PlaceDisplay(p, b, 0)) == "badSlot"
				and select(2, Disp.PlaceDisplay(p, b, 1.5)) == "badSlot"
				and select(2, Disp.PlaceDisplay(p, b, nil)) == "badSlot"
				and select(2, Disp.PlaceDisplay(p, b, "2")) == "badSlot"
				and select(2, Disp.PlaceDisplay(p, b, 0 / 0)) == "badSlot"
		)
		check(
			"display: bad uids refused",
			select(2, Disp.PlaceDisplay(p, "nope", 2)) == "noItem"
				and select(2, Disp.PlaceDisplay(p, 5, 2)) == "noItem"
				and select(2, Disp.PlaceDisplay(p, nil, 2)) == "noItem"
		)
		local dirty = Inv.Add(p, "Teacup", { state = "Dirty" })
		local box = Inv.Add(p, "Teacup")
		check("display: Dirty and Unopened items are refused", select(2, Disp.PlaceDisplay(p, dirty, 2)) == "notRestored" and select(2, Disp.PlaceDisplay(p, box, 2)) == "notRestored")
		check("display: an item already Displayed can't be placed again", select(2, Disp.PlaceDisplay(p, a, 2)) == "notRestored")
		check("display: second slot works", select(1, Disp.PlaceDisplay(p, b, 2)) and Inv.Get(p, b).slot == 2)
		check("display: another player's uid is refused", select(2, Disp.PlaceDisplay(newPlayer(), a, 1)) == "noItem")

		-- ===== exhibit =====
		local e = restored(p, "TinRobot")
		check("exhibit: a Restored item goes on the enabled pedestal", select(1, Disp.PlaceExhibit(p, e, 1)) and Inv.Get(p, e).state == "Exhibited" and Inv.Get(p, e).slot == 1)
		local e2 = restored(p, "TinRobot")
		check("exhibit: pedestal 1 is taken, pedestal 2 locked", select(2, Disp.PlaceExhibit(p, e2, 1)) == "slotTaken" and select(2, Disp.PlaceExhibit(p, e2, 2)) == "slotLocked")
		check("exhibit and display slot numbers don't clash (both use slot 1)", Inv.Get(p, a).slot == 1 and Inv.Get(p, e).slot == 1 and select(2, Disp.PlaceDisplay(p, e2, 1)) == "slotTaken")
		check("exhibit: the exhibited Epic gives rating points (4)", Collection.GetRatingPoints(p) == 4, Collection.GetRatingPoints(p))
		check("bad kind refused", select(2, Disp.RemoveFromSlot(p, "Shelf", 1)) == "badKind" and select(2, Disp.RemoveFromSlot(p, nil, 1)) == "badKind")

		-- ===== no plot =====
		local lost = newPlayer(false)
		local lostItem = restored(lost)
		check("no plot: placing is refused", select(2, Disp.PlaceDisplay(lost, lostItem, 1)) == "noPlot")

		-- ===== removing =====
		local okRemove, _, removedUid = Disp.RemoveFromSlot(p, "Display", 1)
		check("attributes: removing clears them", slot1:GetAttribute("ItemId") == nil and slot1:GetAttribute("Golden") == nil and slot1:GetAttribute("Stars") == nil)
		check("remove: the item goes back to Restored with no slot", okRemove and removedUid == a and Inv.Get(p, a).state == "Restored" and Inv.Get(p, a).slot == nil)
		check("remove: an empty slot is reported", select(2, Disp.RemoveFromSlot(p, "Display", 1)) == "empty" and select(2, Disp.RemoveFromSlot(p, "Display", 3)) == "empty")
		check("remove: the freed slot can be used again", select(1, Disp.PlaceDisplay(p, a, 1)))
		check("remove: removing the exhibit drops the rating points", select(1, Disp.RemoveFromSlot(p, "Exhibit", 1)) and Collection.GetRatingPoints(p) == 0)

		-- ===== reservations (for customers) =====
		check("reserve: a Displayed item can be reserved", Disp.Reserve(p, a, "cust1") == true)
		check("reserve: a second customer can't take the same item", Disp.Reserve(p, a, "cust2") == false)
		check("reserve: a reserved item can't be removed", select(2, Disp.RemoveFromSlot(p, "Display", 1)) == "reserved" and Inv.Get(p, a).state == "Displayed")
		local available = Disp.GetAvailable(p)
		check("available: lists only unreserved Displayed items (only slot 2)", #available == 1 and available[1].slot == 2 and available[1].uid == b)
		Disp.Release(p, a, "cust2")
		check("release: the wrong customer can't release it", select(2, Disp.RemoveFromSlot(p, "Display", 1)) == "reserved")
		Disp.Release(p, a, "cust1")
		check("release: the right customer frees it, and it can be reserved again", #Disp.GetAvailable(p) == 2 and Disp.Reserve(p, a, "cust3") == true)
		check(
			"reserve: Dirty, Exhibited-or-Restored and unknown items can't be reserved",
			Disp.Reserve(p, dirty, "x") == false and Disp.Reserve(p, e, "x") == false and Disp.Reserve(p, "nope", "x") == false and Disp.Reserve(p, a, nil) == false
		)
		local sold = Inv.CompleteSale(p, a, { wishMatched = false, checkout = false, random = Random.new(1) })
		check("sale: a reserved Displayed item can be sold with CompleteSale", sold == true and Inv.Get(p, a) == nil)
		check("attributes: a sale clears them", slot1:GetAttribute("ItemId") == nil)
		check("sale: slot 1 is free again afterwards", select(1, Disp.PlaceDisplay(p, restored(p), 1)))

		-- ===== SyncSlots rebuilds from saved items (after a reload) =====
		local r = newPlayer()
		local ritem = restored(r, "TinRobot")
		Disp.PlaceExhibit(r, ritem, 1)
		Inv.Update(r, ritem, { stars = 3 })
		local pedestal = plotOf[r].ExhibitSlots.Exhibit1
		pedestal:SetAttribute("ItemId", nil)
		pedestal:SetAttribute("Stars", nil)
		Disp.SyncSlots(r)
		check("SyncSlots: rebuilds the exhibit attributes from the saved item (Stars 3)", pedestal:GetAttribute("ItemId") == "TinRobot" and pedestal:GetAttribute("Stars") == 3 and pedestal:GetAttribute("Golden") == false)
		check("SyncSlots: other slots stay empty, other players' plots are untouched", plotOf[r].DisplaySlots.Slot1:GetAttribute("ItemId") == nil and plotOf[p].DisplaySlots.Slot2:GetAttribute("ItemId") == "Teacup")

		-- ===== inventory capacity =====
		local q = newPlayer()
		local shelfItem = restored(q)
		Disp.PlaceDisplay(q, shelfItem, 1)
		for _ = 1, 8 do -- fill the 8-slot inventory (the shelf item doesn't count)
			Inv.Add(q, "Teacup", { state = "Dirty" })
		end
		check("remove: refused when the inventory is full, the item stays on the shelf", select(2, Disp.RemoveFromSlot(q, "Display", 1)) == "full" and Inv.Get(q, shelfItem).state == "Displayed")
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
	print(`[DisplayCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return DisplayCheck
