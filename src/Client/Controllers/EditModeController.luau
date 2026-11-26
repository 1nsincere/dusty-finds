-- EditModeController.luau (StarterPlayerScripts.Client.Controllers.EditModeController)
-- Purpose: the shop edit screen (docs/09_Edit_Mode_Plan.md, step 5): in your own shop, move and turn your display
-- shelves and exhibit pedestals on a 2.8-stud grid from a top-down view, then press Done. Mouse and touch.
-- Everything moves LOCALLY while you edit (only you see it); Done sends the whole layout once (RequestSaveLayout, Ace's
-- LayoutService, step 3) and the server moves the real pieces. Until that remote exists, Done only checks the layout and
-- puts everything back. Cancel / leaving always puts everything back.
-- Owner: Dev 3 (Sean). Depends on: Shared.Layout (the rules, shared with the server), Workspace.Plots.PlotN (Shelves,
-- DisplaySlots, ExhibitSlots, EditZones, PieceId / Piece / DefaultCFrame attributes), HudSkinController (look),
-- HudController.Notify (messages), Shared.Config.UiSkin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Layout"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local EditModeController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}

type Piece = {
	id: string,
	kind: string, -- "Shelf" | "Pedestal"
	part: BasePart,
	default: CFrame, -- plot-local spot it starts from (Reset goes back here)
	sizeX: number, -- footprint at rotation 0
	sizeZ: number,
	startCFrame: CFrame, -- world CFrame when editing began (Cancel restores it)
	followers: { { part: BasePart, offset: CFrame, start: CFrame } }, -- slots / bases that move with it
	placement: Layout.Placement,
	highlight: Highlight?,
}

local editing = false
local plot: Model? = nil
local floorPart: BasePart? = nil
local pieces: { [string]: Piece } = {}
local areas: { Layout.Area } = {}
local owned: { [string]: boolean } = {}
local viewFloor = "Ground"
local selected: Piece? = nil
local dragging = false
local dragOffset = Vector3.zero
local gui: ScreenGui? = nil
local hintLabel: TextLabel? = nil
local floorButton: TextLabel? = nil -- the Floor button's text
local doneButton: ImageButton? = nil
local previewFolder: Folder? = nil
local hiddenParts: { [BasePart]: number } = {}
local savedCamera: { [string]: any }? = nil
local savedControls: { [string]: number }? = nil
local savedGuis: { [ScreenGui]: boolean } = {}
local connections: { RBXScriptConnection } = {}

local function log(...)
	if DEBUG then
		print("[EditModeController]", ...)
	end
end

local function notify(text: string)
	local hud = others.HudController
	if hud and hud.Notify then
		hud.Notify("Info", text)
	end
end

local function myPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, p in plots:GetChildren() do
		if p:GetAttribute("OwnerUserId") == player.UserId and p:IsA("Model") then
			return p
		end
	end
	return nil
end

-- ===== Pieces =====

local function defaultFor(part: BasePart): CFrame?
	-- pedestal 1 lives upstairs while the Showroom is owned (PlotService MoveWithExpansion)
	local room = part:GetAttribute("MoveWithExpansion")
	if type(room) == "string" and owned[room] then
		local up = part:GetAttribute("ExpansionCFrame")
		if typeof(up) == "CFrame" then
			return up
		end
	end
	local d = part:GetAttribute("DefaultCFrame")
	return if typeof(d) == "CFrame" then d else nil
end

local function collectPieces(): { [string]: Piece }
	local found: { [string]: Piece } = {}
	local candidates = {}
	for _, folderName in { "Shelves", "ExhibitSlots" } do
		local folder = plot and plot:FindFirstChild(folderName)
		for _, part in if folder then folder:GetChildren() else {} do
			if part:IsA("BasePart") and type(part:GetAttribute("PieceId")) == "string" then
				-- locked pedestals are hidden (HideWhenLocked): only unlocked pieces can be moved
				local locked = folderName == "ExhibitSlots" and part:GetAttribute("Enabled") ~= true
				if not locked then
					table.insert(candidates, part)
				end
			end
		end
	end
	for _, part in candidates do
		local default = defaultFor(part)
		if default then
			local id = part:GetAttribute("PieceId")
			local piece: Piece = {
				id = id,
				kind = part:GetAttribute("PieceKind") or "Pedestal",
				part = part,
				default = default,
				sizeX = part.Size.X,
				sizeZ = part.Size.Z,
				startCFrame = part.CFrame,
				followers = {},
				placement = Layout.placementOf(floorPart :: BasePart, part, default),
			}
			found[id] = piece
		end
	end
	-- followers: anything in the plot tagged Piece = <id> (shelf slots, a pedestal's base / rim / plaque)
	for _, d in (plot :: Model):GetDescendants() do
		local id = d:GetAttribute("Piece")
		if type(id) == "string" and d:IsA("BasePart") and found[id] then
			local piece = found[id]
			table.insert(piece.followers, { part = d, offset = piece.part.CFrame:ToObjectSpace(d.CFrame), start = d.CFrame })
		end
	end
	return found
end

local function rectOf(piece: Piece): Layout.Rect
	local w, d = Layout.footprint(piece.sizeX, piece.sizeZ, piece.placement.rot)
	return Layout.rect(piece.placement.x, piece.placement.z, w, d)
end

local function checkPiece(piece: Piece): (boolean, string?)
	local list = {}
	for id, other in pieces do
		if id ~= piece.id then
			table.insert(list, { id = id, floor = other.placement.floor, rect = rectOf(other) })
		end
	end
	local default = { x = piece.default.X, z = piece.default.Z, rot = 0, floor = Layout.floorOf(piece.default.Y) }
	local ok, reason = Layout.check(piece.sizeX, piece.sizeZ, piece.placement, { areas = areas, owned = owned, others = list, default = default })
	return ok, reason
end

local function moveLocally(piece: Piece)
	local cf = (floorPart :: BasePart).CFrame * Layout.cframeFor(piece.placement, piece.part.Size.Y, piece.default)
	piece.part.CFrame = cf
	for _, f in piece.followers do
		f.part.CFrame = cf * f.offset
	end
end

-- Colours every piece: selected = gold outline, can't stand there = red. Returns the first problem (for Done).
local function refreshMarks(): (Piece?, string?)
	local firstBad, firstReason = nil, nil
	for _, piece in pieces do
		local ok, reason = checkPiece(piece)
		if not ok and firstBad == nil then
			firstBad, firstReason = piece, reason
		end
		local h = piece.highlight
		if h == nil then
			h = Instance.new("Highlight")
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = piece.part
			h.Parent = previewFolder
			piece.highlight = h
		end
		local isSelected = piece == selected
		h.Enabled = isSelected or not ok
		h.FillColor = if ok then Color3.fromRGB(110, 214, 120) else Color3.fromRGB(230, 60, 60)
		h.FillTransparency = if ok then 0.7 else 0.35
		h.OutlineColor = if isSelected then UiSkin.COLORS.accent else Color3.fromRGB(230, 60, 60)
	end
	if doneButton then
		doneButton.AutoButtonColor = firstBad == nil
		doneButton.BackgroundTransparency = if firstBad == nil then 0.12 else 0.5
	end
	if hintLabel then
		hintLabel.Text = if firstBad
			then `{firstBad.id}: {Layout.REASON_TEXT[firstReason or ""] or "can't stand there."}`
			elseif selected then "Drag to move · Rotate turns it · tap the floor to let go"
			else "Tap a shelf or pedestal, then drag it. Red = can't go there."
	end
	return firstBad, firstReason
end

-- ===== View: top-down camera, hide what is above the floor being edited, red keep-clear plates =====

local CEILING_ART = { Shop_Wood = true, Shop_Lamp = true, Shop_Iron = true }

local function restoreHidden()
	for part, old in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = old
		end
	end
	hiddenParts = {}
end

local function hideAbove()
	restoreHidden()
	local limit = if viewFloor == "Ground" then 13 else 30
	local floorCF = (floorPart :: BasePart).CFrame
	local facade = (plot :: Model):FindFirstChild("Facade")
	local roof = facade and facade:FindFirstChild("Roof")
	local upper = facade and facade:FindFirstChild("Upper")
	local shell = facade and facade:FindFirstChild("Shell")
	for _, d in (plot :: Model):GetDescendants() do
		if d:IsA("BasePart") then
			-- the roof and the upper storey's walls are always in the way of a top-down view; on the ground floor so are
			-- Ace's ceiling pieces (the beams are in the wood mesh, plus the lamps and iron fittings), only while editing
			local roofArt = (roof ~= nil and d:IsDescendantOf(roof)) or (upper ~= nil and d:IsDescendantOf(upper))
			if not roofArt and viewFloor == "Ground" and shell and d:IsDescendantOf(shell) then
				local group = d.Parent and d.Parent.Name
				roofArt = CEILING_ART[group or ""] == true
			end
			local bottom = floorCF:PointToObjectSpace(d.Position).Y - d.Size.Y / 2
			if roofArt or bottom > limit then
				hiddenParts[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

local function drawPlates()
	local folder = previewFolder :: Folder
	for _, c in folder:GetChildren() do
		if c.Name == "Plate" or c.Name == "WorkLight" then
			c:Destroy()
		end
	end
	local floorCF = (floorPart :: BasePart).CFrame
	local top = Layout.FLOORS[viewFloor]
	-- a work light over the floor being edited, so it reads at night too (local only, gone when you leave)
	local lamp = Instance.new("Part")
	lamp.Name = "WorkLight"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(1, 1, 1)
	lamp.CFrame = floorCF * CFrame.new(0, top + 24, if viewFloor == "Ground" and owned.BackRoom then 16.8 else 0)
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 2.5
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 244, 225)
	light.Parent = lamp
	lamp.Parent = folder
	for _, a in areas do
		if a.kind == "KeepClear" and a.floor == viewFloor and (a.requires == nil or owned[a.requires]) then
			local plate = Instance.new("Part")
			plate.Name = "Plate"
			plate.Anchored = true
			plate.CanCollide = false
			plate.CanQuery = false
			plate.CanTouch = false
			plate.CastShadow = false
			plate.Material = Enum.Material.SmoothPlastic
			plate.Color = Color3.fromRGB(220, 60, 60)
			plate.Transparency = 0.55
			plate.Size = Vector3.new(a.x1 - a.x0, 0.12, a.z1 - a.z0)
			plate.CFrame = floorCF * CFrame.new((a.x0 + a.x1) / 2, top + 0.08, (a.z0 + a.z1) / 2)
			plate.Parent = folder
		end
	end
end

local function aimCamera()
	local camera = workspace.CurrentCamera
	local floorCF = (floorPart :: BasePart).CFrame
	-- fit the whole floor (shop, plus the Back Room behind it) into the middle ~65% of the screen, between the hint at
	-- the top and the button bar at the bottom: visible depth = 2 * height * tan(fov / 2)
	local zMin, zMax = -28, if viewFloor == "Ground" and owned.BackRoom then 62 else 28
	local centreZ = (zMin + zMax) / 2
	local height = (zMax - zMin) / (0.65 * 2 * math.tan(math.rad(camera.FieldOfView / 2)))
	local centre = floorCF * Vector3.new(0, Layout.FLOORS[viewFloor], centreZ)
	local eye = centre + floorCF.UpVector * height
	-- straight down, the shop's back at the top of the screen and the door at the bottom
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, centre, floorCF:VectorToWorldSpace(Vector3.new(0, 0, 1)))
end

local function setView(floorName: string)
	viewFloor = floorName
	hideAbove()
	drawPlates()
	aimCamera()
	if floorButton then
		floorButton.Text = if viewFloor == "Ground" then "Upstairs" else "Ground floor"
	end
end

-- ===== Pointer: pick, drag, drop =====

local function pointOnFloor(screen: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screen.X, screen.Y) -- input positions leave out the top bar; ScreenPointToRay does too
	local floorCF = (floorPart :: BasePart).CFrame
	local planePoint = floorCF * Vector3.new(0, Layout.FLOORS[viewFloor], 0)
	local n = floorCF.UpVector
	local denom = ray.Direction:Dot(n)
	if math.abs(denom) < 1e-4 then
		return nil
	end
	local t = (planePoint - ray.Origin):Dot(n) / denom
	if t < 0 then
		return nil
	end
	return floorCF:PointToObjectSpace(ray.Origin + ray.Direction * t) -- plot-local
end

local function pieceAt(screen: Vector2): Piece?
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screen.X, screen.Y) -- input positions leave out the top bar; ScreenPointToRay does too
	local include = {}
	for _, piece in pieces do
		if piece.placement.floor == viewFloor then
			table.insert(include, piece.part)
			for _, f in piece.followers do
				table.insert(include, f.part)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		for _, piece in pieces do
			if hit.Instance == piece.part then
				return piece
			end
			for _, f in piece.followers do
				if hit.Instance == f.part then
					return piece
				end
			end
		end
	end
	-- pedestals are small from up here: also accept a tap on the floor inside a piece's footprint
	local p = pointOnFloor(screen)
	if p then
		for _, piece in pieces do
			local r = rectOf(piece)
			if piece.placement.floor == viewFloor and p.X >= r.x0 and p.X <= r.x1 and p.Z >= r.z0 and p.Z <= r.z1 then
				return piece
			end
		end
	end
	return nil
end

local function placeAt(piece: Piece, x: number, z: number)
	local w, d = Layout.footprint(piece.sizeX, piece.sizeZ, piece.placement.rot)
	local sx, sz = Layout.snap(x, z, w, d)
	if sx ~= piece.placement.x or sz ~= piece.placement.z or piece.placement.floor ~= viewFloor then
		piece.placement = { x = sx, z = sz, rot = piece.placement.rot, floor = viewFloor }
		moveLocally(piece)
		refreshMarks()
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	if not editing or processed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local screen = Vector2.new(input.Position.X, input.Position.Y)
	local piece = pieceAt(screen)
	selected = piece
	if piece then
		local p = pointOnFloor(screen)
		dragOffset = if p then Vector3.new(piece.placement.x - p.X, 0, piece.placement.z - p.Z) else Vector3.zero
		dragging = true
	end
	refreshMarks()
end

local function onInputChanged(input: InputObject)
	if not (editing and dragging and selected) then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local p = pointOnFloor(Vector2.new(input.Position.X, input.Position.Y))
	if p then
		placeAt(selected, p.X + dragOffset.X, p.Z + dragOffset.Z)
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end

-- ===== Buttons =====

local function rotateSelected()
	local piece = selected
	if not piece then
		notify("Tap a piece first, then Rotate.")
		return
	end
	local rot = (piece.placement.rot + 90) % 360
	local w, d = Layout.footprint(piece.sizeX, piece.sizeZ, rot)
	local sx, sz = Layout.snap(piece.placement.x, piece.placement.z, w, d)
	piece.placement = { x = sx, z = sz, rot = rot, floor = piece.placement.floor }
	moveLocally(piece)
	refreshMarks()
end

local function switchFloor()
	if not owned.Showroom then
		return
	end
	local target = if viewFloor == "Ground" then "Upstairs" else "Ground"
	-- a selected piece comes along to the other floor (same spot, snapped; red until it fits)
	local piece = selected
	setView(target)
	if piece then
		placeAt(piece, piece.placement.x, piece.placement.z)
	end
	refreshMarks()
end

local function resetAll()
	for _, piece in pieces do
		piece.placement = { x = piece.default.X, z = piece.default.Z, rot = 0, floor = Layout.floorOf(piece.default.Y) }
		moveLocally(piece)
	end
	selected = nil
	refreshMarks()
end

local exitEdit -- forward

local function layoutToSend(): { [string]: Layout.Placement }
	local out = {}
	for id, piece in pieces do
		local p = piece.placement
		local atDefault = p.rot == 0 and p.floor == Layout.floorOf(piece.default.Y)
			and math.abs(p.x - piece.default.X) < 0.02 and math.abs(p.z - piece.default.Z) < 0.02
		if not atDefault then
			out[id] = { x = p.x, z = p.z, rot = p.rot, floor = p.floor }
		end
	end
	return out
end

local function done()
	local bad, reason = refreshMarks()
	if bad then
		notify(`{bad.id}: {Layout.REASON_TEXT[reason or ""] or "can't stand there."}`)
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("RequestSaveLayout")
	local layout = layoutToSend()
	if remote and remote:IsA("RemoteEvent") then
		-- Remember where everything stood before this edit: if the server refuses the layout (LayoutService sets the plot
		-- attributes LayoutOk / LayoutMsg / LayoutRev), our local preview must snap back, because the server's pieces never moved.
		local snapshot = {}
		for _, piece in pieces do
			table.insert(snapshot, { part = piece.part, cf = piece.startCFrame, followers = piece.followers })
		end
		local shopPlot = plot
		local revBefore = if shopPlot then shopPlot:GetAttribute("LayoutRev") else nil
		remote:FireServer(layout)
		log("sent layout", layout)
		exitEdit(false) -- the server moves the real pieces; ours match its answer when it accepts
		if shopPlot then
			task.spawn(function()
				local waited = 0
				while waited < 5 and shopPlot:GetAttribute("LayoutRev") == revBefore do
					waited += task.wait(0.1)
				end
				if shopPlot:GetAttribute("LayoutOk") == false then
					for _, s in snapshot do
						if s.part.Parent then
							s.part.CFrame = s.cf
						end
						for _, f in s.followers do
							if f.part.Parent then
								f.part.CFrame = f.start
							end
						end
					end
					log("layout refused, put back:", shopPlot:GetAttribute("LayoutMsg"))
				end
			end)
		end
	else
		local n = 0
		for _ in layout do
			n += 1
		end
		notify(`Layout looks good ({n} moved). Saving comes with the server part (LayoutService), so it goes back for now.`)
		exitEdit(true)
	end
end

local function makeGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "EditMode"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20

	local skin = others.HudSkinController
	-- the skin's gradient tints a TextLabel's own text too, so text always sits in a child label on top of the panel
	local function label(parent: GuiObject, text: string, font: Font, color: Color3, padY: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.TextScaled = true
		l.FontFace = font
		l.TextColor3 = color
		l.Text = text
		l.ZIndex = parent.ZIndex + 1
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, padY), UDim.new(0, padY)
		pad.Parent = l
		l.Parent = parent
		return l
	end
	local hintPanel = Instance.new("Frame")
	hintPanel.Name = "Hint"
	hintPanel.AnchorPoint = Vector2.new(0.5, 0)
	hintPanel.Position = UDim2.new(0.5, 0, 0, 52)
	hintPanel.Size = UDim2.new(0.9, 0, 0, 40)
	hintPanel.Parent = screen
	local hintSize = Instance.new("UISizeConstraint")
	hintSize.MaxSize = Vector2.new(720, 40)
	hintSize.Parent = hintPanel
	if skin and skin.Panel then
		skin.Panel(hintPanel)
	end
	hintLabel = label(hintPanel, "", UiSkin.FONT_TEXT, UiSkin.COLORS.text, 6)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.new(0.96, 0, 0, 64)
	bar.BackgroundTransparency = 1
	bar.Parent = screen
	local barSize = Instance.new("UISizeConstraint")
	barSize.MaxSize = Vector2.new(760, 64)
	barSize.Parent = bar
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bar

	local function button(name: string, text: string, order: number, onClick: () -> ()): (ImageButton, TextLabel)
		local b = Instance.new("ImageButton")
		b.Name = name
		b.LayoutOrder = order
		b.Size = UDim2.new(0.158, -8, 1, 0) -- six buttons fit: Rotate, Upstairs, Reset, Cancel, Done, Layouts
		b.Image = ""
		b.Parent = bar
		if skin and skin.Panel then
			skin.Panel(b)
		end
		if skin and skin.Button then
			skin.Button(b)
		end
		local l = label(b, text, UiSkin.FONT_TITLE, UiSkin.COLORS.text, 14)
		b.Activated:Connect(onClick)
		return b, l
	end
	button("Rotate", "Rotate", 1, rotateSelected)
	local fb, fl = button("Floor", "Upstairs", 2, switchFloor)
	fb.Visible = owned.Showroom == true
	floorButton = fl
	button("Reset", "Reset", 3, resetAll)
	button("Cancel", "Cancel", 4, function()
		exitEdit(true)
	end)
	local db, dl = button("Done", "Done", 5, done)
	dl.TextColor3 = UiSkin.COLORS.money
	doneButton = db
	-- Layouts: only with the Saved Layouts pass or VIP. Leaves edit mode (unsaved moves are put back: press Done first to keep them),
	-- then opens the layout slots window.
	local lb = button("Layouts", "Layouts", 6, function()
		exitEdit(true)
		local slots = others.LayoutSlotsController
		if slots and slots.Open then
			slots.Open()
		end
	end)
	lb.Visible = Monetization.layoutSlots(ClientState.Get("entitlements")) > 0

	screen.Parent = player:WaitForChild("PlayerGui")
	return screen
end

-- ===== Enter / exit =====

local function freeze(on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if on then
		savedControls = { walk = humanoid.WalkSpeed, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	elseif savedControls then
		humanoid.WalkSpeed = savedControls.walk
		humanoid.JumpPower = savedControls.jumpPower
		humanoid.JumpHeight = savedControls.jumpHeight
		savedControls = nil
	end
end

local function hideOtherGuis(on: boolean)
	local playerGui = player:FindFirstChild("PlayerGui")
	if on then
		savedGuis = {}
		for _, name in { "HUD", "Tutorial" } do
			local g = playerGui and playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				savedGuis[g] = g.Enabled
				g.Enabled = false
			end
		end
	else
		for g, was in savedGuis do
			if g.Parent then
				g.Enabled = was
			end
		end
		savedGuis = {}
	end
end

function exitEdit(putBack: boolean)
	if not editing then
		return
	end
	editing = false
	dragging = false
	selected = nil
	for _, c in connections do
		c:Disconnect()
	end
	connections = {}
	if putBack then
		for _, piece in pieces do
			if piece.part.Parent then
				piece.part.CFrame = piece.startCFrame
			end
			for _, f in piece.followers do
				if f.part.Parent then
					f.part.CFrame = f.start
				end
			end
		end
	end
	pieces = {}
	restoreHidden()
	if previewFolder then
		previewFolder:Destroy()
		previewFolder = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	hintLabel, floorButton, doneButton = nil, nil, nil
	local camera = workspace.CurrentCamera
	if savedCamera then
		camera.CameraType = savedCamera.type
		camera.CFrame = savedCamera.cframe
		savedCamera = nil
	end
	freeze(false)
	hideOtherGuis(false)
	log("left edit mode", if putBack then "(put back)" else "(sent)")
end

-- Is the character inside its own shop (ground, Back Room or upstairs)?
local function standingInShop(p: Model): boolean
	local floor = p:FindFirstChild("Floor")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (floor and floor:IsA("BasePart") and root) then
		return false
	end
	local l = floor.CFrame:PointToObjectSpace(root.Position)
	return math.abs(l.X) < 28 and l.Z > -28 and l.Z < 62 and l.Y < 40
end

function EditModeController.Enter()
	if editing then
		return
	end
	local p = myPlot()
	if not p then
		notify("You need a shop to edit.")
		return
	end
	if not standingInShop(p) then
		notify("Go to your shop to edit it.")
		return
	end
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom then
		notify("Finish what you're doing first.")
		return
	end
	local floor = p:FindFirstChild("Floor")
	if not (floor and floor:IsA("BasePart")) then
		return
	end
	plot, floorPart = p, floor
	owned = { BackRoom = p:FindFirstChild("Expansion_BackRoom") ~= nil, Showroom = p:FindFirstChild("Expansion_Showroom") ~= nil }
	areas = Layout.readAreas(p)
	pieces = collectPieces()
	editing = true
	savedCamera = { type = camera.CameraType, cframe = camera.CFrame }
	freeze(true)
	hideOtherGuis(true)
	local folder = Instance.new("Folder")
	folder.Name = "EditModePreview"
	folder.Parent = workspace
	previewFolder = folder
	gui = makeGui()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local startFloor = if root and Layout.floorOf((floor :: BasePart).CFrame:PointToObjectSpace(root.Position).Y - 3) == "Upstairs" and owned.Showroom
		then "Upstairs"
		else "Ground"
	setView(startFloor)
	refreshMarks()
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		exitEdit(true)
	end))
	table.insert(connections, p:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		exitEdit(true)
	end))
	local count = 0
	for _ in pieces do
		count += 1
	end
	log("edit mode:", p.Name, count, "pieces, floor", startFloor)
end

function EditModeController.IsEditing(): boolean
	return editing
end

function EditModeController.Init(controllers)
	others = controllers
end

-- The Edit button is removed (Ace, 2026-11-26): nothing creates the HUD / Menu "Edit Mode" button any more. Edit mode itself is
-- still in this file (EditModeController.Enter), so setting SHOW_EDIT_BUTTON = true brings the button back.
local SHOW_EDIT_BUTTON = false

function EditModeController.Start()
	if not SHOW_EDIT_BUTTON then
		log("Edit button is turned off (SHOW_EDIT_BUTTON = false)")
		return
	end
	task.spawn(function()
		local skin = others.HudSkinController
		local button = skin and skin.HudButton and skin.HudButton("EditShop", UiSkin.ICONS.Upgrades)
		if not button then
			warn("[EditModeController] no HUD button: edit mode can't be opened")
			return
		end
		-- (the old "EDIT" tag is gone, 2026-11-25: HudLayoutController draws this as the Menu's "Edit Mode" cell with its own
		-- pencil icon and label, and the tag sat on top of that label)
		button.Activated:Connect(EditModeController.Enter)
		log("ready: Edit button added")
	end)
end

return EditModeController
