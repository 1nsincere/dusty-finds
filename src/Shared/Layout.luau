-- Layout.luau (ReplicatedStorage.Shared.Layout)
-- Purpose: the rules of the shop edit mode (docs/09_Edit_Mode_Plan.md): 2.8-stud grid, 4 rotations, footprints, and
-- "may this piece stand here?". Shared so the client's green/red preview and the server's check of RequestSaveLayout
-- can never disagree. Everything is in PLOT-LOCAL studs (plot Floor centre = 0; x/z on the floor, y up).
-- Owner: Dev 1 (Ace) per the plan; first version by Dev 3 (Sean) for the edit screen (2026-11-24), Ace to review.
-- Depends on: nothing for the rules; Layout.readAreas / Layout.pieceInfo read Workspace.Plots.PlotN (EditZones, pieces).

local Layout = {}

Layout.GRID = 2.8
Layout.ORIGIN = -26.6 -- grid lines at ORIGIN + k * GRID: the inner face of the shop walls, so pieces sit flush to them
Layout.FLOORS = { Ground = 0.7, Upstairs = 18.5 } -- top of each walkable floor
Layout.ENABLED = false -- 2026-11-26 (Ace): Edit mode is paused. Shelves and pedestals stay in their fixed default spots (saved layouts are kept in the data, ignored) until the Edit update.
Layout.MAX_PIECES = 32 -- a saved layout never has more entries than this (server size check)
local EPS = 0.02

export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Area = { name: string, kind: string, floor: string, requires: string?, x0: number, x1: number, z0: number, z1: number }
export type Placement = { x: number, z: number, rot: number, floor: string }
export type Other = { id: string, floor: string, rect: Rect }

function Layout.isRotation(rot: any): boolean
	return rot == 0 or rot == 90 or rot == 180 or rot == 270
end

-- Width (x) and depth (z) of a piece's footprint at a rotation, from its size at rotation 0.
function Layout.footprint(sizeX: number, sizeZ: number, rot: number): (number, number)
	if rot == 90 or rot == 270 then
		return sizeZ, sizeX
	end
	return sizeX, sizeZ
end

function Layout.rect(x: number, z: number, w: number, d: number): Rect
	return { x0 = x - w / 2, x1 = x + w / 2, z0 = z - d / 2, z1 = z + d / 2 }
end

-- Snap a centre so the footprint's low edges land on grid lines (pieces line up with each other and the walls).
function Layout.snap(x: number, z: number, w: number, d: number): (number, number)
	local function one(v: number, size: number): number
		local k = math.floor((v - size / 2 - Layout.ORIGIN) / Layout.GRID + 0.5)
		return Layout.ORIGIN + k * Layout.GRID + size / 2
	end
	return one(x, w), one(z, d)
end

function Layout.onGrid(x: number, z: number, w: number, d: number): boolean
	local sx, sz = Layout.snap(x, z, w, d)
	return math.abs(sx - x) < EPS and math.abs(sz - z) < EPS
end

local function inside(a: Rect, b: Rect): boolean
	return a.x0 >= b.x0 - EPS and a.x1 <= b.x1 + EPS and a.z0 >= b.z0 - EPS and a.z1 <= b.z1 + EPS
end

-- Touching edges is fine; only a real overlap counts.
function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - EPS and a.x1 > b.x0 + EPS and a.z0 < b.z1 - EPS and a.z1 > b.z0 + EPS
end

local function samePlacement(a: Placement?, b: Placement?): boolean
	return a ~= nil and b ~= nil and a.floor == b.floor and a.rot == b.rot
		and math.abs(a.x - b.x) < EPS and math.abs(a.z - b.z) < EPS
end

-- May a piece of this size (at rotation 0) stand at placement p?
-- ctx.areas: from Layout.readAreas; ctx.owned: { [roomName] = true } (BackRoom, Showroom);
-- ctx.others: the other pieces where they will stand; ctx.default: the piece's own default spot (allowed off-grid).
-- Returns ok, reason ("badInput", "badFloor", "badRotation", "offGrid", "outside", "keepClear", "overlap"), detail.
function Layout.check(sizeX: number, sizeZ: number, p: Placement, ctx): (boolean, string?, string?)
	if type(p) ~= "table" or type(p.x) ~= "number" or type(p.z) ~= "number" or p.x ~= p.x or p.z ~= p.z then
		return false, "badInput", nil
	end
	if type(p.floor) ~= "string" or Layout.FLOORS[p.floor] == nil then
		return false, "badFloor", nil
	end
	if not Layout.isRotation(p.rot) then
		return false, "badRotation", nil
	end
	local w, d = Layout.footprint(sizeX, sizeZ, p.rot)
	if not samePlacement(p, ctx.default) and not Layout.onGrid(p.x, p.z, w, d) then
		return false, "offGrid", nil
	end
	local r = Layout.rect(p.x, p.z, w, d)
	local owned = ctx.owned or {}
	local inZone = false
	for _, a in ctx.areas do
		if a.kind == "Zone" and a.floor == p.floor and (a.requires == nil or owned[a.requires]) and inside(r, a) then
			inZone = true
			break
		end
	end
	if not inZone then
		return false, "outside", nil
	end
	for _, a in ctx.areas do
		if a.kind == "KeepClear" and a.floor == p.floor and (a.requires == nil or owned[a.requires]) and Layout.overlaps(r, a) then
			return false, "keepClear", a.name
		end
	end
	for _, o in ctx.others or {} do
		if o.floor == p.floor and Layout.overlaps(r, o.rect) then
			return false, "overlap", o.id
		end
	end
	return true, nil, nil
end

-- Friendly text for a refusal (shown on the edit screen; the server sends the reason code).
Layout.REASON_TEXT = {
	badInput = "That spot isn't valid.",
	badFloor = "That floor doesn't exist.",
	badRotation = "Pieces turn in quarter turns only.",
	offGrid = "Pieces snap to the floor grid.",
	outside = "It has to stand inside your shop.",
	keepClear = "Keep that space clear for customers.",
	overlap = "It's bumping into another piece.",
	reserved = "A customer is buying from this shelf.",
	locked = "That piece isn't unlocked yet.",
}

-- ===== Readers (instances -> plain tables; used by the client and the server) =====

-- The plot's EditZones parts as plot-local rectangles.
function Layout.readAreas(plot: Instance): { Area }
	local floor = plot:FindFirstChild("Floor")
	local folder = plot:FindFirstChild("EditZones")
	local areas: { Area } = {}
	if not (floor and floor:IsA("BasePart") and folder) then
		return areas
	end
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local rel = floor.CFrame:ToObjectSpace(part.CFrame)
			local size = (rel - rel.Position):VectorToWorldSpace(part.Size)
			local hx, hz = math.abs(size.X) / 2, math.abs(size.Z) / 2
			table.insert(areas, {
				name = part.Name,
				kind = part:GetAttribute("Kind") or "Zone",
				floor = part:GetAttribute("Floor") or "Ground",
				requires = part:GetAttribute("Requires"),
				x0 = rel.X - hx, x1 = rel.X + hx, z0 = rel.Z - hz, z1 = rel.Z + hz,
			})
		end
	end
	return areas
end

-- Which floor a plot-local height belongs to.
function Layout.floorOf(y: number): string
	return if y > 12 then "Upstairs" else "Ground"
end

-- Where a piece stands now, as a Placement (rotation measured against its DefaultCFrame).
function Layout.placementOf(floor: BasePart, part: BasePart, default: CFrame): Placement
	local rel = floor.CFrame:ToObjectSpace(part.CFrame)
	local turn = default:ToObjectSpace(CFrame.new(default.Position) * (rel - rel.Position))
	local _, ry = turn:ToEulerAnglesYXZ()
	local rot = (math.floor(math.deg(ry) / 90 + 0.5) * 90) % 360
	return { x = rel.X, z = rel.Z, rot = rot, floor = Layout.floorOf(rel.Y) }
end

-- The plot-local CFrame for a piece at a placement: same height above its floor as at its default, turned by rot.
function Layout.cframeFor(p: Placement, sizeY: number, default: CFrame): CFrame
	local y = Layout.FLOORS[p.floor] + sizeY / 2
	return CFrame.new(p.x, y, p.z) * (default - default.Position) * CFrame.Angles(0, math.rad(p.rot), 0)
end

return Layout
