-- MonetizationCheck.luau (ServerScriptService.Server.Tests.MonetizationCheck)
-- Purpose: tests the Robux rules (docs/12 Stage 5): the config, MonetizationService prompts / grants / receipts / VIP choices, and that
-- pass-only theme items can't be bought with cash or rolled into stock. Pure: a COPY of the service with fake DataService and a fake
-- MarketplaceService (no real prompts, no real money) and fake players.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.MonetizationCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MonetizationCheck = {}

function MonetizationCheck.run()
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

	local Config = require(ReplicatedStorage.Shared.Config.Monetization)
	local Paints = require(ReplicatedStorage.Shared.Config.Paints)
	local Skins = require(ReplicatedStorage.Shared.Config.Skins)
	local Stock = require(ReplicatedStorage.Shared.Stock)

	-- ===== config =====
	local idsOk, pricesOk, grantsOk, unique = true, true, true, {}
	for _, pass in Config.PASSES do
		if Config.BY_PASS[pass.id] ~= pass or unique[pass.id] then
			idsOk = false
		end
		unique[pass.id] = true
		if type(pass.price) ~= "number" or pass.price <= 0 or type(pass.passId) ~= "number" or pass.passId < 0 or type(pass.name) ~= "string" then
			pricesOk = false
		end
		for _, id in if pass.grants then pass.grants.paints or {} else {} do
			if Paints.BY_ID[id] == nil or Paints.BY_ID[id].pass ~= pass.id then
				grantsOk = false
			end
		end
		for _, id in if pass.grants then pass.grants.skins or {} else {} do
			if Skins.BY_ID[id] == nil or Skins.BY_ID[id].pass ~= pass.id then
				grantsOk = false
			end
		end
	end
	for _, product in Config.PRODUCTS do
		if Config.BY_PRODUCT[product.id] ~= product or unique[product.id] or type(product.price) ~= "number" or product.price <= 0 or type(product.productId) ~= "number" then
			idsOk = false
		end
		unique[product.id] = true
	end
	check("config: pass and product ids are unique and indexed", idsOk)
	check("config: every pass has a name, a positive price and a Roblox id (0 = not created yet)", pricesOk)
	check("config: a theme pass grants only paints and skins that are marked with that pass", grantsOk)
	check("config: the approved passes exist", Config.BY_PASS.VIP and Config.BY_PASS.Companion and Config.BY_PASS.GlowPack and Config.BY_PASS.SavedLayouts and Config.BY_PASS.BigStorage and Config.BY_PASS.ThemeArcade and Config.BY_PASS.ThemeCabin ~= nil)
	check("config: Big Storage gives the approved +16 slots", Config.BY_PASS.BigStorage.storageSlots == 16)
	local Formulas = require(ReplicatedStorage.Shared.Formulas)
	local Economy = require(ReplicatedStorage.Shared.Config.Economy)
	check("storage: the Big Storage pass adds 16 slots on top of the racks, nothing else changes it", Formulas.inventoryCapacity(0, { BigStorage = true }) == Economy.StartingInventoryCapacity + 16
		and Formulas.inventoryCapacity(0) == Economy.StartingInventoryCapacity and Formulas.inventoryCapacity(0, {}) == Economy.StartingInventoryCapacity
		and Formulas.inventoryCapacity(2, { BigStorage = true }) == Formulas.inventoryCapacity(2) + 16 and Formulas.inventoryCapacity(1, { VIP = true }) == Formulas.inventoryCapacity(1))
	check("config: VIP choice lists are filled", #Config.VIP.Pets >= 3 and #Config.VIP.AuraStyles >= 3 and #Config.VIP.Titles >= 3 and Config.VIP.TitleMaxLength > 0)

	-- ===== pass-only items stay out of cash shops and stock =====
	local stockClean = true
	for i = 1, 3000 do
		for _, id in Stock.roll(i) do
			if Skins.BY_ID[id].pass ~= nil then
				stockClean = false
			end
		end
	end
	check("themes: pass-only skins never appear in the stock roll", stockClean)

	-- ===== MonetizationService + PaintService + SkinService on copies with fakes =====
	local kit = Instance.new("Folder")
	kit.Name = "MonetizationCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local copy = ServerScriptService.Server.Services.MonetizationService:Clone()
	copy.Parent = services
	local paintCopy = ServerScriptService.Server.Services.PaintService:Clone()
	paintCopy.Parent = services
	kit.Parent = ServerScriptService

	local savedIds = {}
	for _, pass in Config.PASSES do
		savedIds[pass.id] = pass.passId
	end
	local savedProducts = {}
	for _, product in Config.PRODUCTS do
		savedProducts[product.id] = product.productId
	end

	local ok, err = pcall(function()
		-- give every pass a pretend Roblox id for the test, restored afterwards
		for i, pass in Config.PASSES do
			pass.passId = 9000 + i
		end
		for i, product in Config.PRODUCTS do
			product.productId = 8000 + i
		end
		local store = {}
		local failSet = false
		local fakeDS = {
			Get = function(p)
				return store[p]
			end,
			GetValue = function(p, path)
				local node = store[p]
				for _, part in string.split(path, ".") do
					if type(node) ~= "table" then
						return nil
					end
					node = node[part]
				end
				return node
			end,
			Set = function(p, path, value)
				if failSet then
					return false
				end
				local node = store[p]
				local parts = string.split(path, ".")
				for i = 1, #parts - 1 do
					node = node[parts[i]]
				end
				node[parts[#parts]] = value
				return true
			end,
		}
		local owned: { [number]: boolean } = {} -- the fake Roblox: which pass ids the player owns
		local prompts = {}
		local fakeMarket = {
			UserOwnsGamePassAsync = function(_, _, passId)
				return owned[passId] == true
			end,
			PromptGamePassPurchase = function(_, _, passId)
				table.insert(prompts, "pass" .. passId)
			end,
			PromptProductPurchase = function(_, _, productId)
				table.insert(prompts, "product" .. productId)
			end,
		}
		local Service = require(copy)
		Service.Init({ DataService = fakeDS })
		local p = { UserId = 555, Name = "PassMock" }
		local players = { [555] = p }
		Service.SetMarketplace(fakeMarket, function(id)
			return players[id]
		end)
		local function fresh()
			store[p] = {
				entitlements = {},
				vip = { title = "", pet = "", petColor = "", auraStyle = "" },
				paints = { owned = {}, wall = "", floor = "" },
				skins = { owned = {}, shelf = "", pedestal = "", cashier = "" },
			}
		end
		fresh()

		-- prompts
		check("prompt: an unknown pass or a non-string key is refused", select(2, Service.PromptPass(p, "NoSuch")) == "unknown" and select(2, Service.PromptPass(p, 5)) == "unknown" and #prompts == 0)
		check("prompt: a pass opens Roblox's purchase window", Service.PromptPass(p, "BigStorage") == true and prompts[1] == "pass" .. Config.BY_PASS.BigStorage.passId)
		local realId = Config.BY_PASS.GlowPack.passId
		Config.BY_PASS.GlowPack.passId = 0
		check("prompt: a pass not created on Roblox yet is refused as comingSoon", select(2, Service.PromptPass(p, "GlowPack")) == "comingSoon" and #prompts == 1)
		Config.BY_PASS.GlowPack.passId = realId
		check("prompt: a tip opens the product window", Service.PromptProduct(p, "TipSmall") == true and prompts[2] == "product" .. Config.BY_PRODUCT.TipSmall.productId)
		check("prompt: an unknown product is refused", select(2, Service.PromptProduct(p, "NoSuch")) == "unknown")

		-- grants and ownership
		check("owns: nothing at the start", Service.Has(p, "BigStorage") == false)
		check("purchase finished but Roblox does not show it as owned: nothing is granted", (function()
			Service.OnPassPurchaseFinished(p, Config.BY_PASS.BigStorage.passId, true)
			return Service.Has(p, "BigStorage") == false
		end)())
		owned[Config.BY_PASS.BigStorage.passId] = true
		Service.OnPassPurchaseFinished(p, Config.BY_PASS.BigStorage.passId, false)
		check("purchase window closed without buying: nothing is granted", Service.Has(p, "BigStorage") == false)
		Service.OnPassPurchaseFinished(p, Config.BY_PASS.BigStorage.passId, true)
		check("purchase finished and Roblox confirms: the pass is saved", Service.Has(p, "BigStorage") == true and store[p].entitlements.BigStorage == true)
		check("prompt: an owned pass can't be bought twice", select(2, Service.PromptPass(p, "BigStorage")) == "owned")
		check("grant: an unknown pass is refused", select(2, Service.Grant(p, "NoSuch")) == "unknown")
		check("grant: granting twice is harmless", Service.Grant(p, "BigStorage", true) == true and Service.Has(p, "BigStorage") == true)
		failSet = true
		check("grant: a failed save is refused", select(2, Service.Grant(p, "GlowPack", true)) == "saveFailed" and Service.Has(p, "GlowPack") == false)
		failSet = false
		store[p].entitlements = nil
		check("grant: a player with no data is refused", select(2, Service.Grant(p, "GlowPack", true)) == "noData")
		fresh()
		check("themes: the Arcade pass gives its paints and skins", Service.Grant(p, "ThemeArcade", true) == true and store[p].paints.owned.WallArcade == true and store[p].paints.owned.FloorArcade == true and store[p].skins.owned.ShelfArcade == true and store[p].skins.owned.PedestalArcade == true and store[p].skins.owned.CashierArcade == true)
		check("themes: another theme's items are not given", store[p].paints.owned.WallCabin == nil and store[p].skins.owned.ShelfCabin == nil)

		-- join-time re-check
		fresh()
		owned = { [Config.BY_PASS.Companion.passId] = true, [Config.BY_PASS.VIP.passId] = true }
		Service.CheckOwnedPasses(p)
		check("re-check: passes Roblox says you own are restored on join", Service.Has(p, "Companion") == true and Service.Has(p, "VIP") == true and Service.Has(p, "GlowPack") == false)

		-- receipts
		local decisions = Enum.ProductPurchaseDecision
		check("receipt: a tip is granted (thank-you only, nothing else changes)", Service.HandleReceipt({ PlayerId = 555, ProductId = Config.BY_PRODUCT.TipMedium.productId, PurchaseId = "a1" }) == decisions.PurchaseGranted)
		check("receipt: the same purchase again is still granted, never double-processed", Service.HandleReceipt({ PlayerId = 555, ProductId = Config.BY_PRODUCT.TipMedium.productId, PurchaseId = "a1" }) == decisions.PurchaseGranted)
		check("receipt: a player who left is retried later", Service.HandleReceipt({ PlayerId = 999, ProductId = Config.BY_PRODUCT.TipMedium.productId, PurchaseId = "a2" }) == decisions.NotProcessedYet)
		check("receipt: a product that isn't ours is not consumed", Service.HandleReceipt({ PlayerId = 555, ProductId = 12345, PurchaseId = "a3" }) == decisions.NotProcessedYet)

		-- VIP choices
		fresh()
		check("vip: choices need the VIP pass", select(2, Service.SetVip(p, "pet", "Cat")) == "notVip")
		Service.Grant(p, "VIP", true)
		check("vip: a pet from the list is saved", Service.SetVip(p, "pet", "Bunny") == true and store[p].vip.pet == "Bunny")
		check("vip: a pet that isn't in the list is refused", select(2, Service.SetVip(p, "pet", "Dragon")) == "badValue" and store[p].vip.pet == "Bunny")
		check("vip: pet colour and aura style from the lists are saved", Service.SetVip(p, "petColor", "Mint") == true and Service.SetVip(p, "auraStyle", "Sakura") == true and store[p].vip.auraStyle == "Sakura")
		check("vip: an unknown aura style or field is refused", select(2, Service.SetVip(p, "auraStyle", "Rainbow")) == "badValue" and select(2, Service.SetVip(p, "cash", "99999")) == "badField")
		check("vip: a non-string value is refused", select(2, Service.SetVip(p, "title", 123)) == "badValue" and select(2, Service.SetVip(p, "pet", nil)) == "badValue")
		check("vip: a preset title is saved", Service.SetVip(p, "title", Config.VIP.Titles[1]) == true and store[p].vip.title == Config.VIP.Titles[1])
		check("vip: a title that is too long is refused", select(2, Service.SetVip(p, "title", string.rep("a", Config.VIP.TitleMaxLength + 1))) == "badTitle")
		check("vip: a title with odd characters is refused", select(2, Service.SetVip(p, "title", "<b>Hi</b>")) == "badTitle" and select(2, Service.SetVip(p, "title", "Hi\nthere")) == "badTitle")
		check("vip: an empty custom title (spaces only) is refused", select(2, Service.SetVip(p, "title", "   ")) == "badTitle")
		check("vip: \"\" clears a choice", Service.SetVip(p, "pet", "") == true and store[p].vip.pet == "")
		failSet = true
		check("vip: a failed save is refused", select(2, Service.SetVip(p, "pet", "Cat")) == "saveFailed")
		failSet = false

		-- layout slots (Saved Layouts pass 3, VIP +1)
		check("slots: none without a pass, 3 with Saved Layouts, +1 with VIP, 4 with both", Config.layoutSlots(nil) == 0 and Config.layoutSlots({}) == 0
			and Config.layoutSlots({ SavedLayouts = true }) == 3 and Config.layoutSlots({ VIP = true }) == 1 and Config.layoutSlots({ SavedLayouts = true, VIP = true }) == 4)
		local layoutCopy = ServerScriptService.Server.Services.LayoutService:Clone()
		layoutCopy.Parent = services
		local LS = require(layoutCopy)
		LS.Init({ DataService = fakeDS })
		store[p] = { entitlements = {}, layout = { Shelf3 = { x = 4, z = 6, rot = 0, floor = "Ground" } }, layoutSlots = {} }
		check("slots: saving without a pass is refused", select(2, LS.SaveSlot(p, 1)) == "noSlot" and next(store[p].layoutSlots) == nil)
		store[p].entitlements = { SavedLayouts = true }
		check("slots: with the pass, slot 1 keeps a copy of the saved layout", LS.SaveSlot(p, 1) == true and store[p].layoutSlots["1"] ~= nil and store[p].layoutSlots["1"].Shelf3 ~= nil)
		check("slots: slot 4 needs VIP, 0 and 1.5 and text are not slots", select(2, LS.SaveSlot(p, 4)) == "noSlot" and select(2, LS.SaveSlot(p, 0)) == "noSlot" and select(2, LS.SaveSlot(p, 1.5)) == "noSlot" and select(2, LS.SaveSlot(p, "1")) == "noSlot")
		store[p].entitlements = { SavedLayouts = true, VIP = true }
		check("slots: VIP adds a 4th slot", LS.SaveSlot(p, 4) == true and store[p].layoutSlots["4"] ~= nil)
		store[p].layout = {}
		check("slots: an empty (default) shop can be saved too", LS.SaveSlot(p, 2) == true and next(store[p].layoutSlots["2"]) == nil)
		check("slots: using an empty slot is refused", select(2, LS.LoadSlot(p, 3)) == "empty")
		check("slots: using a slot you can't have is refused", select(2, LS.LoadSlot(p, 5)) == "noSlot")
		store[p].entitlements = {}
		check("slots: without the pass nothing can be used (even a saved slot)", select(2, LS.LoadSlot(p, 1)) == "noSlot")
		store[p].entitlements = { SavedLayouts = true }
		failSet = true
		check("slots: a failed save is refused", select(2, LS.SaveSlot(p, 3)) == "saveFailed")
		failSet = false
		store[p].layoutSlots = nil
		check("slots: a profile without the slots field is refused safely", select(2, LS.SaveSlot(p, 1)) == "noData" and select(2, LS.LoadSlot(p, 1)) == "noData")

		-- pass-only paints can't be bought with cash
		local Paint = require(paintCopy)
		Paint.Init({ DataService = fakeDS, EconomyService = { Spend = function() return true end, AddCash = function() end } })
		Paint.SetNearCheck(function()
			return true
		end)
		store[p] = { paints = { owned = {}, wall = "", floor = "" } }
		check("themes: a theme paint can't be bought with cash", select(2, Paint.Buy(p, "WallArcade")) == "passOnly" and store[p].paints.owned.WallArcade == nil)
	end)

	for _, pass in Config.PASSES do
		pass.passId = savedIds[pass.id]
	end
	for _, product in Config.PRODUCTS do
		product.productId = savedProducts[product.id]
	end
	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[MonetizationCheck]", line)
		end
	end
	print(`[MonetizationCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return MonetizationCheck
