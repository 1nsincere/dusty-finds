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
	local existing = head:FindFirstChild("FlairTitle")
	if (type(title) ~= "string" or title == "") and not vip then
		if existing then
			existing:Destroy()
		end
		return
	end
	local text = (if vip then "★ " else "") .. (if type(title) == "string" and title ~= "" then title else "VIP")
	if existing then
		local label = existing:FindFirstChild("Label")
		if label and label:IsA("TextLabel") and label.Text ~= text then
			label.Text = text
		end
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "FlairTitle"
	board.Adornee = head
	board.Size = UDim2.fromOffset(180, 24)
	board.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	board.MaxDistance = 60
	board.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = board
	board.Parent = head
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
		for _, name in { "DF_Title", "DF_VIP" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				syncTitle(player)
			end)
		end
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			syncTitle(player)
		end)
		syncPet(player)
		syncTitle(player)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(removePet)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, entry in pets do
			placePet(player, entry, dt, now)
		end
	end)

	Remotes.ItemRestored.OnClientEvent:Connect(function()
		burst({ Color3.fromRGB(255, 214, 100), Color3.fromRGB(255, 244, 200) }, 40) -- golden shimmer
	end)
	Remotes.BoxOpened.OnClientEvent:Connect(function()
		burst({ Color3.fromRGB(255, 110, 170), Color3.fromRGB(110, 200, 255) }, 60) -- confetti
	end)
end

return FlairController
