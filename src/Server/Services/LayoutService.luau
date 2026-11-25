-- LayoutService.luau (ServerScriptService.Server.Services.LayoutService)
-- Purpose: the SERVER half of shop edit mode (docs/09): checks the layout a player sends (RequestSaveLayout), saves it in the
-- player data (`layout`), and puts the shelves / pedestals (and everything that follows them: shelf slots, pedestal bases)
-- where the layout says, on the server, so visitors see it too. Put back to the default spots when the owner leaves.
-- Owner: Dev 1 (Ace). Depends on: DataService, PlotService, DisplayService, Shared.Layout (the SAME rules the client previews).
-- Saved shape: layout[pieceId] = { x, z, rot, floor } in plot-local studs; only MOVED pieces are saved (missing = default spot).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)

local LayoutService = {}
local DEBUG = true
local log = Log.new("LayoutService", DEBUG)

local DataService, PlotService, DisplayService = nil, nil, nil

local MAX_COORD = 500 -- a placement this far from the plot centre is nonsense (stops huge numbers)
local MAX_ID_LENGTH = 32
local EPS = 0.02

type Piece = {
	id: string,
	kind: string,
	part: BasePart,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	home: CFrame, -- plot-local default spot (DefaultCFrame attribute)
	room: string?, -- MoveWithExpansion: stands elsewhere once this room is owned
	roomCFrame: CFrame?,
	followers: { { part: BasePart, offset: CFrame } }, -- parts tagged Piece = <id>, kept at their offset from the piece
}

type PlotInfo = { pieces: { [string]: Piece }, areas: { Layout.Area }, displaced: { [string]: boolean } }
local plotInfo: { [Instance]: PlotInfo } = {}

-- ===== Pure rules (testable without Studio objects) =====

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function samePlacement(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.floor == b.floor and a.rot == b.rot and math.abs(a.x - b.x) < EPS and math.abs(a.z - b.z) < EPS
end

-- Cleans what a client sent into plain placements. Returns the clean table, or nil + reason ("badInput").
function LayoutService.Clean(raw: any): ({ [string]: Layout.Placement }?, string?)
	if type(raw) ~= "table" then
		return nil, "badInput"
	end
	local clean = {}
	local count = 0
	for id, p in raw do
		count += 1
		if count > Layout.MAX_PIECES or type(id) ~= "string" or #id == 0 or #id > MAX_ID_LENGTH or type(p) ~= "table" then
			return nil, "badInput"
		end
		if not (isFiniteNumber(p.x) and isFiniteNumber(p.z) and math.abs(p.x) <= MAX_COORD and math.abs(p.z) <= MAX_COORD) then
			return nil, "badInput"
		end
		if type(p.floor) ~= "string" or Layout.FLOORS[p.floor] == nil then
			return nil, "badFloor"
		end
		if not Layout.isRotation(p.rot) then
			return nil, "badRotation"
		end
		clean[id] = { x = p.x, z = p.z, rot = p.rot, floor = p.floor }
	end
	return clean, nil
end

-- The whole check. ctx = {
--   pieces = { [id] = { sizeX, sizeZ, locked: boolean, busy: boolean (a customer is buying from it), default: Placement } },
--   areas = Layout.readAreas(...), owned = { [room] = true }, current = { [id] = Placement } (what is saved now) }
-- `layout` is the clean table from Clean. All or nothing. Returns ok, reason, detail (the piece id, or the keep-clear name).
function LayoutService.Validate(layout: { [string]: Layout.Placement }, ctx): (boolean, string?, string?)
	-- final spot of every usable piece: the saved one, else its default
	local final: { [string]: Layout.Placement } = {}
	for id, info in ctx.pieces do
		if not info.locked then
			final[id] = layout[id] or info.default
		end
	end
	for id, placement in layout do
		local info = ctx.pieces[id]
		if info == nil then
			return false, "badPiece", id
		end
		if info.locked then
			return false, "locked", id
		end
		if samePlacement(placement, info.default) then
			-- sent but at its default: harmless, nothing to check (the client strips these)
			continue
		end
		local others = {}
		for otherId, otherPlacement in final do
			if otherId ~= id then
				local other = ctx.pieces[otherId]
				local w, d = Layout.footprint(other.sizeX, other.sizeZ, otherPlacement.rot)
				table.insert(others, { id = otherId, floor = otherPlacement.floor, rect = Layout.rect(otherPlacement.x, otherPlacement.z, w, d) })
			end
		end
		local ok, reason, detail = Layout.check(info.sizeX, info.sizeZ, placement, {
			areas = ctx.areas, owned = ctx.owned, others = others, default = info.default,
		})
		if not ok then
			return false, reason, if detail then detail else id
		end
	end
	-- a shelf a customer is buying from stays put for those few seconds (moving it, or putting it back, is refused)
	for id, info in ctx.pieces do
		if info.busy and not info.locked then
			local wanted = layout[id] or info.default
			local now = (ctx.current or {})[id] or info.default
			if not samePlacement(wanted, now) then
				return false, "reserved", id
			end
		end
	end
	return true, nil, nil
end

-- ===== Studio objects =====

local function ownedRooms(player: Player): { [string]: boolean }
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	local rooms = {}
	for _, def in Upgrades do
		local name = def.effect and def.effect.expansion
		if name and (upgrades[def.id] or 0) > 0 then
			rooms[name] = true
		end
	end
	return rooms
end

-- Reads a plot's pieces once, at server start, while everything is still at its default spot.
local function buildInfo(plot: Instance): PlotInfo?
	local floor = plot:FindFirstChild("Floor")
	if not (floor and floor:IsA("BasePart")) then
		return nil
	end
	local info: PlotInfo = { pieces = {}, areas = Layout.readAreas(plot), displaced = {} }
	for _, folderName in { "Shelves", "ExhibitSlots" } do
		local folder = plot:FindFirstChild(folderName)
		for _, part in if folder then folder:GetChildren() else {} do
			local id = part:GetAttribute("PieceId")
			local home = part:GetAttribute("DefaultCFrame")
			if part:IsA("BasePart") and type(id) == "string" and typeof(home) == "CFrame" then
				local roomCFrame = part:GetAttribute("ExpansionCFrame")
				info.pieces[id] = {
					id = id,
					kind = part:GetAttribute("PieceKind") or "Pedestal",
					part = part,
					sizeX = part.Size.X, sizeY = part.Size.Y, sizeZ = part.Size.Z,
					home = home,
					room = part:GetAttribute("MoveWithExpansion"),
					roomCFrame = if typeof(roomCFrame) == "CFrame" then roomCFrame else nil,
					followers = {},
				}
			end
		end
	end
	for _, d in plot:GetDescendants() do
		local id = d:GetAttribute("Piece")
		local piece = type(id) == "string" and info.pieces[id]
		if piece and d:IsA("BasePart") and d ~= piece.part then
			table.insert(piece.followers, { part = d, offset = piece.part.CFrame:ToObjectSpace(d.CFrame) })
		end
	end
	return info
end

local function getInfo(plot: Instance): PlotInfo?
	local info = plotInfo[plot]
	if info == nil then
		info = buildInfo(plot)
		if info then
			plotInfo[plot] = info
		end
	end
	return info
end

local function isLocked(piece: Piece): boolean
	return piece.kind ~= "Shelf" and piece.part:GetAttribute("Enabled") ~= true -- a pedestal you don't own yet
end

local function defaultCFrame(piece: Piece, owned: { [string]: boolean }): CFrame
	if piece.room and owned[piece.room] and piece.roomCFrame then
		return piece.roomCFrame
	end
	return piece.home
end

local function defaultPlacement(cf: CFrame): Layout.Placement
	return { x = cf.X, z = cf.Z, rot = 0, floor = Layout.floorOf(cf.Y) }
end

-- Does a slot of this shelf hold an item a customer has reserved?
local function shelfBusy(player: Player, plot: Instance, shelfId: string): boolean
	local slots = plot:FindFirstChild("DisplaySlots")
	for _, slot in if slots then slots:GetChildren() else {} do
		if slot:GetAttribute("Piece") == shelfId then
			local index = slot:GetAttribute("SlotIndex")
			if type(index) == "number" and DisplayService.IsReservedAt(player, index) then
				return true
			end
		end
	end
	return false
end

local function savedLayout(player: Player): { [string]: Layout.Placement }
	local raw = DataService.GetValue(player, "layout")
	local clean = LayoutService.Clean(raw)
	return clean or {}
end

local function moveTo(plot: Instance, piece: Piece, plotLocal: CFrame)
	local floor = plot.Floor :: BasePart
	local cf = floor.CFrame * plotLocal
	piece.part.CFrame = cf
	for _, f in piece.followers do
		if f.part.Parent then
			f.part.CFrame = cf * f.offset
		end
	end
end

-- ===== Applying a layout =====

-- Puts every usable piece where the player's saved layout says (default spot when it has none). Safe to call any time; only
-- touches pieces that moved or were moved before.
function LayoutService.Apply(player: Player)
	local plot = PlotService.GetPlot(player)
	local info = plot and getInfo(plot)
	if plot == nil or info == nil then
		return
	end
	local owned = ownedRooms(player)
	local layout = savedLayout(player)
	for id, piece in info.pieces do
		if piece.part.Parent and not isLocked(piece) then
			local default = defaultCFrame(piece, owned)
			local placement = layout[id]
			if placement then
				moveTo(plot, piece, Layout.cframeFor(placement, piece.sizeY, default))
				info.displaced[id] = true
			elseif info.displaced[id] then
				moveTo(plot, piece, default)
				info.displaced[id] = nil
			end
		end
	end
end

-- Back to the default spots for the next owner of the plot.
local function resetPlot(plot: Instance)
	local info = plotInfo[plot]
	if info == nil then
		return
	end
	for id, piece in info.pieces do
		if info.displaced[id] and piece.part.Parent then
			moveTo(plot, piece, piece.home)
		end
	end
	info.displaced = {}
end

-- ===== Saving =====

-- Returns ok, reason, detail. All or nothing.
function LayoutService.Save(player: Player, raw: any): (boolean, string?, string?)
	local plot = PlotService.GetPlot(player)
	local info = plot and getInfo(plot)
	if plot == nil or info == nil then
		return false, "noPlot", nil
	end
	local layout, reason = LayoutService.Clean(raw)
	if layout == nil then
		return false, reason, nil
	end
	local owned = ownedRooms(player)
	local pieces = {}
	for id, piece in info.pieces do
		pieces[id] = {
			sizeX = piece.sizeX, sizeZ = piece.sizeZ,
			locked = isLocked(piece),
			busy = piece.kind == "Shelf" and shelfBusy(player, plot, id),
			default = defaultPlacement(defaultCFrame(piece, owned)),
		}
	end
	local ok, why, detail = LayoutService.Validate(layout, {
		pieces = pieces, areas = info.areas, owned = owned, current = savedLayout(player),
	})
	if not ok then
		return false, why, detail
	end
	-- drop entries that are just the default spot, so the save only holds real moves
	for id, placement in table.clone(layout) do
		if samePlacement(placement, pieces[id].default) then
			layout[id] = nil
		end
	end
	if not DataService.Set(player, "layout", layout) then
		return false, "saveFailed", nil
	end
	LayoutService.Apply(player)
	log.info(player.Name, "saved a layout with", (function()
		local n = 0
		for _ in layout do
			n += 1
		end
		return n
	end)(), "moved piece(s)")
	return true, nil, nil
end

-- ===== Layout slots (Saved Layouts pass: 3, VIP: +1; docs/12 Stage 5) =====
-- A slot holds a COPY of the shop layout that is saved right now. Loading a slot is a normal save of that layout: the same checks,
-- all or nothing, so a slot made before an upgrade or while a shelf was empty can still be refused today (with the usual reason).

function LayoutService.SlotCount(player: any): number
	return Monetization.layoutSlots(DataService.GetValue(player, "entitlements"))
end

-- Returns ok, reason ("noSlot" = no such slot / no pass, "noData", "saveFailed").
function LayoutService.SaveSlot(player: any, slot: any): (boolean, string?)
	if not Validate.isInteger(slot, 1, LayoutService.SlotCount(player)) then
		return false, "noSlot"
	end
	if type(DataService.GetValue(player, "layoutSlots")) ~= "table" then
		return false, "noData"
	end
	local layout = savedLayout(player) -- the shop as it is saved now (an empty table = the default shop)
	if not DataService.Set(player, "layoutSlots." .. tostring(slot), layout) then
		return false, "saveFailed"
	end
	return true, nil
end

-- Returns ok, reason ("noSlot", "noData", "empty" = nothing saved there, or any LayoutService.Save reason).
function LayoutService.LoadSlot(player: any, slot: any): (boolean, string?, string?)
	if not Validate.isInteger(slot, 1, LayoutService.SlotCount(player)) then
		return false, "noSlot", nil
	end
	local slots = DataService.GetValue(player, "layoutSlots")
	if type(slots) ~= "table" then
		return false, "noData", nil
	end
	local raw = slots[tostring(slot)]
	if raw == nil then
		return false, "empty", nil
	end
	return LayoutService.Save(player, raw)
end

local SLOT_TEXT = {
	noSlot = "You don't have that layout slot. Get Saved Layouts or VIP at the Collector's Corner.",
	empty = "That slot is empty. Save your shop layout there first.",
	noData = "Your shop isn't ready yet.",
	saveFailed = "Couldn't save that. Try again.",
}

local SAVED_TEXT = "Shop layout saved!"

function LayoutService.Init(services)
	DataService = services.DataService
	PlotService = services.PlotService
	DisplayService = services.DisplayService
	log.info("Init")
end

function LayoutService.Start()
	-- read every plot's pieces now, while the shelves are still at their default spots
	for _, plot in workspace:WaitForChild("Plots"):GetChildren() do
		getInfo(plot)
	end

	Remotes.RequestSaveLayout.OnServerEvent:Connect(function(player, raw)
		if not Validate.rateLimit(player, "RequestSaveLayout", 2) then
			return
		end
		local ok, reason, detail = LayoutService.Save(player, raw)
		local plot = PlotService.GetPlot(player)
		local text = if ok then SAVED_TEXT else (Layout.REASON_TEXT[reason or ""] or "Couldn't save the layout.")
		if not ok and detail and (reason == "overlap" or reason == "keepClear" or reason == "reserved") then
			log.info(player.Name, "layout refused:", reason, detail)
		end
		if plot then
			-- the client waits for this to know whether to keep its preview or snap back
			plot:SetAttribute("LayoutOk", ok)
			plot:SetAttribute("LayoutMsg", text)
			plot:SetAttribute("LayoutRev", (plot:GetAttribute("LayoutRev") or 0) + 1)
		end
		Remotes.Notify:FireClient(player, "Info", text)
	end)

	Remotes.RequestSaveLayoutSlot.OnServerEvent:Connect(function(player, slot)
		if not Validate.rateLimit(player, "RequestSaveLayoutSlot", 2) then
			return
		end
		local ok, reason = LayoutService.SaveSlot(player, slot)
		Remotes.Notify:FireClient(player, "Info", if ok then `Layout saved in slot {slot}!` else (SLOT_TEXT[reason or ""] or "Couldn't save the layout slot."))
	end)
	Remotes.RequestLoadLayoutSlot.OnServerEvent:Connect(function(player, slot)
		if not Validate.rateLimit(player, "RequestLoadLayoutSlot", 2) then
			return
		end
		local ok, reason = LayoutService.LoadSlot(player, slot)
		local text = if ok then `Layout {slot} is on your shop!` else (SLOT_TEXT[reason or ""] or Layout.REASON_TEXT[reason or ""] or "Couldn't use that layout.")
		Remotes.Notify:FireClient(player, "Info", text)
	end)

	-- the plot is assigned by PlotService's own OnPlayerLoaded callback (registered earlier), so it exists now
	DataService.OnPlayerLoaded(function(player)
		LayoutService.Apply(player)
	end)
	DataService.OnPlayerReleasing(function(player)
		local plot = PlotService.GetPlot(player)
		if plot then
			resetPlot(plot)
		end
	end)
	-- PlotService re-places pedestals after every purchase: put the layout back on top of that
	PlotService.SetRefreshHook(function(player)
		LayoutService.Apply(player)
	end)
	log.info("Start")
end

return LayoutService
