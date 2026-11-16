-- EndToEndCheck.luau (ServerScriptService.Server.Tests.EndToEndCheck)
-- Purpose: walks ONE real player through the whole loop on the LIVE services: first box -> open -> restore (autoRestore, real
-- rules) -> shelf -> a real customer NPC buys it -> money/XP/stats -> shelf cleared. Then puts the test profile back as it was.
-- Owner: Dev 1 (Ace). Depends on: the live services (passed in by DevTools), CustomerNpcService walking the customer.
-- Studio only: run from the command bar WHILE PLAYING (Server):
--   game.ServerStorage.DevTools:Invoke("e2e", game.Players:GetPlayers()[1])
-- It changes your DEV profile while it runs and restores every saved key at the end (a snapshot taken at the start).

local EndToEndCheck = {}

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

-- services = the live services table DevTools got in Init; devTools = DevTools.Invoke-able function for resetProfile/autoRestore
function EndToEndCheck.run(services: { [string]: any }, player: Player, devCall: (...any) -> (boolean, any), waitSeconds: number?)
	local lines: { string } = {}
	local passCount, failCount = 0, 0
	local function step(name: string, cond: boolean, detail: any?)
		if cond then
			passCount += 1
			table.insert(lines, "PASS " .. name .. (if detail ~= nil then " -> " .. tostring(detail) else ""))
		else
			failCount += 1
			table.insert(lines, "FAIL " .. name .. (if detail ~= nil then " -> " .. tostring(detail) else ""))
		end
	end

	local Data, Ship, Inv, Disp, Cust, Plot = services.DataService, services.ShipmentService, services.InventoryService, services.DisplayService, services.CustomerService, services.PlotService
	local function D()
		return Data.Get(player)
	end
	local snapshot = deepCopy(D())

	local ok, err = pcall(function()
		devCall("resetProfile")
		step("reset: brand-new player ($100, one Unopened box)", D().cash == 100)

		local boxUid
		for uid, item in D().inventory do
			if item.state == "Unopened" then
				boxUid = uid
			end
		end
		local opened, openReason, card = Ship.OpenBox(player, boxUid)
		step("open the first box", opened, openReason or (card and card.itemId))

		local itemUid
		for uid, item in D().inventory do
			if item.state == "Dirty" then
				itemUid = uid
			end
		end
		step("the opened item is Dirty in the inventory", itemUid ~= nil)
		if itemUid == nil then
			return
		end

		local restored, result = devCall("autoRestore", itemUid, 100)
		step("restore through the real server rules", restored and type(result) == "table" and result.finished == true, restored and `stars {result.stars}, xp {result.xp}, value {result.value}` or result)
		local item = D().inventory[itemUid]
		step("item is Restored, stats.restored = 1, collection has an entry", item ~= nil and item.state == "Restored" and D().stats.restored == 1 and next(D().collection) ~= nil)

		local placed, placeReason = Disp.PlaceDisplay(player, itemUid, 1)
		step("place it on shelf 1", placed, placeReason)
		local slot = Plot.GetPlot(player).DisplaySlots.Slot1
		step("the slot carries ItemId and Stars for visitors", slot:GetAttribute("ItemId") == item.itemId and slot:GetAttribute("Stars") ~= nil)

		local cashBefore, xpBefore, soldBefore = D().cash, D().xp, D().stats.sold
		local customer, why = Cust.TrySpawn(player)
		step("a customer arrives (TrySpawn)", customer ~= nil, why or (customer and customer.typeId))
		local waited = 0
		local limit = waitSeconds or 70
		while waited < limit and D().stats.sold == soldBefore do
			task.wait(1)
			waited += 1
		end
		step(`a customer bought it (after {waited}s)`, D().stats.sold > soldBefore, `cash {cashBefore} -> {D().cash}, xp {xpBefore} -> {D().xp}, sold {D().stats.sold}`)
		step("cash went up after the sale (XP comes from restoring, not selling: docs/01)", D().cash > cashBefore and D().xp == xpBefore, `cash +{D().cash - cashBefore}`)
		step("the item left the inventory and the shelf attributes are cleared", D().inventory[itemUid] == nil and slot:GetAttribute("ItemId") == nil)
		local left = {}
		for id, c in Cust.GetCustomers(player) do
			table.insert(left, `{c.typeId} uid={tostring(c.uid)}`)
		end
		local holding = 0
		for _, c in Cust.GetCustomers(player) do
			if c.uid == itemUid then
				holding += 1
			end
		end
		step("nobody still holds the sold item (a second customer may still be walking in: it leaves by itself)", holding == 0, if #left > 0 then "in flight: " .. table.concat(left, "; ") else nil)
	end)
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL e2e crashed: " .. tostring(err))
	end

	-- put the test profile back exactly as it was
	Cust.RemoveAll(player, "test finished")
	for key, value in snapshot do
		if key ~= "version" then
			Data.Set(player, key, deepCopy(value))
		end
	end
	Plot.RefreshSlots(player)
	Disp.SyncSlots(player)
	step("test profile restored", D().cash == snapshot.cash and D().level == snapshot.level)

	for _, line in lines do
		print(line)
	end
	print(`[EndToEndCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return EndToEndCheck
