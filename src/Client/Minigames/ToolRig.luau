-- ToolRig.luau
-- Purpose: the tool you work with while restoring, shown in your view: a damp folded cloth for Wipe, a putty knife for Scrape and
-- a round buffing pad for Polish (no tool for the repair steps). It follows the pointer over the item, hovers a little above
-- the surface and tilts like a held tool when you are not pressing, lies on the surface and works back and forth (a zig-zag for
-- the cloth, strokes for the knife, circles for the pad) while you hold, with a soft shadow under it and puffs of dust, rust
-- flakes or sparkles. (An arm was tried first and removed: it looked awkward.) Purely visual and client-side: it never touches
-- the item, the minigame logic or the server.
-- Owner: Dev 1 (Ace) with Claude. Depends on: a live camera (RestorationView sets it up).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ToolRig = {}
ToolRig.__index = ToolRig

local TOOL_FOR_STEP = { Wipe = "cloth", Scrape = "scraper", Polish = "buff" }
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder part's axis is X: this stands it up (axis = Y)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- ... and this lays it along Z

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Transparency = transparency or 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Tools are built around their own origin: y = 0 is the face that touches the item, +y is up out of it, +z points at the player.
-- Returns { { part, offset } }; ToolRig scales the whole thing with the camera distance.
local function buildTool(parent: Instance, kind: string): { { part: Part, offset: CFrame } }
	local parts = {}
	local function add(p: Part, offset: CFrame)
		table.insert(parts, { part = p, offset = offset })
	end
	local F, M, W, P = Enum.Material.Fabric, Enum.Material.Metal, Enum.Material.Wood, Enum.Material.SmoothPlastic
	local C, B = Enum.PartType.Cylinder, Enum.PartType.Ball
	if kind == "cloth" then
		-- a damp folded rag: a wet base, two folds on top, a stitched blue border and a few droplets
		add(newPart(parent, "ClothBase", Vector3.new(1.05, 0.1, 0.9), Color3.fromRGB(166, 190, 220), F), CFrame.new(0, 0.05, 0))
		add(newPart(parent, "ClothFold1", Vector3.new(0.98, 0.09, 0.62), Color3.fromRGB(222, 234, 248), F), CFrame.new(0, 0.14, -0.1) * CFrame.Angles(0, 0, math.rad(2)))
		add(newPart(parent, "ClothFold2", Vector3.new(0.84, 0.08, 0.46), Color3.fromRGB(238, 246, 252), F), CFrame.new(0.04, 0.215, 0.1) * CFrame.Angles(0, math.rad(8), math.rad(-3)))
		add(newPart(parent, "ClothRoll", Vector3.new(0.9, 0.16, 0.16), Color3.fromRGB(205, 221, 240), F, C), CFrame.new(0, 0.12, 0.42) * CFrame.Angles(0, 0, 0))
		for i, z in { -0.43, 0.43 } do
			add(newPart(parent, "Stitch" .. i, Vector3.new(1.05, 0.11, 0.05), Color3.fromRGB(70, 130, 204), F), CFrame.new(0, 0.05, z))
		end
		for i, x in { -0.5, 0.5 } do
			add(newPart(parent, "StitchSide" .. i, Vector3.new(0.05, 0.11, 0.9), Color3.fromRGB(70, 130, 204), F), CFrame.new(x, 0.05, 0))
		end
		for i, spot in { { -0.3, 0.5, 0.09 }, { 0.1, 0.52, 0.07 }, { 0.38, 0.46, 0.06 } } do
			add(newPart(parent, "Drop" .. i, Vector3.new(spot[3], spot[3], spot[3]), Color3.fromRGB(190, 226, 255), Enum.Material.Glass, B, 0.3), CFrame.new(spot[1], 0.03, spot[2]))
		end
	elseif kind == "scraper" then
		-- a putty knife: steel blade lying flat, brass ferrule, wooden handle rising toward the player, brass end cap
		local tilt = CFrame.Angles(math.rad(-30), 0, 0)
		add(newPart(parent, "Blade", Vector3.new(0.9, 0.035, 0.62), Color3.fromRGB(214, 218, 224), M), CFrame.new(0, 0.02, -0.2))
		add(newPart(parent, "BladeEdge", Vector3.new(0.9, 0.04, 0.05), Color3.fromRGB(246, 248, 250), M), CFrame.new(0, 0.022, -0.51))
		add(newPart(parent, "BladeNeck", Vector3.new(0.46, 0.04, 0.2), Color3.fromRGB(190, 196, 204), M), CFrame.new(0, 0.03, 0.2))
		add(newPart(parent, "Ferrule", Vector3.new(0.3, 0.24, 0.24), Color3.fromRGB(212, 166, 74), M, C), CFrame.new(0, 0.16, 0.38) * tilt * ALONG_Z)
		add(newPart(parent, "Handle", Vector3.new(0.9, 0.3, 0.3), Color3.fromRGB(164, 106, 62), W, C), CFrame.new(0, 0.36, 0.88) * tilt * ALONG_Z)
		add(newPart(parent, "HandleGrip", Vector3.new(0.5, 0.33, 0.33), Color3.fromRGB(126, 80, 48), W, C), CFrame.new(0, 0.42, 0.98) * tilt * ALONG_Z)
		add(newPart(parent, "EndCap", Vector3.new(0.36, 0.36, 0.36), Color3.fromRGB(212, 166, 74), M, B), CFrame.new(0, 0.62, 1.38))
	elseif kind == "buff" then
		-- a round buffing pad: dark rim, thick yellow microfibre pad, a lighter top and a wooden knob to hold it by
		add(newPart(parent, "PadRim", Vector3.new(0.05, 1.04, 1.04), Color3.fromRGB(226, 152, 36), F, C), CFrame.new(0, 0.025, 0) * UPRIGHT)
		add(newPart(parent, "Pad", Vector3.new(0.16, 0.98, 0.98), Color3.fromRGB(255, 212, 80), F, C), CFrame.new(0, 0.1, 0) * UPRIGHT)
		add(newPart(parent, "PadTop", Vector3.new(0.1, 0.8, 0.8), Color3.fromRGB(255, 233, 150), F, C), CFrame.new(0, 0.23, 0) * UPRIGHT)
		add(newPart(parent, "Collar", Vector3.new(0.12, 0.5, 0.5), Color3.fromRGB(90, 70, 56), P, C), CFrame.new(0, 0.34, 0) * UPRIGHT)
		add(newPart(parent, "Knob", Vector3.new(0.3, 0.34, 0.34), Color3.fromRGB(164, 106, 62), W, C), CFrame.new(0, 0.55, 0) * UPRIGHT)
		add(newPart(parent, "KnobTop", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(176, 116, 68), W, B), CFrame.new(0, 0.74, 0))
	end
	return parts
end

local function newEmitter(parent: Instance, kind: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightEmission = 0
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Speed = NumberRange.new(0.8, 2)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	if kind == "cloth" then -- soft grey-brown dust
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(190, 170, 140))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.55) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	elseif kind == "scraper" then -- rust flakes
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(190, 96, 40))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Acceleration = Vector3.new(0, -6, 0)
	else -- polish: golden glints
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 244, 200))
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	end
	e.Parent = parent
	return e
end

-- opts.model: the item being restored (the pointer ray lands on it); opts.stepType: "Wipe" | "Scrape" | "Polish" | ...
function ToolRig.new(opts: { model: Model, stepType: string? })
	local camera = workspace.CurrentCamera
	assert(camera, "ToolRig needs a camera")
	local self = setmetatable({
		destroyed = false, model = opts.model, camera = camera, held = false, contact = nil :: Vector3?, normal = Vector3.yAxis,
		lift = 0.6, t0 = os.clock(), speed = 0, toolKind = nil :: string?, toolParts = {}, touch = nil :: Vector2?, shown = 0,
	}, ToolRig)
	local folder = Instance.new("Folder")
	folder.Name = "RestorationTool"
	folder.Parent = workspace
	self.folder = folder
	self.fxPart = newPart(folder, "Fx", Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), nil, nil, 1)
	-- the soft shadow the tool throws on the item (a flat dark disc that follows the contact point)
	self.shadow = newPart(folder, "Shadow", Vector3.new(0.02, 1, 1), Color3.new(0, 0, 0), nil, Enum.PartType.Cylinder, 1)
	self.emitter = nil
	self:SetStep(opts.stepType)
	self.connections = {
		UserInputService.TouchStarted:Connect(function(input)
			self.touch = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		end),
		UserInputService.TouchMoved:Connect(function(input)
			self.touch = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		end),
	}
	self.binding = "RestorationTool" .. tostring(math.random(1, 1e9))
	-- after the view's camera (Camera + 1) so the tool is placed against the final frame
	RunService:BindToRenderStep(self.binding, Enum.RenderPriority.Camera.Value + 2, function(dt)
		if not self.destroyed then
			self:Step(dt)
		end
	end)
	return self
end

function ToolRig:SetStep(stepType: string?)
	for _, entry in self.toolParts do
		entry.part:Destroy()
	end
	table.clear(self.toolParts)
	if self.emitter then
		self.emitter:Destroy()
		self.emitter = nil
	end
	self.toolKind = if stepType then TOOL_FOR_STEP[stepType] else nil
	if self.toolKind then
		self.toolParts = buildTool(self.folder, self.toolKind)
		self.emitter = newEmitter(self.fxPart, self.toolKind)
	else
		self.shadow.Transparency = 1
	end
end

function ToolRig:Press()
	self.held = true
end

function ToolRig:Release()
	self.held = false
end

-- where the pointer is on screen (viewport coordinates)
function ToolRig:PointerScreen(): Vector2
	local view = self.camera.ViewportSize
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled and self.touch then
		return self.touch
	end
	if UserInputService.MouseEnabled then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(view.X * 0.55, view.Y * 0.6) -- no pointer yet: resting near the middle
end

function ToolRig:Step(dt: number)
	local camera = self.camera
	if workspace.CurrentCamera ~= camera or self.toolKind == nil then
		return
	end
	local now = os.clock() - self.t0
	local screen = self:PointerScreen()

	-- what the pointer touches: the item (its surface and normal), else a plane through the item's middle
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { self.model }
	params.RespectCanCollide = false
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local target, normal
	if hit then
		target, normal = hit.Position, hit.Normal
	else
		local center = self.model:GetPivot().Position
		local planeNormal = -camera.CFrame.LookVector
		local denom = ray.Direction:Dot(planeNormal)
		local distance = if math.abs(denom) > 1e-4 then (center - ray.Origin):Dot(planeNormal) / denom else 6
		target, normal = ray.Origin + ray.Direction * math.clamp(distance, 1, 60), planeNormal
	end
	local follow = 1 - math.exp(-dt * 18)
	local prev = self.contact or target
	self.contact = prev:Lerp(target, follow)
	self.normal = (self.normal:Lerp(normal, follow)).Unit
	self.speed = ((self.contact :: Vector3) - prev).Magnitude / math.max(dt, 1e-3)
	local contact: Vector3 = self.contact
	local up: Vector3 = self.normal

	-- pose: lies on the surface while pressed (and works), hovers with a held-tool tilt while not
	local working = self.held and self.speed > 0.12
	self.lift += ((if self.held then 0.015 else 0.45) - self.lift) * math.min(1, dt * 12)
	local right = camera.CFrame.RightVector - up * camera.CFrame.RightVector:Dot(up)
	if right.Magnitude < 0.05 then
		right = camera.CFrame.UpVector:Cross(up)
	end
	right = right.Unit
	local forward = up:Cross(right) -- along the surface, away from the player... flipped below so +Z faces the camera
	local distance = (camera.CFrame.Position - contact).Magnitude
	local scale = math.clamp(distance / 8.5, 0.5, 2.2) -- the tool is about as big as a hand-held rag next to the item
	local kind = self.toolKind
	local dx, dz = 0, 0 -- how the tool moves while it works
	if self.held then
		if kind == "cloth" then
			dx, dz = math.sin(now * 13) * 0.22, math.sin(now * 6.5) * 0.08 -- side to side, drifting
		elseif kind == "scraper" then
			dx, dz = math.sin(now * 3) * 0.06, math.sin(now * 11) * 0.2 -- short strokes toward / away from you
		else
			dx, dz = math.cos(now * 9) * 0.16, math.sin(now * 9) * 0.16 -- circles
		end
	end
	local zAxis = right:Cross(up) -- toward the camera side
	local toolPos = contact + up * (self.lift * scale) + right * (dx * scale) + zAxis * (dz * scale)
	local tilt = if self.held then 0 else (if kind == "scraper" then -0.3 else -0.38) -- hovering: tipped like a held tool
	local twist = if self.held and kind == "cloth" then math.sin(now * 13) * 0.14 else 0
	local toolCF = CFrame.fromMatrix(toolPos, right, up) * CFrame.Angles(tilt, twist, 0)
	self:PlaceTool(toolCF, scale)

	-- the shadow on the item (smaller and darker when the tool is down, bigger and fainter when it hovers)
	local lifted = math.clamp(self.lift / 0.45, 0, 1)
	self.shadow.Size = Vector3.new(0.02, (0.9 + 0.5 * lifted) * scale, (0.9 + 0.5 * lifted) * scale)
	self.shadow.CFrame = CFrame.fromMatrix(contact + up * 0.012 * scale, right, up) * UPRIGHT
	self.shadow.Transparency = 0.62 + 0.28 * lifted

	if self.emitter and working then
		self.fxPart.Position = contact + up * 0.05
		self.emitter:Emit(1)
	end
end

function ToolRig:PlaceTool(cf: CFrame, scale: number)
	for _, entry in self.toolParts do
		local p = entry.part
		if p:GetAttribute("BaseSize") == nil then
			p:SetAttribute("BaseSize", p.Size)
		end
		p.Size = (p:GetAttribute("BaseSize") :: Vector3) * scale
		p.CFrame = cf * CFrame.new(entry.offset.Position * scale) * (entry.offset - entry.offset.Position)
	end
end

function ToolRig:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	RunService:UnbindFromRenderStep(self.binding)
	for _, c in self.connections do
		c:Disconnect()
	end
	self.folder:Destroy()
end

return ToolRig
