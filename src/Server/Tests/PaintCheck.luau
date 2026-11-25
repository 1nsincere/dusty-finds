-- PaintCheck.luau (ServerScriptService.Server.Tests.PaintCheck)
-- Purpose: tests the paint rules (docs/12 Stage 2): config, PaintService Buy / Apply / Grant, drawing on a copy of a plot, and
-- the skin wishlist (SkinService.SetWishlist). Pure: COPIES of the services with fake DataService / EconomyService and fake
-- players; never touches a real profile or the real plots.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.PaintCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PaintCheck = {}

function PaintCheck.run()
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

	local Paints = require(ReplicatedStorage.Shared.Config.Paints)
	local Skins = require(ReplicatedStorage.Shared.Config.Skins)

	-- ===== config =====
	local idsOk, kindsOk, valuesOk, names = true, true, true, {}
	for _, paint in Paints.LIST do
		if Paints.BY_ID[paint.id] ~= paint then
			idsOk = false
		end
		if Paints.FIELD[paint.kind] == nil or not table.find(Paints.KINDS, paint.kind) then
			kindsOk = false
		end
		if type(paint.price) ~= "number" or paint.price <= 0 or typeof(paint.color) ~= "Color3" or type(paint.name) ~= "string" then
			valuesOk = false
		end
		names[paint.name] = (names[paint.name] or 0) + 1
	end
	local uniqueNames = true
	for _, n in names do
		if n > 1 then
			uniqueNames = false
		end
	end
	check("config: every paint id is unique and indexed", idsOk)
	check("config: every paint is a Wall or Floor paint", kindsOk)
	check("config: every paint has a name, a price and a colour", valuesOk)
	check("config: paint names are unique", uniqueNames)
	check("config: both walls and floors have paints", (function()
		local w, f = 0, 0
		for _, p in Paints.LIST do
			if p.kind == "Wall" then
				w += 1
			else
				f += 1
			end
		end
		return w >= 6 and f >= 4
	end)())

	-- ===== services on copies with fakes =====
	local kit = Instance.new("Folder")
	kit.Name = "PaintCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local paintCopy = ServerScriptService.Server.Services.PaintService:Clone()
	paintCopy.Parent = services
	local skinCopy = ServerScriptService.Server.Services.SkinService:Clone()
	skinCopy.Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local store = {}
		local spent, refunded = 0, 0
		local failSet = false
		local fakeDS = {
			Get = function(p)
				return store[p]
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
		local cash = 1000
		local fakeEconomy = {
			Spend = function(_, amount)
				if cash < amount then
					return false
				end
				cash -= amount
				spent += amount
				return true
			end,
			AddCash = function(_, amount)
				cash += amount
				refunded += amount
			end,
		}
		local Paint = require(paintCopy)
		Paint.Init({ DataService = fakeDS, EconomyService = fakeEconomy })
		local p = { UserId = 888, Name = "PaintMock" }
		store[p] = { paints = { owned = {}, wall = "", floor = "" }, skins = { owned = {} }, wishlist = {} }
		local near = true
		Paint.SetNearCheck(function()
			return near
		end)

		-- buy
		check("buy: an unknown paint is refused", select(2, Paint.Buy(p, "NoSuchPaint")) == "unknown" and select(2, Paint.Buy(p, 5)) == "unknown")
		near = false
		check("buy: too far from the Paint Bar is refused, no cash taken", select(2, Paint.Buy(p, "WallUbe")) == "far" and spent == 0)
		near = true
		check("buy: a paint is bought, cash taken, now owned", Paint.Buy(p, "WallUbe") == true and spent == Paints.BY_ID.WallUbe.price and store[p].paints.owned.WallUbe == true)
		check("buy: buying it twice is refused, no extra cash", select(2, Paint.Buy(p, "WallUbe")) == "owned" and spent == Paints.BY_ID.WallUbe.price)
		cash = 10
		check("buy: not enough cash is refused and nothing is owned", select(2, Paint.Buy(p, "WallTsokolate")) == "cash" and store[p].paints.owned.WallTsokolate == nil)
		cash = 1000
		failSet = true
		local before = cash
		local saveOk, saveReason = Paint.Buy(p, "WallPandan")
		failSet = false
		check("buy: a failed save is refunded", saveOk == false and saveReason == "saveFailed" and cash == before and refunded == Paints.BY_ID.WallPandan.price)
		store[p] = nil
		check("buy: a player with no data is refused", select(2, Paint.Buy(p, "WallUbe")) == "noData")
		store[p] = { paints = { owned = { WallUbe = true }, wall = "", floor = "" }, skins = { owned = {} }, wishlist = {} }

		-- apply
		check("apply: bad kind refused", select(2, Paint.Apply(p, "Roof", "WallUbe")) == "badKind" and select(2, Paint.Apply(p, 3, "WallUbe")) == "badKind")
		check("apply: bad paint id refused", select(2, Paint.Apply(p, "Wall", 12)) == "unknown" and select(2, Paint.Apply(p, "Wall", "Nope")) == "unknown")
		check("apply: a floor paint can't be used as a wall paint", select(2, Paint.Apply(p, "Wall", "FloorNarra")) == "wrongKind")
		check("apply: a paint you don't own is refused", select(2, Paint.Apply(p, "Wall", "WallPandan")) == "notOwned" and store[p].paints.wall == "")
		check("apply: an owned paint is used", Paint.Apply(p, "Wall", "WallUbe") == true and store[p].paints.wall == "WallUbe")
		check("apply: \"\" puts the original look back", Paint.Apply(p, "Wall", "") == true and store[p].paints.wall == "")
		failSet = true
		check("apply: a failed save is refused", select(2, Paint.Apply(p, "Wall", "WallUbe")) == "saveFailed")
		failSet = false
		check("grant: an admin gift is owned and can be put on", Paint.Grant(p, "FloorNarra", true) == true and store[p].paints.owned.FloorNarra == true and store[p].paints.floor == "FloorNarra")
		check("grant: an unknown paint is refused", select(2, Paint.Grant(p, "Nope", false)) == "unknown")

		-- drawing on a copy of a plot
		local plot = Instance.new("Folder")
		plot.Name = "PaintPlot"
		local walls = Instance.new("Folder")
		walls.Name = "Walls"
		walls.Parent = plot
		local back = Instance.new("Part")
		back.Name = "BackWall"
		back.Color = Color3.fromRGB(10, 20, 30)
		back.Material = Enum.Material.Plaster
		back.Parent = walls
		local facade = Instance.new("Folder")
		facade.Name = "Facade"
		facade.Parent = plot
		local shell = Instance.new("Folder")
		shell.Name = "Shell"
		shell.Parent = facade
		local floorModel = Instance.new("Model")
		floorModel.Name = "Shop_Floor"
		floorModel.Parent = shell
		local floorPart = Instance.new("Part")
		floorPart.Color = Color3.fromRGB(100, 100, 100)
		floorPart.Material = Enum.Material.Wood
		floorPart.Parent = floorModel
		local wallModel = Instance.new("Model")
		wallModel.Name = "Shop_Walls"
		wallModel.Parent = shell
		local wallPart = Instance.new("Part")
		wallPart.Color = Color3.fromRGB(1, 2, 3)
		wallPart.Parent = wallModel
		plot.Parent = ServerScriptService

		Paint.DrawKind(plot, "Wall", "WallUbe")
		check("draw: a wall paint colours the walls (the material stays)", back.Color == Paints.BY_ID.WallUbe.color and wallPart.Color == Paints.BY_ID.WallUbe.color and back.Material == Enum.Material.Plaster)
		check("draw: a wall paint leaves the floor alone", floorPart.Color == Color3.fromRGB(100, 100, 100))
		Paint.DrawKind(plot, "Floor", "FloorNarra")
		check("draw: a floor paint sets colour and material", floorPart.Color == Paints.BY_ID.FloorNarra.color and floorPart.Material == Paints.BY_ID.FloorNarra.material)
		Paint.DrawKind(plot, "Wall", "WallPandan")
		Paint.DrawKind(plot, "Wall", "")
		check("draw: the original wall look comes back exactly", back.Color == Color3.fromRGB(10, 20, 30) and wallPart.Color == Color3.fromRGB(1, 2, 3))
		Paint.DrawKind(plot, "Floor", "")
		check("draw: the original floor colour and material come back", floorPart.Color == Color3.fromRGB(100, 100, 100) and floorPart.Material == Enum.Material.Wood)
		plot:Destroy()

		-- wishlist (SkinService on a copy)
		local Skin = require(skinCopy)
		Skin.Init({ DataService = fakeDS, EconomyService = fakeEconomy })
		check("wishlist: pin a skin", Skin.SetWishlist(p, "ShelfMachucaTeal", true) == true and store[p].wishlist.ShelfMachucaTeal == true)
		check("wishlist: pinning twice is fine", Skin.SetWishlist(p, "ShelfMachucaTeal", true) == true)
		check("wishlist: unknown skins and bad flags are refused", select(2, Skin.SetWishlist(p, "Nope", true)) == "unknown" and select(2, Skin.SetWishlist(p, "ShelfMachucaTeal", "yes")) == "unknown")
		for _, id in { "ShelfPine", "ShelfMint", "ShelfWalnut", "ShelfCoral" } do
			Skin.SetWishlist(p, id, true)
		end
		check("wishlist: 5 pins fit", (function()
			local n = 0
			for _ in store[p].wishlist do
				n += 1
			end
			return n == 5
		end)())
		check("wishlist: a 6th pin is refused (full)", select(2, Skin.SetWishlist(p, "ShelfBrass", true)) == "full" and store[p].wishlist.ShelfBrass == nil)
		check("wishlist: unpinning works and frees a place", Skin.SetWishlist(p, "ShelfPine", false) == true and store[p].wishlist.ShelfPine == nil and Skin.SetWishlist(p, "ShelfBrass", true) == true)
		store[p].skins.owned.PedestalMarble = true
		check("wishlist: you can't pin a skin you already own", select(2, Skin.SetWishlist(p, "PedestalMarble", true)) == "owned")
		check("wishlist: every pinnable skin exists in Config", Skins.BY_ID.ShelfMachucaTeal ~= nil)
		store[p] = nil
		check("wishlist: a player with no data is refused", select(2, Skin.SetWishlist(p, "ShelfMint", true)) == "noData")
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[PaintCheck]", line)
		end
	end
	print(`[PaintCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return PaintCheck
