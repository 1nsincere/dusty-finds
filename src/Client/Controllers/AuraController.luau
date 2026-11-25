-- AuraController.luau (StarterPlayerScripts.Client.Controllers.AuraController)
-- Purpose: draws each player's collector AURA (docs/12 Stage 4): soft sparkles and a gentle glow round the avatar, stronger the
-- higher the collector tier (server attribute DF_CollectorTier, set by CollectorService). Purely visual and local: nothing is
-- sent to the server. Off when Settings "Reduce effects" is on; other players' auras only draw within
-- Config.Collector.AuraDrawDistance so a crowded server stays light on phones.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Collector, ClientState (settings.reduceEffects).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Config"):WaitForChild("Collector"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local AuraController = {}

local localPlayer = Players.LocalPlayer
local AURA = "CollectorAura"

local function root(player: Player): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

local function removeAura(part: BasePart)
	local old = part:FindFirstChild(AURA)
	if old then
		old:Destroy()
	end
end

-- Builds (or updates) the aura on a player's root part for their tier. Tier 1 (Dusty) has none.
local function applyTier(player: Player)
	local part = root(player)
	if part == nil then
		return
	end
	local tier = player:GetAttribute("DF_CollectorTier")
	local look = if type(tier) == "number" then Settings.TIERS[tier] else nil
	if look == nil or look.color == nil then
		removeAura(part)
		return
	end
	local holder = part:FindFirstChild(AURA)
	if holder == nil or holder:GetAttribute("Tier") ~= tier then
		removeAura(part)
		holder = Instance.new("Attachment")
		holder.Name = AURA
		holder:SetAttribute("Tier", tier)
		holder.Position = Vector3.new(0, -0.5, 0)
		holder.Parent = part
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(look.color)
		sparkles.LightEmission = 0.8
		sparkles.Rate = look.rate
		sparkles.Lifetime = NumberRange.new(1.2, 2)
		sparkles.Speed = NumberRange.new(0.6, 1.6)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparkles.Shape = Enum.ParticleEmitterShape.Cylinder
		sparkles.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		sparkles.EmissionDirection = Enum.NormalId.Top
		sparkles.Acceleration = Vector3.new(0, 1.2, 0)
		sparkles.Parent = holder
		if look.light > 0 then
			local glow = Instance.new("PointLight")
			glow.Name = "Glow"
			glow.Color = look.color
			glow.Brightness = look.light
			glow.Range = 9
			glow.Shadows = false
			glow.Parent = holder
		end
	end
end

-- On / off by Reduce effects and by distance (other players only).
local function syncVisibility(player: Player)
	local part = root(player)
	local holder = part and part:FindFirstChild(AURA)
	if holder == nil then
		return
	end
	local mine = root(localPlayer)
	local near = player == localPlayer or mine == nil or (part :: BasePart).Position:Distance(mine.Position) <= Settings.AuraDrawDistance
	local enabled = near and not reduceEffects()
	local sparkles = holder:FindFirstChild("Sparkles")
	if sparkles then
		(sparkles :: ParticleEmitter).Enabled = enabled
	end
	local glow = holder:FindFirstChild("Glow")
	if glow then
		(glow :: PointLight).Enabled = enabled
	end
end

local function hook(player: Player)
	player:GetAttributeChangedSignal("DF_CollectorTier"):Connect(function()
		applyTier(player)
		syncVisibility(player)
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- let the character finish loading
		applyTier(player)
		syncVisibility(player)
	end)
	applyTier(player)
	syncVisibility(player)
end

function AuraController.Init() end

function AuraController.Start()
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.5 then
			return
		end
		since = 0
		for _, player in Players:GetPlayers() do
			syncVisibility(player)
		end
	end)
end

return AuraController
