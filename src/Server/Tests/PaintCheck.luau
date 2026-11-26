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
	check("config: walls, floors, trim and accent all have paints", (function()
		local n = { Wall = 0, Floor = 0, Trim = 0, Accent = 0 }
		for _, p in Paints.LIST do
			n[p.kind] += 1
		end
		return n.Wall >= 6 and n.Floor >= 4 and n.Trim >= 6 and n.Accent >= 6
	end)())
	check("config: every kind has a default look, a save field and a label", (function()
		for _, kind in Paints.KINDS do
			if Paints.DEFAULTS[kind] == nil or Paints.FIELD[kind] == nil or Paints.KIND_LABEL[kind] == nil then
				return false
			end
		end
		return true
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
		store[p] = { paints = { owned = {}, wall = "", floor = "", trim = "", accent = "" }, skins = { owned = {} }, wishlist = {} }
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
		store[p] = { paints = { owned = { WallUbe = true }, wall = "", floor = "", trim = "", accent = "" }, skins = { owned = {} }, wishlist = {} }

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
		check("trim/accent: a trim paint can be granted and used, but not as an accent", Paint.Grant(p, "TrimNarra", true) == true and store[p].paints.trim == "TrimNarra" and select(2, Paint.Apply(p, "Accent", "TrimNarra")) == "wrongKind")
		check("trim/accent: an accent paint can be used and put back", Paint.Grant(p, "AccentTeal", true) == true and store[p].paints.accent == "AccentTeal" and Paint.Apply(p, "Accent", "") == true and store[p].paints.accent == "")
		cash = 1000
		check("trim/accent: they can be bought like any paint", Paint.Buy(p, "AccentBrick") == true and store[p].paints.owned.AccentBrick == true and select(2, Paint.Buy(p, "TrimKamagong")) ~= "unknown")

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
		local wallPart = Instance.new("MeshPart") -- SurfaceAppearance can only be parented to a MeshPart
		wallPart.Color = Color3.fromRGB(1, 2, 3)
		wallPart.Parent = wallModel
		-- a textured wall mesh: its visible colour is SurfaceAppearance.Color, the part's own Color does nothing you can see
		local wallSA = Instance.new("SurfaceAppearance")
		wallSA.Color = Color3.fromRGB(236, 246, 238)
		wallSA.Parent = wallPart
		-- the second storey's wall mesh, a bought Back Room and a bought Showroom (second floor)
		local upperFolder = Instance.new("Folder")
		upperFolder.Name = "Upper"
		upperFolder.Parent = facade
		local upWallsModel = Instance.new("Model")
		upWallsModel.Name = "Shop_UpWalls"
		upWallsModel.Parent = upperFolder
		local upWalls = Instance.new("MeshPart")
		upWalls.Color = Color3.fromRGB(5, 5, 5)
		upWalls.Parent = upWallsModel
		local upSA = Instance.new("SurfaceAppearance")
		upSA.Color = Color3.fromRGB(240, 240, 240)
		upSA.Parent = upWalls
		local backRoom = Instance.new("Model")
		backRoom.Name = "Expansion_BackRoom"
		backRoom.Parent = plot
		local backShell = Instance.new("Folder")
		backShell.Name = "Shell"
		backShell.Parent = backRoom
		local function shellPart(name: string, color: Color3, material: Enum.Material): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Color = color
			p.Material = material
			p.Parent = backShell
			return p
		end
		local backFloor = shellPart("Floor", Color3.fromRGB(7, 7, 7), Enum.Material.WoodPlanks)
		local backWall = shellPart("BackWall", Color3.fromRGB(8, 8, 8), Enum.Material.Plaster)
		local backOuter = shellPart("OuterWall", Color3.fromRGB(9, 9, 9), Enum.Material.Plaster)
		local backCornice = shellPart("CorniceBack", Color3.fromRGB(11, 11, 11), Enum.Material.WoodPlanks) -- trim: never painted
		local showroom = Instance.new("Model")
		showroom.Name = "Expansion_Showroom"
		showroom.Parent = plot
		local upperFloorFolder = Instance.new("Folder")
		upperFloorFolder.Name = "UpperFloor"
		upperFloorFolder.Parent = showroom
		local showFloor = Instance.new("Part")
		showFloor.Name = "FloorMain"
		showFloor.Color = Color3.fromRGB(12, 12, 12)
		showFloor.Material = Enum.Material.WoodPlanks
		showFloor.Parent = upperFloorFolder
		local showRail = Instance.new("Part")
		showRail.Name = "RailSide"
		showRail.Color = Color3.fromRGB(13, 13, 13)
		showRail.Parent = upperFloorFolder
		-- the main floor: a textured overlay mesh on top of the plank slab (Plot.Floor)
		local overlay = Instance.new("MeshPart")
		overlay.Name = "Overlay"
		overlay.Parent = floorModel
		local overlaySA = Instance.new("SurfaceAppearance")
		overlaySA.Parent = overlay
		local slab = Instance.new("Part")
		slab.Name = "Floor"
		slab.Color = Color3.fromRGB(20, 20, 20)
		slab.Material = Enum.Material.Wood
		slab.Parent = plot
		plot.Parent = ServerScriptService

		Paint.DrawKind(plot, "Wall", "WallUbe")
		check("expansions: a wall paint also covers the second storey's wall mesh and the Back Room walls (not its trim)", upSA.Color == Paints.BY_ID.WallUbe.color and backWall.Color == Paints.BY_ID.WallUbe.color
			and backOuter.Color == Paints.BY_ID.WallUbe.color and backCornice.Color == Color3.fromRGB(11, 11, 11))
		Paint.DrawKind(plot, "Floor", "FloorNarra")
		check("expansions: a floor paint also covers the Back Room floor and the Showroom's second floor (not its rails)", backFloor.Color == Paints.BY_ID.FloorNarra.color and showFloor.Color == Paints.BY_ID.FloorNarra.color
			and showFloor.Material == Paints.BY_ID.FloorNarra.material and showRail.Color == Color3.fromRGB(13, 13, 13))
		check("one floor: the main floor texture is hidden and the slab gets the SAME colour and material as the bought rooms' floors", overlay.Transparency == 1
			and slab.Color == showFloor.Color and slab.Material == showFloor.Material and slab.Color == backFloor.Color and slab.Material == backFloor.Material)
		Paint.DrawKind(plot, "Wall", "")
		Paint.DrawKind(plot, "Floor", "")
		check("one floor: with no floor paint the main floor texture shows again and the slab is as it was", overlay.Transparency == 0 and overlaySA.Color == Color3.fromRGB(255, 255, 255)
			and slab.Color == Color3.fromRGB(20, 20, 20) and slab.Material == Enum.Material.Wood)
		Paint.DrawDefault(plot, "Floor")
		Paint.DrawDefault(plot, "Wall")
		local dFloor, dWall = Paints.DEFAULTS.Floor, Paints.DEFAULTS.Wall
		check("default: with no paint every floor (main slab, Back Room, Showroom) has the SAME default colour and material, the main texture is hidden",
			slab.Color == dFloor.color and slab.Material == dFloor.material and backFloor.Color == dFloor.color and backFloor.Material == dFloor.material
			and showFloor.Color == dFloor.color and showFloor.Material == dFloor.material and overlay.Transparency == 1)
		check("default: with no paint every wall (main walls, second storey, Back Room) has the SAME default colour",
			wallSA.Color == dWall.color and upSA.Color == dWall.color and backWall.Color == dWall.color and backOuter.Color == dWall.color and back.Color == dWall.color)
		check("default: trim, rails and decor are not touched", backCornice.Color == Color3.fromRGB(11, 11, 11) and showRail.Color == Color3.fromRGB(13, 13, 13))
		Paint.DrawKind(plot, "Wall", "WallUbe")
		check("default: a chosen paint still overrides the default in every room", backWall.Color == Paints.BY_ID.WallUbe.color and upSA.Color == Paints.BY_ID.WallUbe.color)
		Paint.DrawKind(plot, "Wall", "")
		Paint.DrawKind(plot, "Floor", "")
		check("expansions: the original look comes back in the extra rooms too", upSA.Color == Color3.fromRGB(240, 240, 240) and backWall.Color == Color3.fromRGB(8, 8, 8)
			and backFloor.Color == Color3.fromRGB(7, 7, 7) and showFloor.Color == Color3.fromRGB(12, 12, 12) and showFloor.Material == Enum.Material.WoodPlanks)

		Paint.DrawKind(plot, "Wall", "WallUbe")
		check("draw: a wall paint colours the walls (the material stays); a textured wall is tinted, its own Color untouched", back.Color == Paints.BY_ID.WallUbe.color and wallSA.Color == Paints.BY_ID.WallUbe.color and wallPart.Color == Color3.fromRGB(1, 2, 3) and back.Material == Enum.Material.Plaster)
		check("draw: a wall paint leaves the floor alone", floorPart.Color == Color3.fromRGB(100, 100, 100))
		Paint.DrawKind(plot, "Floor", "FloorNarra")
		check("draw: a floor paint sets colour and material", floorPart.Color == Paints.BY_ID.FloorNarra.color and floorPart.Material == Paints.BY_ID.FloorNarra.material)
		Paint.DrawKind(plot, "Wall", "WallPandan")
		Paint.DrawKind(plot, "Wall", "")
		check("draw: the original wall look comes back exactly (also the texture tint)", back.Color == Color3.fromRGB(10, 20, 30) and wallPart.Color == Color3.fromRGB(1, 2, 3) and wallSA.Color == Color3.fromRGB(236, 246, 238))
		Paint.DrawKind(plot, "Floor", "")
		check("draw: the original floor colour and material come back", floorPart.Color == Color3.fromRGB(100, 100, 100) and floorPart.Material == Enum.Material.Wood)

		-- trim and accent (2026-11-26): the universal shell's Trim / Accent meshes, the rear cap, the Back Room's and the decor's accent
		local function model(parent: Instance, name: string, color: Color3): Part
			local m = Instance.new("Model")
			m.Name = name
			m.Parent = parent
			local part = Instance.new("Part")
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic
			part.Parent = m
			return part
		end
		local upper = plot:FindFirstChild("Facade"):FindFirstChild("Upper")
		local decorFolder = Instance.new("Folder")
		decorFolder.Name = "Decor"
		decorFolder.Parent = plot.Facade
		local backRoomShell = plot:FindFirstChild("Expansion_BackRoom")
		local trimGround = model(plot.Facade.Shell, "Shop_Trim", Color3.fromRGB(31, 31, 31))
		local trimUpper = model(upper, "Shop_UpTrim", Color3.fromRGB(32, 32, 32))
		local trimCap = model(upper, "Shop_BackCapTrim", Color3.fromRGB(33, 33, 33))
		local trimBack = model(backRoomShell, "BackRoom_Trim", Color3.fromRGB(34, 34, 34))
		local accentGround = model(plot.Facade.Shell, "Shop_Accent", Color3.fromRGB(41, 41, 41))
		local accentUpper = model(upper, "Shop_UpAccent", Color3.fromRGB(42, 42, 42))
		local accentDecor = model(decorFolder, "Shop_Accent", Color3.fromRGB(43, 43, 43))
		local accentBack = model(backRoomShell, "BackRoom_UpAccent", Color3.fromRGB(44, 44, 44))
		Paint.DrawKind(plot, "Trim", "TrimNarra")
		local narra = Paints.BY_ID.TrimNarra.color
		check("trim: a trim paint colours the ground, second-storey, rear-cap and Back Room trim", trimGround.Color == narra and trimUpper.Color == narra and trimCap.Color == narra and trimBack.Color == narra)
		check("trim: a trim paint leaves accents, walls and floors alone", accentGround.Color == Color3.fromRGB(41, 41, 41) and accentBack.Color == Color3.fromRGB(44, 44, 44) and back.Color == Color3.fromRGB(10, 20, 30))
		Paint.DrawKind(plot, "Accent", "AccentTeal")
		local teal = Paints.BY_ID.AccentTeal.color
		check("accent: an accent paint colours the shell, second-storey, decor and Back Room accents", accentGround.Color == teal and accentUpper.Color == teal and accentDecor.Color == teal and accentBack.Color == teal)
		check("accent: an accent paint leaves the trim alone", trimGround.Color == narra)
		Paint.DrawKind(plot, "Trim", "")
		Paint.DrawKind(plot, "Accent", "")
		check("trim/accent: the original look comes back exactly", trimGround.Color == Color3.fromRGB(31, 31, 31) and trimBack.Color == Color3.fromRGB(34, 34, 34) and accentGround.Color == Color3.fromRGB(41, 41, 41) and accentDecor.Color == Color3.fromRGB(43, 43, 43))
		Paint.DrawDefault(plot, "Trim")
		Paint.DrawDefault(plot, "Accent")
		check("trim/accent: with no paint every trim and every accent gets the same default colour", trimGround.Color == Paints.DEFAULTS.Trim.color and trimUpper.Color == Paints.DEFAULTS.Trim.color and trimBack.Color == Paints.DEFAULTS.Trim.color
			and accentGround.Color == Paints.DEFAULTS.Accent.color and accentUpper.Color == Paints.DEFAULTS.Accent.color and accentBack.Color == Paints.DEFAULTS.Accent.color)
		-- premium finishes (2026-11-26): a premium paint puts a ready-made texture on a textured shell part and takes it off again.
		-- (Game scripts can't read or write a SurfaceAppearance's maps, so the textures are cloned from ReplicatedStorage.ShellTextures.)
		local shellTex = ReplicatedStorage:FindFirstChild("ShellTextures")
		check("premium: ReplicatedStorage.ShellTextures has every finish and the three originals", (function()
			if shellTex == nil then
				return false
			end
			for _, key in { "plaster", "woodgrain", "shingle", "pearl", "velvet", "brass", "goldleaf", "marblewall" } do
				local holder = shellTex:FindFirstChild(key)
				if holder == nil or holder:FindFirstChildWhichIsA("SurfaceAppearance") == nil then
					return false
				end
			end
			return true
		end)())
		wallPart.Name = "Shop_Walls_mesh" -- the real name decides which original texture the part wears (plaster)
		local function wallTexture(): SurfaceAppearance?
			return wallPart:FindFirstChildWhichIsA("SurfaceAppearance")
		end
		Paint.DrawKind(plot, "Wall", "WallPremPearl")
		check("premium: a finish paint tints the wall and puts the finish texture on it", wallTexture() ~= nil and wallTexture().Color == Paints.BY_ID.WallPremPearl.color and wallPart:GetAttribute("ShellTex") == "pearl")
		Paint.DrawKind(plot, "Wall", "WallUbe")
		check("premium: a plain paint puts the original texture back, with its own tint", wallPart:GetAttribute("ShellTex") == nil and wallTexture() ~= nil and wallTexture().Color == Paints.BY_ID.WallUbe.color)
		Paint.DrawKind(plot, "Wall", "WallPremVelvet")
		Paint.DrawKind(plot, "Wall", "WallPremMarble")
		check("premium: finish to finish changes the texture each time and leaves exactly one SurfaceAppearance", wallPart:GetAttribute("ShellTex") == "marblewall" and #wallPart:GetChildren() == 1)
		Paint.DrawKind(plot, "Wall", "")
		check("premium: the original look brings back the original texture", wallPart:GetAttribute("ShellTex") == nil and wallTexture() ~= nil and #wallPart:GetChildren() == 1)
		check("premium: a part that is not a textured shell part is only tinted (the floor overlay keeps its texture)", (function()
			Paint.DrawKind(plot, "Floor", "FloorPremMarble")
			return overlay:GetAttribute("ShellTex") == nil
		end)())
		Paint.DrawKind(plot, "Floor", "FloorPremMarble")
		check("premium: a premium floor sets its colour and its material (Marble)", slab.Material == Enum.Material.Marble and slab.Color == Paints.BY_ID.FloorPremMarble.color)
		Paint.DrawKind(plot, "Floor", "")
		plot:Destroy()

		-- premium buying and earning
		store[p] = { paints = { owned = {}, wall = "", floor = "", trim = "", accent = "" }, skins = { owned = {} }, wishlist = {} }
		cash = 100000
		near = true
		check("premium: a premium paint can't be bought with cash", select(2, Paint.Buy(p, "WallPremPearl")) == "robuxOnly" and store[p].paints.owned.WallPremPearl == nil)
		check("premium: a premium paint can't be used before it is owned", select(2, Paint.Apply(p, "Wall", "WallPremPearl")) == "notOwned")
		check("premium: below the earn tier nothing is given", #Paint.GrantEarned(p, 3) == 0 and store[p].paints.owned.TrimPremGold == nil)
		local gotGold = Paint.GrantEarned(p, 4)
		check("premium: reaching the Gilded tier (4) gives the gold-leaf trim for free, once", #gotGold == 1 and gotGold[1] == "TrimPremGold" and store[p].paints.owned.TrimPremGold == true and store[p].paints.owned.WallPremMarble == nil and #Paint.GrantEarned(p, 4) == 0)
		check("premium: reaching the Radiant tier (5) gives the marble wall", #Paint.GrantEarned(p, 5) == 1 and store[p].paints.owned.WallPremMarble == true)
		check("premium: an earned paint can be used", Paint.Apply(p, "Trim", "TrimPremGold") == true and store[p].paints.trim == "TrimPremGold")
		check("premium: no data = nothing given", (function()
			local nobody = { UserId = 777, Name = "NoData2" }
			return #Paint.GrantEarned(nobody, 5) == 0
		end)())

		-- ===== themes (one-tap looks) and the trim contrast guard =====
		local Themes = require(ReplicatedStorage.Shared.Config.Themes)
		local Contrast = require(ReplicatedStorage.Shared.Contrast)
		local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
		check("themes: every look uses real paints of the right kind", (function()
			for _, theme in Themes.LIST do
				for _, slot in Themes.SLOTS do
					local id = theme.looks[slot]
					if id ~= "" then
						local paint = Paints.BY_ID[id]
						if paint == nil or paint.kind ~= slot then
							return false
						end
					end
				end
			end
			return true
		end)())
		check("themes: a pass theme's paints are given by that pass, a cash or free theme's paints are not pass-only", (function()
			for _, theme in Themes.LIST do
				local pass = if theme.pass then Monetization.BY_PASS[theme.pass] else nil
				for _, id in Themes.paintIds(theme) do
					local paint = Paints.BY_ID[id]
					if theme.tier == "pass" then
						if pass == nil or paint.pass ~= theme.pass or not table.find(pass.grants.paints, id) then
							return false
						end
					elseif paint.pass ~= nil then
						return false
					end
				end
			end
			return true
		end)())
		check("themes: ids are unique and indexed", (function()
			local n = 0
			for _, theme in Themes.LIST do
				n += 1
				if Themes.BY_ID[theme.id] ~= theme then
					return false
				end
			end
			return n >= 8
		end)())

		local ube = Themes.BY_ID.UbeHalaya
		local ubeSum = Paints.BY_ID.WallUbe.price + Paints.BY_ID.FloorPine.price + Paints.BY_ID.TrimSampaguita.price + Paints.BY_ID.AccentUbe.price
		check("themes: a cash theme costs 85% of its unowned paints, rounded up to $10", Themes.price(ube, {}) == math.ceil(ubeSum * 0.85 / 10) * 10 and Themes.price(ube, {}) < ubeSum)
		check("themes: owned pieces are not charged again", Themes.price(ube, { WallUbe = true, AccentUbe = true }) == math.ceil((ubeSum - Paints.BY_ID.WallUbe.price - Paints.BY_ID.AccentUbe.price) * 0.85 / 10) * 10 and Themes.price(ube, (function()
			local all = {}
			for _, id in Themes.paintIds(ube) do
				all[id] = true
			end
			return all
		end)()) == 0)
		check("themes: free and starter themes cost 0, a pass theme has no cash price", Themes.price(Themes.BY_ID.PandanLeaf, {}) == 0 and Themes.price(Themes.BY_ID.CapizCream, {}) == 0 and Themes.price(Themes.BY_ID.ParolPasko, {}) == nil)

		store[p] = { paints = { owned = {}, wall = "", floor = "", trim = "", accent = "" }, skins = { owned = {} }, wishlist = {} }
		cash, spent, refunded = 1000, 0, 0
		near = false
		check("theme buy: too far from the Paint Bar is refused, nothing taken", select(2, Paint.BuyTheme(p, "UbeHalaya")) == "far" and spent == 0)
		near = true
		check("theme buy: an unknown theme and a non-string are refused", select(2, Paint.BuyTheme(p, "Nope")) == "unknown" and select(2, Paint.BuyTheme(p, 7)) == "unknown")
		check("theme buy: a pass theme can't be bought with cash", select(2, Paint.BuyTheme(p, "ParolPasko")) == "passOnly" and spent == 0)
		local ubePrice = Themes.price(ube, {}) or 0
		check("theme buy: the whole look is bought, the SERVER's price is charged, all four paints are owned", (function()
			local okBuy, _, paid = Paint.BuyTheme(p, "UbeHalaya")
			return okBuy == true and paid == ubePrice and spent == ubePrice and Themes.ownsAll(ube, store[p].paints.owned)
		end)())
		check("theme buy: buying it again is refused, no extra cash", select(2, Paint.BuyTheme(p, "UbeHalaya")) == "owned" and spent == ubePrice)
		cash = 5
		check("theme buy: not enough cash is refused and nothing is owned", select(2, Paint.BuyTheme(p, "BarakoRoast")) == "cash" and store[p].paints.owned.WallTsokolate == nil)
		cash = 1000
		failSet = true
		local beforeCash = cash
		local failedOk, failedReason = Paint.BuyTheme(p, "SantanSunset")
		failSet = false
		check("theme buy: a failed save is refunded", failedOk == false and failedReason == "saveFailed" and cash == beforeCash)
		check("theme buy: a free theme costs nothing and gives its paints", (function()
			local before2 = spent
			local okFree, _, paid = Paint.BuyTheme(p, "PandanLeaf")
			return okFree == true and paid == 0 and spent == before2 and store[p].paints.owned.WallPandan == true and store[p].paints.owned.AccentHoney == true
		end)())
		check("theme buy: a player with no data is refused", (function()
			local other = { UserId = 889, Name = "NoData" }
			return select(2, Paint.BuyTheme(other, "UbeHalaya")) == "noData"
		end)())
		check("theme apply: a look you do not own is refused and nothing changes", select(2, Paint.ApplyTheme(p, "BarakoRoast")) == "notOwned" and store[p].paints.wall == "")
		check("theme apply: an owned look sets all four paints at once", Paint.ApplyTheme(p, "UbeHalaya") == true and store[p].paints.wall == "WallUbe" and store[p].paints.floor == "FloorPine"
			and store[p].paints.trim == "TrimSampaguita" and store[p].paints.accent == "AccentUbe" and Themes.isInUse(ube, store[p].paints))
		check("theme apply: the starter look puts the default back on every slot", Paint.ApplyTheme(p, "CapizCream") == true and store[p].paints.wall == "" and store[p].paints.floor == "" and store[p].paints.trim == "" and store[p].paints.accent == "")
		check("theme apply: an unknown theme is refused", select(2, Paint.ApplyTheme(p, "Nope")) == "unknown")

		-- the contrast guard
		local dark, light = Color3.fromRGB(54, 57, 64), Color3.fromRGB(234, 227, 213)
		local darkTrim = Color3.fromRGB(54, 51, 48)
		local fixedDark, changedDark = Contrast.fixTrim(dark, darkTrim)
		check("contrast: a dark trim on a dark wall is moved lighter, by at least the minimum gap", changedDark == true and Contrast.lightness(fixedDark) - Contrast.lightness(dark) >= Contrast.MIN_GAP - 0.01)
		local fixedLight, changedLight = Contrast.fixTrim(light, Color3.fromRGB(245, 241, 235))
		check("contrast: a light trim on a light wall is moved darker", changedLight == true and Contrast.lightness(light) - Contrast.lightness(fixedLight) >= Contrast.MIN_GAP - 0.01)
		local sameTrim, changedSame = Contrast.fixTrim(light, Color3.fromRGB(89, 62, 43))
		check("contrast: a trim that already stands out is left exactly as it is", changedSame == false and sameTrim == Color3.fromRGB(89, 62, 43))
		local h1 = Color3.fromRGB(143, 45, 43):ToHSV()
		local h2 = (Contrast.fixTrim(Color3.fromRGB(150, 50, 48), Color3.fromRGB(143, 45, 43))):ToHSV()
		check("contrast: the trim keeps its hue when it is adjusted", math.abs(h1 - h2) < 0.03)
		check("contrast: no wall and trim pair of any theme or paint ends up too close after the guard", (function()
			for _, w in Paints.LIST do
				if w.kind == "Wall" then
					for _, t in Paints.LIST do
						if t.kind == "Trim" then
							local shown = Contrast.fixTrim(w.color, t.color)
							if math.abs(Contrast.lightness(shown) - Contrast.lightness(w.color)) < Contrast.MIN_GAP - 0.01 then
								return false
							end
						end
					end
				end
			end
			return true
		end)())
		check("contrast: PaintService shows the adjusted trim, a plain accent and wall are untouched", (function()
			local wallPaint = { color = dark }
			local trimPaint = { color = darkTrim, material = Enum.Material.SmoothPlastic }
			local shownTrim = Paint.Effective("Trim", trimPaint, wallPaint)
			return shownTrim ~= trimPaint and shownTrim.color ~= darkTrim and shownTrim.material == Enum.Material.SmoothPlastic
				and Paint.Effective("Accent", trimPaint, wallPaint) == trimPaint and Paint.Effective("Wall", wallPaint, wallPaint) == wallPaint
		end)())

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
