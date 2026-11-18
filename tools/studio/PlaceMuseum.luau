-- PlaceMuseum.luau  (Studio Command Bar, Edit mode; run AFTER importing assets/models/Museum.glb with Home > Import 3D)
-- Purpose: turns the imported Blender museum (a Model "Scene" with one sub-model per colour group) into the plaza Museum:
-- colours/materials by object name, solid walls only, correct size/rotation, front facing the plaza (-X), and swaps out the old blocky museum.
-- Reversible: the old museum parts go to ServerStorage.OldLayoutArchive (parent them back to restore). The CollectionPedestal and its prompt are KEPT.
-- Owner: Dev 1. Not part of gameplay code.

local CENTER = Vector3.new(-8, 0.4, 205) -- world position of the building centre on the ground
local FACE = Vector3.new(-1, 0, 0) -- the front (portico) faces west, toward the plaza and the pedestal
local WANT_WIDTH = 72 -- Walls width in studs (tools/blender/museum.py)

local LOOK = {
	Walls = { Color3.fromRGB(239, 226, 196), Enum.Material.SmoothPlastic },
	Trim = { Color3.fromRGB(251, 247, 236), Enum.Material.Marble },
	Columns = { Color3.fromRGB(251, 247, 236), Enum.Material.Marble },
	Roof = { Color3.fromRGB(196, 88, 54), Enum.Material.Slate },
	Dome = { Color3.fromRGB(94, 158, 136), Enum.Material.Metal },
	Gold = { Color3.fromRGB(227, 178, 60), Enum.Material.Metal },
	Glass = { Color3.fromRGB(62, 106, 138), Enum.Material.Glass },
	Frames = { Color3.fromRGB(107, 74, 46), Enum.Material.Wood },
	Steps = { Color3.fromRGB(189, 180, 162), Enum.Material.Concrete },
	BannerPlum = { Color3.fromRGB(110, 74, 126), Enum.Material.Fabric },
	BannerTeal = { Color3.fromRGB(31, 122, 122), Enum.Material.Fabric },
	BannerGold = { Color3.fromRGB(227, 178, 60), Enum.Material.Fabric },
	Door = { Color3.fromRGB(216, 185, 138), Enum.Material.Wood },
	Urns = { Color3.fromRGB(251, 247, 236), Enum.Material.Marble },
}

local scene
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and child.Name == "Scene" and child:FindFirstChild("Walls", true) then scene = child end
end
assert(scene, "Import assets/models/Museum.glb first (Home > Import 3D); no Model 'Scene' with a 'Walls' part found")

local wow = workspace:FindFirstChild("CanalTownWow") or Instance.new("Folder", workspace)
local old = wow:FindFirstChild("MuseumBlender")
if old then old:Destroy() end
scene.Name = "MuseumBlender"
scene.Parent = wow

local function groupOf(part: BasePart): string?
	local node: Instance? = part
	while node and node ~= scene do
		if LOOK[node.Name] then return node.Name end
		node = node.Parent
	end
	return nil
end

for _, part in scene:GetDescendants() do
	if part:IsA("BasePart") then
		local g = groupOf(part)
		part.Anchored = true
		part.CanTouch = false
		part.CanQuery = false
		part.CanCollide = false
		part.CastShadow = true
		if g then
			part.Color = LOOK[g][1]
			part.Material = LOOK[g][2]
			if g == "Glass" then part.Reflectance = 0.2 end
			if g == "Walls" then
				part.CanCollide = true
				part.CollisionFidelity = Enum.CollisionFidelity.Box
				part.CanQuery = true
			end
		end
		if part:IsA("MeshPart") then part.DoubleSided = false end
	end
end

-- size: the Walls part is 72 studs wide in Blender units
local walls = scene:FindFirstChild("Walls", true)
local wallPart = walls:IsA("BasePart") and walls or walls:FindFirstChildWhichIsA("BasePart", true)
local size = wallPart.Size
local longest = math.max(size.X, size.Z)
local k = WANT_WIDTH / longest
if math.abs(k - 1) > 0.02 then scene:ScaleTo(scene:GetScale() * k) end

-- rotation: the Door sits on the front, so the direction from the building centre to the Door is the front
local door = scene:FindFirstChild("Door", true)
local doorPart = door and (door:IsA("BasePart") and door or door:FindFirstChildWhichIsA("BasePart", true))
local cf, bbox = scene:GetBoundingBox()
if doorPart then
	local front = Vector3.new(doorPart.Position.X - cf.Position.X, 0, doorPart.Position.Z - cf.Position.Z)
	if front.Magnitude < 0.5 then
		-- Door nearly centred: use the Steps (they stick out of the front) instead
		local steps = scene:FindFirstChild("Steps", true)
		local sp = steps and (steps:IsA("BasePart") and steps or steps:FindFirstChildWhichIsA("BasePart", true))
		if sp then front = Vector3.new(sp.Position.X - cf.Position.X, 0, sp.Position.Z - cf.Position.Z) end
	end
	front = front.Unit
	local angle = math.atan2(front.X * FACE.Z - front.Z * FACE.X, front.X * FACE.X + front.Z * FACE.Z)
	local test = CFrame.Angles(0, angle, 0) * front
	if test:Dot(FACE) < 0.99 then angle = -angle end
	scene:PivotTo(CFrame.Angles(0, angle, 0) * scene:GetPivot())
end

cf, bbox = scene:GetBoundingBox()
local shift = Vector3.new(CENTER.X - cf.Position.X, (CENTER.Y) - (cf.Position.Y - bbox.Y / 2), CENTER.Z - cf.Position.Z)
scene:PivotTo(scene:GetPivot() + shift)

-- swap out the old museum art (keep the Collection pedestal and anything with a prompt)
local archive = game.ServerStorage:FindFirstChild("OldLayoutArchive") or Instance.new("Folder", game.ServerStorage)
archive.Name = "OldLayoutArchive"
local bin = archive:FindFirstChild("OldMuseum") or Instance.new("Folder", archive)
bin.Name = "OldMuseum"
local museum = workspace.Environment.Districts:FindFirstChild("Museum")
local moved = 0
if museum then
	for _, c in museum:GetChildren() do
		if c.Name ~= "CollectionPedestal" and not c:FindFirstChildWhichIsA("ProximityPrompt", true) then
			c.Parent = bin
			moved += 1
		end
	end
end
local portico = workspace.CanalTownAssembly.Landmarks:FindFirstChild("MuseumPortico")
if portico then portico.Parent = bin moved += 1 end
local dome = wow:FindFirstChild("MuseumDome")
if dome then dome.Parent = bin moved += 1 end
print(("[PlaceMuseum] placed at %s, scale %.2f, old pieces archived: %d"):format(tostring(scene:GetPivot().Position), scene:GetScale(), moved))
