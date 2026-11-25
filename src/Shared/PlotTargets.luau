-- PlotTargets.luau (ReplicatedStorage.Shared.PlotTargets)
-- Purpose: which parts of a shop a paint or a skin covers. One answer for the server (PaintService draws them for real) and
-- the client (PreviewController tries them on for 60 seconds), so a preview always matches what you would really get.
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Walls = Plot.Walls children + everything in Facade.Shell.Shop_Walls; Floor = Facade.Shell.Shop_Floor.
-- Pieces = shelves (Plot.Shelves) / pedestals (Plot.ExhibitSlots) that carry a PieceId (SkinService uses the same rule).

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

function PlotTargets.paintPart(part: BasePart, color: Color3, material: Enum.Material?)
	local sa = surfaceOf(part)
	if sa then
		sa.Color = color -- textured: tint only
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

-- kind = "Wall" | "Floor". Covers the ground-floor shop AND the bought Back Room and Showroom (second floor), so a paint or a
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
		addNamed(list, plot, "Expansion_BackRoom", "Shell", { "BackWall", "OuterWall", "OuterWallR" })
	else
		addNamed(list, plot, "Expansion_BackRoom", "Shell", { "Floor" })
		addNamed(list, plot, "Expansion_Showroom", "UpperFloor", { "FloorMain" })
		addAll(list, shell and shell:FindFirstChild("Shop_Floor"))
		local base = plot:FindFirstChild("Floor") -- the plank slab under the floor mesh (shows at the edges)
		if base and base:IsA("BasePart") then
			table.insert(list, base)
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
