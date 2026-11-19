-- Rub.luau
-- Purpose: production movement-based Polish adapted from tested surface-entry and sample guards.
-- Owner: Dev 2 (Dwayne). Depends on: disposable Model.PolishSurfaces and explicit movement tuning.
-- Surfaces start dull (colour pulled toward grime, no shine) and return to their ORIGINAL colour/material as you rub,
-- so the finished item keeps its identity (Item Model Contract). Completion is local, not a reward.

local Debris = game:GetService("Debris")

local Rub = {}
Rub.__index = Rub
local DEBUG = true
local GRIME = Color3.fromRGB(105, 92, 78) -- what an unpolished surface is tinted toward
local DULL_AMOUNT = 0.45 -- how far toward GRIME the surface starts
local SHINE = 0.3 -- reflectance reached at 100%

-- Small sparkle burst when the polish completes (client-only visual).
local function sparkle(part: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(14)
	Debris:AddItem(attachment, 1.5)
end

local function positiveNumber(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function Rub.new(model, stepConfig, onProgress, onComplete)
	assert(stepConfig.type == "Polish", "Rub supports Polish only")
	local tuning = stepConfig.movement
	assert(type(tuning) == "table", "Supply explicit movement tuning")
	for _, key in { "requiredTravel", "maxSampleTravel", "maxCreditPerSample", "minSampleTravel" } do
		assert(positiveNumber(tuning[key]), `Invalid movement.{key}`)
	end
	assert(tuning.minSampleTravel < tuning.maxCreditPerSample
		and tuning.maxCreditPerSample <= tuning.maxSampleTravel, "Invalid test movement limits")
	local folder = model:FindFirstChild("PolishSurfaces")
	assert(folder and folder:IsA("Folder"), "Item needs a PolishSurfaces Folder")
	local self = setmetatable({
		surfaces = {}, count = 0, held = false, completed = false, destroyed = false,
		lastSurface = nil, lastViewport = nil, travel = 0, milestone = 0,
		tuning = table.clone(tuning), onProgress = onProgress, onComplete = onComplete,
	}, Rub)
	-- Validate before changing any surface, so malformed fixtures cannot partially start.
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			assert(part.Anchored and part.CanQuery and not part.CanCollide,
				`{part.Name}: set Anchored=true, CanQuery=true, CanCollide=false`)
			assert(part.Transparency == 0, `{part.Name}: set Transparency=0 so shine is visible`)
			self.surfaces[part] = { color = part.Color, material = part.Material, reflectance = part.Reflectance }
			self.count += 1
		end
	end
	assert(self.count > 0, "PolishSurfaces needs at least one direct child surface Part")
	-- Start dull: the player sees the colour come back while rubbing.
	for part, original in self.surfaces do
		original.dull = original.color:Lerp(GRIME, DULL_AMOUNT)
		part.Color = original.dull
		part.Reflectance = 0
	end
	onProgress(0, 0, self.count)
	if DEBUG then
		print(`[PolishRub] ready: {self.count} surfaces; target {tuning.requiredTravel} viewport units`)
	end
	return self
end

function Rub:OnPointerDown(_hit)
	if self.destroyed or self.completed then
		return
	end
	self.held = true
	-- Even a press directly on a surface must establish its baseline on the next sample.
	self.lastSurface = nil
	self.lastViewport = nil
end

function Rub:OnDrag(hit, delta, _dt)
	if self.destroyed or self.completed or not self.held then
		return
	end
	local part = hit and hit.Instance
	local camera = workspace.CurrentCamera
	if not part or not self.surfaces[part] or not part.CanQuery or not camera then
		-- PointerInput supplies nil over the blocked UI panel as well as empty space.
		self.lastSurface = nil
		self.lastViewport = nil
		return
	end
	local viewport = camera.ViewportSize
	local shortSide = math.min(viewport.X, viewport.Y)
	if shortSide <= 0 then
		self.lastSurface = nil
		self.lastViewport = nil
		return
	end
	if self.lastSurface ~= part or self.lastViewport ~= viewport then
		-- Discard the complete sample on entry/switch/resize; never credit the jump into it.
		self.lastSurface = part
		self.lastViewport = viewport
		return
	end
	if typeof(delta) ~= "Vector2" then
		return
	end
	local distance = delta.Magnitude / shortSide
	if distance ~= distance or distance == math.huge or distance < self.tuning.minSampleTravel then
		return -- includes a stationary pointer; there is no elapsed-time progress
	end
	if distance > self.tuning.maxSampleTravel then
		-- Reject large jumps rather than awarding their clamped distance.
		return
	end
	self.travel = math.min(self.tuning.requiredTravel,
		self.travel + math.min(distance, self.tuning.maxCreditPerSample))
	local progress = self.travel / self.tuning.requiredTravel
	for surface, original in self.surfaces do
		surface.Color = original.dull:Lerp(original.color, progress)
		surface.Reflectance = original.reflectance + (SHINE - original.reflectance) * progress
	end
	local milestone = math.floor(progress * 4)
	if milestone > self.milestone then
		self.milestone = milestone
		if DEBUG then
			print(`[PolishRub] shine {milestone * 25}%`)
		end
	end
	self.onProgress(progress, self.travel, self.count)
	if progress == 1 then
		self.completed = true
		self.held = false
		self.lastSurface = nil
		for surface in self.surfaces do
			sparkle(surface)
		end
		if DEBUG then
			print("[PolishRub] complete: local Polish score 100; await server confirmation")
		end
		self.onComplete(100)
	end
end

function Rub:OnPointerUp()
	self.held = false
	self.lastSurface = nil
	self.lastViewport = nil
end

function Rub:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:OnPointerUp()
	for part, original in self.surfaces do
		if part.Parent then
			part.Color = original.color
			part.Material = original.material
			part.Reflectance = original.reflectance
		end
	end
	self.onProgress = function() end
	self.onComplete = function() end
end

return Rub
