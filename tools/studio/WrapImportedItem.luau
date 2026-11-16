-- WrapImportedItem.luau: turns a Blender model you just imported (Studio: Home > Import 3D) into a finished restore item.
-- HOW TO USE (Studio, EDIT mode, not Play): 1) import the .glb: a Model named "Scene" appears in Workspace.
-- 2) edit the CONFIG block below for your item. 3) paste this whole file into the Command Bar (View > Command Bar) and press Enter.
-- 4) the finished model replaces ReplicatedStorage.Assets.Items.<ITEM_ID>; the "Scene" is deleted. 5) File > Save, then test it:
--    Play, open Inventory, pick the item, Restore.
-- Rules it follows (docs/Item_Model_Contract_DRAFT.md + docs/Blender_Pipeline.md): a Base plate is the PrimaryPart; dirt/rust spots sit ON the
-- outside surface (found by raycasting down), 0.6 studs, face Top, CanQuery; polish surfaces are in a PolishSurfaces folder; names are exact.
-- Owner: Dev 1 (Ace). Studio-only tool, never runs in the game.

local CONFIG = {
	ITEM_ID = "Teacup", -- exact Config item id (see src/Shared/Config/Items.luau)
	ROTATE_Y_DEGREES = -90, -- turn the model so its good side (handle, front) faces the bench camera; the camera sits on the +X side
	BASE_SIZE = Vector3.new(2.1, 0.12, 2.1), -- the plate it stands on
	SCALE = 1, -- uniform scale after import (1 = as modelled, 1 stud = 1 Blender unit)
	-- colour per part name (the object names you used in Blender): { hex, reflectance }
	COLORS = {
		Body = { "F4F0E8", 0.15 }, Saucer = { "F4F0E8", 0.15 }, Handle = { "F4F0E8", 0.15 },
		Rim = { "E3B23C", 0.25 }, Trim = { "E3B23C", 0.25 }, Flower = { "D2694A", 0 }, Leaf = { "7FA37C", 0 },
	},
	POLISH_PARTS = { "Body", "Saucer", "Handle" }, -- parts the Polish step rubs; they go into the PolishSurfaces folder
	-- dirt spots (Wipe) and rust spots (Scrape): {x, z} offsets from the item centre AFTER rotation; the height is raycast onto the surface
	DIRT_SPOTS = { { 0.45, -0.54 }, { 0.70, 0 }, { 0.45, 0.54 } },
	RUST_SPOTS = {},
	-- Reassemble / Replace: { name = "Lens1", socket = Vector3, tray = Vector3 }; leave empty if the recipe has none
	SOCKETS = {},
	DECOYS = false, -- true for Replace: adds two wrong parts to the tray
	TEST_POINT = nil, -- Vector3 above the item for Test steps, or nil
}

local H = Color3.fromHex
local items = game.ReplicatedStorage.Assets.Items
local TEX = "rbxasset://textures/SpawnLocation.png" -- the decal texture known to render

local scene = workspace:FindFirstChild("Scene")
assert(scene, 'Import the .glb first: a Model named "Scene" must be in Workspace')

-- 1) collect the mesh parts (the importer puts each Blender object in its own sub-model)
local src = {}
for _, m in scene:GetChildren() do
	local mp = if m:IsA("MeshPart") then m else m:FindFirstChildWhichIsA("MeshPart", true)
	if mp then
		src[m.Name] = mp
	end
end
assert(next(src), "no MeshParts found inside Scene")

-- 2) put the lowest point on the base plate and the centre of the first part over the origin
local anchor = src[CONFIG.POLISH_PARTS[1]] or select(2, next(src))
local minY = math.huge
for _, p in src do
	minY = math.min(minY, p.Position.Y - p.Size.Y / 2)
end
local BASE_TOP = CONFIG.BASE_SIZE.Y
local R = CFrame.Angles(0, math.rad(CONFIG.ROTATE_Y_DEGREES), 0)
local shift = Vector3.new(-anchor.Position.X, BASE_TOP - minY, -anchor.Position.Z)

local model = Instance.new("Model")
model.Name = CONFIG.ITEM_ID
local function newPart(name, size, cf, color)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored, p.CanCollide = true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return p
end
local base = newPart("Base", CONFIG.BASE_SIZE, CFrame.new(0, BASE_TOP / 2, 0), H("9AA0A6"))
base.Material = Enum.Material.SmoothPlastic
base.Parent = model
model.PrimaryPart = base

local polish = Instance.new("Folder")
polish.Name = "PolishSurfaces"
local polishSet = {}
for _, n in CONFIG.POLISH_PARTS do
	polishSet[n] = true
end
for name, mp in src do
	local c = mp:Clone()
	c.Name, c.Anchored, c.CanCollide, c.CanQuery = name, true, false, true
	c.CFrame = (CFrame.new(0, 0, 0) * R) * (CFrame.new(shift) * mp.CFrame)
	if CONFIG.SCALE ~= 1 then
		c.Size *= CONFIG.SCALE
		c.Position *= CONFIG.SCALE
	end
	local col = CONFIG.COLORS[name]
	if col then
		c.Color = H(col[1])
		c.Reflectance = col[2]
	end
	c.Material = Enum.Material.SmoothPlastic
	c.Parent = if polishSet[name] then polish else model
end
if #polish:GetChildren() > 0 then
	polish.Parent = model
end

-- 3) raycast to find the real surface height under each spot, so nothing is hidden inside the mesh
local function surfaceY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	model.Parent = workspace
	local hit = workspace:Raycast(Vector3.new(x, 20, z), Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y or BASE_TOP
end
local function spots(folderName, decalName, colorHex, list, layers)
	if #list == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = model
	for i, xz in list do
		local y = surfaceY(xz[1], xz[2]) + 0.012
		local s = newPart(folderName:sub(1, -6) .. i, Vector3.new(0.6, 0.02, 0.6), CFrame.new(xz[1], y, xz[2]), H("FFFFFF"))
		s.Transparency, s.CanQuery = 1, true
		local d = Instance.new("Decal")
		d.Name, d.Face, d.Texture, d.Color3 = decalName, Enum.NormalId.Top, TEX, H(colorHex)
		d.Parent = s
		if layers then
			local v = Instance.new("NumberValue")
			v.Name, v.Value = "Layers", layers
			v.Parent = s
		end
		s.Parent = folder
	end
end
spots("DirtSpots", "Dirt", "58361C", CONFIG.DIRT_SPOTS)
spots("RustSpots", "Rust", "BE6428", CONFIG.RUST_SPOTS, 3)

if #CONFIG.SOCKETS > 0 then
	local sockets, loose = Instance.new("Folder"), Instance.new("Folder")
	sockets.Name, loose.Name = "Sockets", "LooseParts"
	sockets.Parent, loose.Parent = model, model
	for _, sk in CONFIG.SOCKETS do
		local s = newPart(sk.name, Vector3.new(0.4, 0.4, 0.4), CFrame.new(sk.socket), H("FFFF00"))
		s.Material, s.Transparency, s.CanQuery, s.Parent = Enum.Material.Neon, 0.55, true, sockets
		local l = newPart(sk.name, Vector3.new(0.4, 0.4, 0.4), CFrame.new(sk.tray), H("D2694A"))
		l.CanQuery, l.Parent = true, loose
	end
	if CONFIG.DECOYS then
		for i, x in { -1.4, 1.4 } do
			local d = newPart(i == 1 and "DecoyA" or "DecoyB", Vector3.new(0.4, 0.5, 0.4), CFrame.new(x, 0.3, -1.4), H(i == 1 and "2E4A7D" or "7FA37C"))
			d.CanQuery, d.Parent = true, loose
		end
	end
end
if CONFIG.TEST_POINT then
	local t = newPart("TestPoint", Vector3.new(0.3, 0.3, 0.3), CFrame.new(CONFIG.TEST_POINT), H("FFFFFF"))
	t.Transparency, t.Parent = 1, model
end

-- 4) swap it in and clean up
local old = items:FindFirstChild(CONFIG.ITEM_ID)
if old then
	old:Destroy()
end
model:SetAttribute("Hand", true) -- a real Blender model, not a placeholder block
model:PivotTo(CFrame.new(0, 0, 0))
model.Parent = items
scene:Destroy()
print(`[WrapImportedItem] {CONFIG.ITEM_ID} done: {#model:GetDescendants()} instances. Save the place, then Play and test Restore.`)
