-- FlairController.luau (StarterPlayerScripts.Client.Controllers.FlairController)
-- Purpose: the VIP / pass cosmetics everybody can see (docs/12 Stage 5), all drawn on the client from Player attributes the server
-- sets (MonetizationService.PublishCosmetics): the COMPANION PET that follows a player (DF_Pet, DF_PetColor), the VIP TITLE above
-- the head (DF_Title, with a star for VIP), and the GLOW PACK sparkle / confetti bursts when YOU finish restoring or open a box
-- (ClientState entitlements.GlowPack). Looks only; nothing is sent to the server.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Monetization (pet looks), Shared.Config.Collector (draw distance), Shared.Remotes
-- (ItemRestored, BoxOpened events), ClientState.
-- Performance: pets and titles only for players within AuraDrawDistance; pets are 6 plain anchored parts each.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local Collector = require(Shared:WaitForChild("Config"):WaitForChild("Collector"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local FlairController = {}

local ONE_OF_ONE = {
	ink = Color3.fromRGB(246, 244, 252), -- platinum-white; the Sheen gradient dims it and sweeps a bright band across
	light = Color3.fromRGB(171, 139, 211),
	deep = Color3.fromRGB(73, 54, 99),
	plaque = Color3.fromRGB(28, 23, 38),
}
local ONE_OF_ONE_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
-- Fonts by name, with a fallback, so a missing font never breaks the title (Enum.Font:FromName gives nil for an unknown name).
local function pickFont(name: string, fallback: Font): Font
	local item = Enum.Font:FromName(name)
	return if item then Font.fromEnum(item) else fallback
end
local TITLE_FONT = pickFont("Michroma", ONE_OF_ONE_FONT) -- wide, geometric, futuristic: reads as a rare title next to the dark-flame aura
local TITLE_SUB_FONT = pickFont("Fondamento", ONE_OF_ONE_FONT) -- calligraphic, for the small "The" above it (contrast with the wide main line)

local localPlayer = Players.LocalPlayer
local pets: { [Player]: { model: Model, kind: string, color: string, body: BasePart, seed: number } } = {}
local folder: Folder? = nil

local function lookup(list: { any }, id: any): any
	for _, entry in list do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function root(player: Player): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

-- ===== Pets =====

local function part(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, color: Color3, offset: Vector3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("Offset", offset)
	p.Parent = parent
	return p
end

-- A small round friend: body, head, two ears, two eyes, a tail. `kind` changes the ears and tail a little.
local function buildPet(kind: string, color: Color3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Pet"
	local dark = Color3.fromRGB(40, 36, 36)
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(1.5, 1.3, 1.7), color, Vector3.new(0, 0, 0))
	part(model, "Head", Enum.PartType.Ball, Vector3.new(1.1, 1.0, 1.1), color, Vector3.new(0, 0.85, -0.7))
	if kind == "Bunny" then
		part(model, "EarL", Enum.PartType.Block, Vector3.new(0.25, 0.9, 0.25), color, Vector3.new(-0.28, 1.75, -0.7))
		part(model, "EarR", Enum.PartType.Block, Vector3.new(0.25, 0.9, 0.25), color, Vector3.new(0.28, 1.75, -0.7))
		part(model, "Tail", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 255, 255), Vector3.new(0, 0.1, 0.95))
	elseif kind == "Pup" then
		part(model, "EarL", Enum.PartType.Block, Vector3.new(0.3, 0.6, 0.2), color:Lerp(dark, 0.35), Vector3.new(-0.5, 1.2, -0.7))
		part(model, "EarR", Enum.PartType.Block, Vector3.new(0.3, 0.6, 0.2), color:Lerp(dark, 0.35), Vector3.new(0.5, 1.2, -0.7))
		part(model, "Tail", Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.7), color, Vector3.new(0, 0.5, 1.0))
	else -- Cat
		part(model, "EarL", Enum.PartType.Wedge, Vector3.new(0.3, 0.4, 0.3), color, Vector3.new(-0.38, 1.5, -0.7))
		part(model, "EarR", Enum.PartType.Wedge, Vector3.new(0.3, 0.4, 0.3), color, Vector3.new(0.38, 1.5, -0.7))
		part(model, "Tail", Enum.PartType.Block, Vector3.new(0.2, 0.2, 1.0), color, Vector3.new(0, 0.55, 1.1))
	end
	part(model, "EyeL", Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), dark, Vector3.new(-0.25, 0.95, -1.2))
	part(model, "EyeR", Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), dark, Vector3.new(0.25, 0.95, -1.2))
	return model, body
end

local function removePet(player: Player)
	local entry = pets[player]
	if entry then
		entry.model:Destroy()
		pets[player] = nil
	end
end

local function petColor(kind: string, colorId: any): Color3
	local choice = lookup(Monetization.VIP.PetColors, colorId)
	if choice and choice.color then
		return choice.color
	end
	local pet = lookup(Monetization.VIP.Pets, kind)
	return if pet then pet.color else Color3.fromRGB(240, 170, 90)
end

-- Make sure a player's pet matches their attributes (create, rebuild or remove).
local function syncPet(player: Player)
	local kind = player:GetAttribute("DF_Pet")
	if type(kind) ~= "string" or lookup(Monetization.VIP.Pets, kind) == nil then
		removePet(player)
		return
	end
	local colorId = player:GetAttribute("DF_PetColor")
	local colorKey = tostring(colorId)
	local entry = pets[player]
	if entry and entry.kind == kind and entry.color == colorKey then
		return
	end
	removePet(player)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "FlairPets"
		folder.Parent = workspace
	end
	local model, body = buildPet(kind, petColor(kind, colorId))
	model.Parent = folder
	pets[player] = { model = model, kind = kind, color = colorKey, body = body, seed = math.random() * 6 }
end

local function placePet(player: Player, entry: any, dt: number, now: number)
	local hrp = root(player)
	if hrp == nil then
		entry.model.Parent = nil
		return
	end
	local mine = root(localPlayer)
	if mine and hrp.Position:Distance(mine.Position) > Collector.AuraDrawDistance then
		entry.model.Parent = nil -- too far to matter (saves work on phones)
		return
	end
	if entry.model.Parent == nil then
		entry.model.Parent = folder
	end
	-- follow behind and to the right of the player, bobbing a little
	local bob = math.sin(now * 3 + entry.seed) * 0.15
	local target = hrp.CFrame * CFrame.new(2.6, -1.6 + 0.9 + bob, 3.2)
	local body: BasePart = entry.body
	local current: CFrame = body:GetAttribute("Pose") or target
	local alpha = math.clamp(dt * 5, 0, 1)
	local pos = current.Position:Lerp(target.Position, alpha)
	local look = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
	local pose = if look.Magnitude > 0.2 then CFrame.lookAt(pos, pos + look) else CFrame.new(pos) * (current - current.Position)
	body:SetAttribute("Pose", pose)
	for _, p in entry.model:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = pose * CFrame.new(p:GetAttribute("Offset") :: Vector3)
		end
	end
end

-- ===== Title above the head =====

local function syncTitle(player: Player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local title = player:GetAttribute("DF_Title")
	local vip = player:GetAttribute("DF_VIP") == true
	local oneOfOne = player:GetAttribute("DF_OneOfOne") == true
	local existing = head:FindFirstChild("FlairTitle")
	if (type(title) ~= "string" or title == "") and not vip and not oneOfOne then
		if existing then
			existing:Destroy()
		end
		return
	end
	local text = if oneOfOne then "◆ ONE OF ONE ◆" else (if vip then "★ " else "") .. (if type(title) == "string" and title ~= "" then title else "VIP")
	if existing then
		local label = existing:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = text
			label.TextColor3 = if oneOfOne then ONE_OF_ONE.ink else Color3.fromRGB(255, 214, 120)
			label.FontFace = if oneOfOne then TITLE_FONT else Font.fromEnum(Enum.Font.GothamBold)
			label.TextStrokeColor3 = if oneOfOne then ONE_OF_ONE.deep else Color3.fromRGB(20, 17, 15)
			label.TextStrokeTransparency = if oneOfOne then 0.45 else 0.4
			existing.Size = UDim2.fromOffset(if oneOfOne then 280 else 180, if oneOfOne then 56 else 24)
			existing.StudsOffsetWorldSpace = Vector3.new(0, if oneOfOne then 2.6 else 3.1, 0)
			local plaque = existing:FindFirstChild("Plaque")
			if plaque and plaque:IsA("Frame") then
				plaque.BackgroundColor3 = ONE_OF_ONE.plaque
				local rim = plaque:FindFirstChildOfClass("UIStroke")
				if rim then rim.Color = ONE_OF_ONE.light end
			end
		end
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "FlairTitle"
	board.Adornee = head
	board.Size = UDim2.fromOffset(if oneOfOne then 280 else 180, if oneOfOne then 56 else 24)
	board.StudsOffsetWorldSpace = Vector3.new(0, if oneOfOne then 2.6 else 3.1, 0)
	board.MaxDistance = 60
	board.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = if oneOfOne then TITLE_FONT else Font.fromEnum(Enum.Font.GothamBold)
	label.TextColor3 = if oneOfOne then ONE_OF_ONE.ink else Color3.fromRGB(255, 214, 120)
	label.TextStrokeColor3 = if oneOfOne then ONE_OF_ONE.deep else Color3.fromRGB(20, 17, 15)
	label.TextStrokeTransparency = if oneOfOne then 0.45 else 0.4
	label.Text = text
	label.Parent = board
	if oneOfOne then
		local plaque = Instance.new("Frame")
		plaque.Name = "Plaque"
		plaque.Size = UDim2.fromScale(1, 1)
		plaque.BackgroundColor3 = ONE_OF_ONE.plaque
		plaque.BackgroundTransparency = 0.08
		plaque.BorderSizePixel = 0
		plaque.ZIndex = 0
		plaque.Parent = board
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 9)
		corner.Parent = plaque
		local shade = Instance.new("UIGradient")
		shade.Name = "Shade"
		shade.Rotation = 90
		shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 203, 220))
		shade.Parent = plaque
		local rim = Instance.new("UIStroke")
		rim.Color = ONE_OF_ONE.light
		rim.Thickness = 1
		rim.Transparency = 0.12
		rim.Parent = plaque
		local rimSheen = Instance.new("UIGradient") -- the rim slowly turns: violet to platinum and back (animated in Start)
		rimSheen.Name = "RimSheen"
		rimSheen.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ONE_OF_ONE.light),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 238, 250)),
			ColorSequenceKeypoint.new(1, ONE_OF_ONE.light),
		})
		rimSheen.Parent = rim
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.AnchorPoint = Vector2.new(0.5, 1)
		accent.Position = UDim2.new(0.5, 0, 1, -2)
		accent.Size = UDim2.new(0.32, 0, 0, 1)
		accent.BackgroundColor3 = ONE_OF_ONE.light
		accent.BorderSizePixel = 0
		accent.ZIndex = 1
		accent.Parent = plaque
		local fade = Instance.new("UIGradient")
		fade.Name = "Fade"
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.45) })
		fade.Parent = accent
		local inset = Instance.new("UIPadding")
		inset.Name = "Inset"
		inset.PaddingLeft = UDim.new(0, 10)
		inset.PaddingRight = UDim.new(0, 10)
		inset.PaddingTop = UDim.new(0, 1)
		inset.PaddingBottom = UDim.new(0, 1)
		inset.Parent = label
		local sheen = Instance.new("UIGradient") -- a bright platinum band sweeps across the lettering every few seconds (animated in Start)
		sheen.Name = "Sheen"
		sheen.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 176, 222)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(205, 192, 232)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(205, 192, 232)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 176, 222)),
		})
		sheen.Parent = label
		label.ZIndex = 1
		-- a stacked title: a small calligraphic "The" above, the wide "ONE OF ONE" below
		label.Size = UDim2.fromScale(1, 0.62)
		label.Position = UDim2.fromScale(0, 0.34)
		local the = Instance.new("TextLabel")
		the.Name = "The"
		the.BackgroundTransparency = 1
		the.AnchorPoint = Vector2.new(0.5, 0)
		the.Position = UDim2.new(0.5, 0, 0, 3)
		the.Size = UDim2.new(0.3, 0, 0.3, 0)
		the.TextScaled = true
		the.FontFace = TITLE_SUB_FONT
		the.Text = "— The —"
		the.TextColor3 = ONE_OF_ONE.light
		the.TextTransparency = 0.05
		the.ZIndex = 2
		the.Parent = board
	end
	board.Parent = head
end

-- ===== The One of One aura: a dark-purple flame that traces the avatar's own outline =====
-- Like a Saiyan aura, but thin and only along the silhouette of the body: a Highlight draws a glowing dark-purple outline around the
-- avatar (no fill, hidden behind walls), the outline breathes and shifts between two purples, and thin wisps of dark flame rise off
-- the head, torso, arms and legs and stream upward. No rings or discs on the ground. Local only (each screen draws it; nothing is sent).
-- Reduce effects removes it all; it also hides beyond Collector.AuraDrawDistance. About 40 soft particles + 1 Highlight: fine for phones.
type DevAura = { highlight: Highlight, emitters: { ParticleEmitter }, light: PointLight, character: Model, seed: number }
local devAuraState: { [Player]: DevAura } = {}

local OUTLINE_DEEP = Color3.fromRGB(70, 24, 128) -- dark purple
local OUTLINE_GLOW = Color3.fromRGB(128, 62, 214) -- the brighter purple the outline breathes towards
local FLAME_DARK = Color3.fromRGB(34, 10, 66)
-- body parts that shed wisps, how many per second, and how big (R15 names; parts a rig does not have are skipped)
local WISP_PARTS = {
	{ "Head", 7, 0.55 },
	{ "UpperTorso", 9, 0.8 },
	{ "LowerTorso", 6, 0.7 },
	{ "LeftUpperArm", 5, 0.5 },
	{ "RightUpperArm", 5, 0.5 },
	{ "LeftUpperLeg", 4, 0.55 },
	{ "RightUpperLeg", 4, 0.55 },
}

local function buildWisp(part: BasePart, rate: number, size: number): ParticleEmitter
	local wisp = Instance.new("ParticleEmitter")
	wisp.Name = "OneOfOneWisp"
	wisp.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisp.Shape = Enum.ParticleEmitterShape.Box
	wisp.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface -- they leave from the skin of the part, which is what makes it hug the outline
	wisp.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	wisp.EmissionDirection = Enum.NormalId.Top
	wisp.Rate = rate
	wisp.Lifetime = NumberRange.new(0.9, 1.5)
	wisp.Speed = NumberRange.new(0.8, 1.8)
	wisp.SpreadAngle = Vector2.new(10, 10)
	wisp.Acceleration = Vector3.new(0, 3.2, 0) -- the flame streams upward and speeds up
	wisp.Drag = 0.6
	wisp.RotSpeed = NumberRange.new(-40, 40)
	wisp.Rotation = NumberRange.new(0, 360)
	wisp.LightEmission = 0.25
	wisp.LightInfluence = 0
	wisp.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, OUTLINE_GLOW),
		ColorSequenceKeypoint.new(0.45, OUTLINE_DEEP),
		ColorSequenceKeypoint.new(1, FLAME_DARK),
	})
	wisp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.55),
		NumberSequenceKeypoint.new(0.35, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	wisp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisp.Parent = part
	return wisp
end

local function removeDevAura(player: Player)
	local state = devAuraState[player]
	if state then
		state.highlight:Destroy()
		state.light:Destroy()
		for _, e in state.emitters do
			e:Destroy()
		end
		devAuraState[player] = nil
	end
end

local function syncDevAura(player: Player)
	local character = player.Character
	local hrp = root(player)
	local enabled = player:GetAttribute("DF_OneOfOne") == true and not reduceEffects()
	if not enabled or hrp == nil or character == nil then
		removeDevAura(player)
		return
	end
	local current = devAuraState[player]
	if current and current.character == character and current.highlight.Parent ~= nil then
		return
	end
	removeDevAura(player)
	local highlight = Instance.new("Highlight")
	highlight.Name = "OneOfOneOutline"
	highlight.Adornee = character
	highlight.FillTransparency = 1 -- outline only: the avatar itself is not tinted
	highlight.OutlineColor = OUTLINE_DEEP
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	local emitters: { ParticleEmitter } = {}
	for _, spec in WISP_PARTS do
		local part = character:FindFirstChild(spec[1])
		if part and part:IsA("BasePart") then
			table.insert(emitters, buildWisp(part, spec[2], spec[3]))
		end
	end
	local light = Instance.new("PointLight")
	light.Name = "OneOfOneGlow"
	light.Color = OUTLINE_GLOW
	light.Brightness = 0.55
	light.Range = 9
	light.Shadows = false
	light.Parent = hrp
	devAuraState[player] = { highlight = highlight, emitters = emitters, light = light, character = character, seed = (player.UserId % 97) / 10 }
end

-- Every frame: the outline breathes and shifts purple, wisps calm down while running, and the title's shine sweeps.
local function animateOneOfOne(now: number)
	local mine = root(localPlayer)
	for player, state in devAuraState do
		local hrp = root(player)
		if hrp == nil or state.highlight.Parent == nil then
			continue
		end
		local near = mine == nil or (hrp.Position - mine.Position).Magnitude <= Collector.AuraDrawDistance
		state.highlight.Enabled = near
		state.light.Enabled = near
		local t = now + state.seed
		local pulse = 0.5 + 0.5 * math.sin(t * 2.2)
		state.highlight.OutlineColor = OUTLINE_DEEP:Lerp(OUTLINE_GLOW, pulse * 0.55)
		state.highlight.OutlineTransparency = 0.18 + 0.3 * (1 - pulse)
		state.light.Brightness = 0.4 + 0.3 * pulse
		local humanoid = state.character:FindFirstChildOfClass("Humanoid")
		local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
		for _, e in state.emitters do
			e.Enabled = near
			e.Speed = if moving then NumberRange.new(0.4, 1) else NumberRange.new(0.8, 1.8)
		end
	end
	-- the title: a bright band sweeps across the lettering, the rim slowly turns
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("DF_OneOfOne") == true then
			local head = player.Character and player.Character:FindFirstChild("Head")
			local board = head and head:FindFirstChild("FlairTitle")
			local label = board and board:FindFirstChild("Label")
			local sheen = label and label:FindFirstChild("Sheen")
			if sheen and sheen:IsA("UIGradient") then
				local phase = (now % 4) / 4
				sheen.Offset = Vector2.new(-1.2 + 2.4 * math.min(phase * 1.5, 1), 0)
			end
			local plaque = board and board:FindFirstChild("Plaque")
			local rim = plaque and plaque:FindFirstChild("RimSheen", true)
			if rim and rim:IsA("UIGradient") then
				rim.Rotation = (now * 50) % 360
			end
		end
	end
end

-- ===== Glow Pack bursts (only YOU see yours; it's a reward for what you just did) =====

local function burst(colors: { Color3 }, count: number)
	if reduceEffects() then
		return
	end
	local entitlements = ClientState.Get("entitlements")
	if type(entitlements) ~= "table" or entitlements.GlowPack ~= true then
		return
	end
	local hrp = root(localPlayer)
	if hrp == nil then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(colors[1], colors[#colors])
	emitter.LightEmission = 0.7
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1.0, 1.8)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Parent = hrp
	emitter:Emit(count)
	task.delay(2.2, function()
		emitter:Destroy()
	end)
end

function FlairController.Init() end

function FlairController.Start()
	local function hook(player: Player)
		for _, name in { "DF_Pet", "DF_PetColor" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				syncPet(player)
			end)
		end
		for _, name in { "DF_Title", "DF_VIP", "DF_OneOfOne" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				syncTitle(player)
			end)
		end
		player:GetAttributeChangedSignal("DF_OneOfOne"):Connect(function() syncDevAura(player) end)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			syncTitle(player)
			syncDevAura(player)
		end)
		syncPet(player)
		syncTitle(player)
		syncDevAura(player)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		removePet(player)
		removeDevAura(player)
	end)
	ClientState.OnChanged("settings.reduceEffects", function()
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("DF_OneOfOne") then syncDevAura(player) end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, entry in pets do
			placePet(player, entry, dt, now)
		end
		animateOneOfOne(now)
	end)

	Remotes.ItemRestored.OnClientEvent:Connect(function()
		burst({ Color3.fromRGB(255, 214, 100), Color3.fromRGB(255, 244, 200) }, 40) -- golden shimmer
	end)
	Remotes.BoxOpened.OnClientEvent:Connect(function()
		burst({ Color3.fromRGB(255, 110, 170), Color3.fromRGB(110, 200, 255) }, 60) -- confetti
	end)
end

return FlairController
