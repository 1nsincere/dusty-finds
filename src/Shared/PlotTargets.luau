-- PlotTargets.luau (ReplicatedStorage.Shared.PlotTargets)
-- Purpose: which parts of a shop a paint or a skin covers. One answer for the server (PaintService draws them for real) and
-- the client (PreviewController tries them on for 60 seconds), so a preview always matches what you would really get.
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Walls = Plot.Walls children + everything in Facade.Shell.Shop_Walls; Floor = Facade.Shell.Shop_Floor.
-- Pieces = shelves (Plot.Shelves) / pedestals (Plot.ExhibitSlots) that carry a PieceId (SkinService uses the same rule).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotTargets = {}

local function addAll(list: { BasePart }, container: Instance?)
	if container == nil then
		return
	end
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	if container:IsA("BasePart") then
		table.insert(list, container)
	end
end

-- ===== Painting one part (shared by the server's real paint and the client's preview) =====
-- The shop's walls and floor are textured meshes: they carry a SurfaceAppearance, and for those the part's own Color does
-- NOTHING you can see. The colour that shows is SurfaceAppearance.Color (a tint over the texture), and the material can't change.
-- Plain parts (no SurfaceAppearance) use Color and Material as usual.
-- EXCEPTION, the main FLOOR: the ground-floor floor is a textured overlay mesh (Facade.Shell.Shop_Floor) on top of the plank slab
-- (Plot.Floor). A tint would never match the bought rooms' flat floors, so a floor paint HIDES the overlay and paints the slab
-- with the paint's colour AND material, exactly like the Back Room and Showroom floors: one identical floor everywhere.

local function surfaceOf(part: BasePart): SurfaceAppearance?
	return part:FindFirstChildWhichIsA("SurfaceAppearance")
end

-- The textured overlay that makes up the main floor (hidden while a floor paint is on).
local function isFloorOverlay(part: BasePart): boolean
	return part.Parent ~= nil and part.Parent.Name == "Shop_Floor" and surfaceOf(part) ~= nil
end

export type Look = { color: Color3, material: Enum.Material, transparency: number }

-- What the part looks like now: { color (the colour that shows), material, transparency }.
function PlotTargets.snapshot(part: BasePart): Look
	local sa = surfaceOf(part)
	return { color = if sa then sa.Color else part.Color, material = part.Material, transparency = part.Transparency }
end

-- The colour that currently shows on the part (a painted floor overlay keeps the paint colour in its tint, so this still matches).
function PlotTargets.shownColor(part: BasePart): Color3
	local sa = surfaceOf(part)
	return if sa then sa.Color else part.Color
end

-- ===== Textures: the shell's meshes carry a SurfaceAppearance (plaster, wood grain, shingles). A premium FINISH (Config.Finishes) is another
-- texture on the same part. Game scripts can NOT read or write a SurfaceAppearance's maps (Roblox security: ColorMap / NormalMap are plugin-only),
-- so the finishes are READY-MADE: ReplicatedStorage.ShellTextures holds one tiny MeshPart per texture, named by key (plaster, woodgrain, shingle,
-- pearl, velvet, brass, goldleaf, marblewall), each with its SurfaceAppearance. Painting a finish CLONES that SurfaceAppearance onto the part
-- (the old one is destroyed); the part's attribute ShellTex remembers which one it wears (nil = its own original). =====

-- Which of the three original textures a shell part wears, from its name; nil = not a textured shell part (the main floor overlay, props...).
local function originalTexture(part: BasePart): string?
	local name = part.Name
	if not (string.match(name, "^Shop_.+_mesh$") or string.match(name, "^BackRoom_.+_mesh$")) then
		return nil
	end
	if string.find(name, "Roof", 1, true) then
		return "shingle"
	elseif string.find(name, "Trim", 1, true) or string.find(name, "Accent", 1, true) then
		return "woodgrain"
	elseif string.find(name, "Walls", 1, true) or string.find(name, "BackCap_mesh", 1, true) then
		return "plaster"
	end
	return nil
end

local function textureTemplate(key: string): SurfaceAppearance?
	local folder = ReplicatedStorage:FindFirstChild("ShellTextures")
	local holder = folder and folder:FindFirstChild(key)
	return holder and holder:FindFirstChildWhichIsA("SurfaceAppearance")
end

-- Puts texture `key` (nil = the part's original) on the part if it is not already there. Returns the SurfaceAppearance that is on the part now.
local function setTexture(part: BasePart, sa: SurfaceAppearance, key: string?): SurfaceAppearance
	local original = originalTexture(part)
	if original == nil then
		return sa
	end
	local want = key or original
	if (part:GetAttribute("ShellTex") or original) == want then
		return sa
	end
	local template = textureTemplate(want)
	if template == nil then
		return sa -- finish textures not set up: keep what is there (the paint still tints it)
	end
	local new = template:Clone()
	new.Color = sa.Color
	sa:Destroy()
	new.Parent = part
	part:SetAttribute("ShellTex", if key then key else nil)
	return new
end

-- finish (optional) = a key of Config.Finishes: the premium texture for a textured shell part.
function PlotTargets.paintPart(part: BasePart, color: Color3, material: Enum.Material?, finish: string?)
	local sa = surfaceOf(part)
	if sa then
		sa = setTexture(part, sa, finish)
		sa.Color = color -- textured: tint (the premium finish, when there is one, is the texture itself)
		if isFloorOverlay(part) then
			part.Transparency = 1 -- the main floor: hide the texture, the painted slab underneath shows
		end
	else
		part.Color = color
		if material then
			part.Material = material
		end
	end
end

function PlotTargets.restorePart(part: BasePart, original: Look)
	local sa = surfaceOf(part)
	if sa then
		sa = setTexture(part, sa, nil)
		sa.Color = original.color
		if isFloorOverlay(part) then
			part.Transparency = original.transparency or 0
		end
	else
		part.Color = original.color
		part.Material = original.material
	end
end

-- Parts of a bought expansion room (Plot.Expansion_BackRoom / Expansion_Showroom): the named parts that sit directly in `group`.
-- The room only exists once it is bought, so a missing model simply adds nothing.
local function addNamed(list: { BasePart }, plot: Instance, expansion: string, group: string, names: { string })
	local model = plot:FindFirstChild(expansion)
	if model == nil then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name == group and table.find(names, d.Name) then
			table.insert(list, d)
		end
	end
end

-- kind = "Wall" | "Floor" | "Trim" | "Accent". Covers the ground-floor shop AND the bought Back Room and Showroom (second floor), so a paint or a
-- theme matches the whole shop.
function PlotTargets.paint(plot: Instance, kind: string): { BasePart }
	local list: { BasePart } = {}
	local facade = plot:FindFirstChild("Facade")
	local shell = facade and facade:FindFirstChild("Shell")
	if kind == "Wall" then
		local walls = plot:FindFirstChild("Walls")
		if walls then
			for _, part in walls:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(list, part)
				end
			end
		end
		addAll(list, shell and shell:FindFirstChild("Shop_Walls"))
		-- the second storey's wall mesh and the Back Room's walls
		local upper = facade and facade:FindFirstChild("Upper")
		addAll(list, upper and upper:FindFirstChild("Shop_UpWalls"))
		addNamed(list, plot, "Expansion_BackRoom", "Shell", { "BackWall", "OuterWall", "OuterWallR", "Ceiling" })
		-- the first floor's ceiling = a thin wall-coloured layer under the Showroom's upper floor (so the floor paint does not show from below)
		addNamed(list, plot, "Expansion_Showroom", "UpperFloor", { "CeilingMain", "CeilingBack", "CeilingFront" })
		-- the Back Room's universal shell meshes (ground and second-storey walls): models named BackRoom_Walls / BackRoom_UpWalls
		local room = plot:FindFirstChild("Expansion_BackRoom")
		if room then
			addAll(list, room:FindFirstChild("BackRoom_Walls", true))
			addAll(list, room:FindFirstChild("BackRoom_UpWalls", true))
		end
	elseif kind == "Floor" then
		addNamed(list, plot, "Expansion_BackRoom", "Shell", { "Floor" })
		addNamed(list, plot, "Expansion_Showroom", "UpperFloor", { "FloorMain", "FloorBack", "FloorFront" }) -- the strips beside the stairwell too
		addNamed(list, plot, "Expansion_UpperBackRoom", "Shell", { "AnnexFloor" }) -- the second floor above the Back Room
		addAll(list, shell and shell:FindFirstChild("Shop_Floor"))
		local base = plot:FindFirstChild("Floor") -- the plank slab under the floor mesh (shows at the edges)
		if base and base:IsA("BasePart") then
			table.insert(list, base)
		end
	elseif kind == "Trim" or kind == "Accent" then
		-- the universal shell's trim / accent meshes: ground (Shell), second storey (Upper), the removable rear cap, the Back Room's,
		-- and the stock decor's accent pieces (the blade sign)
		local upper = facade and facade:FindFirstChild("Upper")
		local decor = facade and facade:FindFirstChild("Decor")
		local room = plot:FindFirstChild("Expansion_BackRoom")
		if kind == "Trim" then
			addAll(list, shell and shell:FindFirstChild("Shop_Trim"))
			addAll(list, upper and upper:FindFirstChild("Shop_UpTrim"))
			addAll(list, upper and upper:FindFirstChild("Shop_BackCapTrim"))
			addAll(list, room and room:FindFirstChild("BackRoom_Trim", true))
			addAll(list, room and room:FindFirstChild("BackRoom_UpTrim", true))
		else
			addAll(list, shell and shell:FindFirstChild("Shop_Accent"))
			addAll(list, upper and upper:FindFirstChild("Shop_UpAccent"))
			addAll(list, decor and decor:FindFirstChild("Shop_Accent"))
			addAll(list, room and room:FindFirstChild("BackRoom_UpAccent", true))
		end
	end
	return list
end

-- kind = "Shelf" | "Pedestal"
function PlotTargets.pieces(plot: Instance, kind: string): { BasePart }
	local FOLDER = { Shelf = "Shelves", Pedestal = "ExhibitSlots" }
	local folder = FOLDER[kind] and plot:FindFirstChild(FOLDER[kind])
	local list: { BasePart } = {}
	for _, part in if folder then folder:GetChildren() else {} do
		if part:IsA("BasePart") and part:GetAttribute("PieceId") ~= nil then
			table.insert(list, part)
		end
	end
	return list
end

return PlotTargets
