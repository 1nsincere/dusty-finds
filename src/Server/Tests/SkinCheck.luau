-- SkinCheck.luau (ServerScriptService.Server.Tests.SkinCheck)
-- Purpose: tests the skins stall rules: the shared stock roll (Shared.Stock) and SkinService's Buy / Apply checks and
-- drawing. Pure: a COPY of SkinService with fake DataService / EconomyService and a fake player; drawing is tested on a
-- copy of one plot. Never touches a real profile or the real plots.
-- Owner: Dev 3 (Sean). Depends on: Services.SkinService, Shared.Stock, Shared.Config (Skins, Stock).
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.SkinCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkinCheck = {}

function SkinCheck.run()
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

	local Skins = require(ReplicatedStorage.Shared.Config.Skins)
	local StockConfig = require(ReplicatedStorage.Shared.Config.Stock)
	local Stock = require(ReplicatedStorage.Shared.Stock)

	-- ===== config =====
	local idsOk, kindsOk, pricesOk = true, true, true
	for _, skin in Skins.LIST do
		if Skins.BY_ID[skin.id] ~= skin then
			idsOk = false
		end
		if Skins.FIELD[skin.kind] == nil or not table.find(Skins.KINDS, skin.kind) then
			kindsOk = false
		end
		if type(skin.price) ~= "number" or skin.price <= 0 or typeof(skin.look and skin.look.color) ~= "Color3" then
			pricesOk = false
		end
	end
	check("config: every skin id is unique and indexed", idsOk)
	check("config: every skin is a Shelf, Pedestal or Cashier skin", kindsOk)
	check("config: every skin has a price and a colour", pricesOk)
	check("config: restock every 5 minutes", StockConfig.RestockSeconds == 300)

	-- ===== the stock roll =====
	check("stock: the same restock gives the same list (every server, every client)", table.concat(Stock.roll(1000), ",") == table.concat(Stock.roll(1000), ","))
	local differs = false
	for i = 1, 20 do
		if table.concat(Stock.roll(i), ",") ~= table.concat(Stock.roll(i + 1), ",") then
			differs = true
		end
	end
	check("stock: it changes between restocks", differs)
	check("stock: restock index steps every 300 s", Stock.restockIndex(299) == 0 and Stock.restockIndex(300) == 1 and Stock.secondsLeft(290) == 10)
	local seen, commons, mythics, runs = {}, 0, 0, 4000
	for i = 1, runs do
		local hasCommonShelf = false
		for _, id in Stock.roll(i) do
			seen[id] = true
			local skin = Skins.BY_ID[id]
			if skin.rarity == "Common" and skin.kind == "Shelf" then
				hasCommonShelf = true
			end
			if skin.rarity == "Mythic" then
				mythics += 1
			end
		end
		if hasCommonShelf then
			commons += 1
		end
	end
	check("stock: a common shelf skin is always in stock", commons == runs, commons)
	local everySkin = true
	for _, skin in Skins.LIST do
		if not seen[skin.id] then
			everySkin = false
		end
	end
	check("stock: every skin shows up sometimes (4000 restocks)", everySkin)
	-- 2 kinds x 1.5% = ~3% of restocks have a Mythic: about 120 in 4000
	check("stock: Mythic is rare (~3% of restocks)", mythics > 40 and mythics < 250, mythics)

	-- ===== SkinService buy / apply on a copy with fakes =====
	local kit = Instance.new("Folder")
	kit.Name = "SkinCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local copy = ServerScriptService.Server.Services.SkinService:Clone()
	copy.Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local store = {}
		local spent = 0
		local fakeDS = {
			Get = function(p)
				return store[p]
			end,
			Set = function(p, path, value)
				local node = store[p]
				local parts = string.split(path, ".")
				for i = 1, #parts - 1 do
					node = node[parts[i]]
				end
				node[parts[#parts]] = value
				return true
			end,
		}
		local fakeEconomy = {
			Spend = function(_, amount)
				spent += amount
				return true
			end,
			AddCash = function() end,
		}
		local Service = require(copy)
		Service.Init({ DataService = fakeDS, EconomyService = fakeEconomy })
		local p = { UserId = 777, Name = "SkinMock" }
		store[p] = { skins = { owned = { ShelfMint = true }, shelf = "", pedestal = "", cashier = "" } }

		local index = Stock.restockIndex(os.time())
		local inStock = Stock.roll(index)
		local notInStock
		for _, skin in Skins.LIST do
			if not table.find(inStock, skin.id) and not store[p].skins.owned[skin.id] then
				notInStock = skin.id
				break
			end
		end
		local stockedNew
		for _, id in inStock do
			if not store[p].skins.owned[id] then
				stockedNew = id
				break
			end
		end
		local now = index * StockConfig.RestockSeconds + 1
		check("buy: unknown skin refused", select(2, Service.Buy(p, "NotASkin", now)) == "unknown")
		check("buy: bad input refused", select(2, Service.Buy(p, 42, now)) == "unknown")
		check("buy: a skin you own is refused", select(2, Service.Buy(p, "ShelfMint", now)) == "owned")
		check("buy: a skin that is not in stock is refused", notInStock ~= nil and select(2, Service.Buy(p, notInStock, now)) == "notInStock", notInStock)
		check("buy: far from the stall is refused (no money taken)", stockedNew ~= nil and select(2, Service.Buy(p, stockedNew, now)) == "far" and spent == 0, stockedNew)
		check("buy: no data refused", select(2, Service.Buy({ UserId = 1, Name = "ghost" }, "ShelfMint", now)) == "noData")

		check("apply: bad kind refused", select(2, Service.Apply(p, "Lamp", "ShelfMint")) == "badKind")
		check("apply: a pedestal skin on shelves refused", select(2, Service.Apply(p, "Shelf", "PedestalMarble")) == "wrongKind")
		check("apply: a skin you don't own refused", select(2, Service.Apply(p, "Shelf", "ShelfWalnut")) == "notOwned")
		check("apply: bad input refused", select(2, Service.Apply(p, "Shelf", 5)) == "unknown")
		check("apply: an owned skin is saved", Service.Apply(p, "Shelf", "ShelfMint") == true and store[p].skins.shelf == "ShelfMint")
		check("apply: back to classic", Service.Apply(p, "Shelf", "") == true and store[p].skins.shelf == "")
		check("apply: a shelf skin on the cashier refused", select(2, Service.Apply(p, "Cashier", "ShelfMint")) == "wrongKind")
		check("apply: classic cashier is saved", Service.Apply(p, "Cashier", "") == true and store[p].skins.cashier == "")

		-- drawing, on a copy of one plot owned by the fake player's data
		local plotCopy = workspace.Plots:FindFirstChildWhichIsA("Model"):Clone()
		plotCopy.Name = "SkinCheckPlot"
		plotCopy:SetAttribute("OwnerUserId", nil)
		plotCopy.Parent = workspace
		local pedestal = plotCopy.ExhibitSlots.Exhibit1
		local beforeColor, beforeMaterial = pedestal.Color, pedestal.Material
		Service.DrawPlot(plotCopy) -- unowned: classic
		check("draw: an unowned shop keeps the classic look", pedestal.Color == beforeColor and pedestal:GetAttribute("Skin") == nil)
		local topBefore = pedestal.Position.Y + pedestal.Size.Y / 2
		Service.DrawPiece(plotCopy, pedestal, "PedestalWalnut") -- a skin with a trim
		local trims = plotCopy:FindFirstChild("SkinTrims")
		local rim = trims and trims:FindFirstChild("Exhibit1_Top")
		check("draw: the skin colour and material are used", pedestal.Color == Skins.BY_ID.PedestalWalnut.look.color and pedestal.Material == Skins.BY_ID.PedestalWalnut.look.material)
		check("draw: a trimmed skin adds a rim that follows the piece in edit mode (Piece)", rim ~= nil and rim:GetAttribute("Piece") == "Exhibit1")
		check("draw: the top of the pedestal stays where items sit", math.abs(pedestal.Position.Y + pedestal.Size.Y / 2 - topBefore) < 0.001
			and rim ~= nil and rim.Position.Y + rim.Size.Y / 2 <= topBefore + 0.001)
		Service.DrawPiece(plotCopy, pedestal, "")
		check("draw: classic puts the original look back and removes the trim", pedestal.Color == beforeColor and pedestal.Material == beforeMaterial
			and (trims == nil or trims:FindFirstChild("Exhibit1_Top") == nil))
		plotCopy:Destroy()
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[SkinCheck]", line)
		end
	end
	print(`[SkinCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return SkinCheck
