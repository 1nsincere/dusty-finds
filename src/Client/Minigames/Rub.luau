-- Rub.luau
-- Purpose: production movement-based Polish adapted from tested surface-entry and sample guards.
-- Owner: Dev 2 (Dwayne). Depends on: disposable Model.PolishSurfaces and explicit movement tuning.
-- Preserve original colour/material; only reflectance changes. Completion is local, not a reward.

local Rub = {}
Rub.__index = Rub
local DEBUG = true

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
		surface.Reflectance = original.reflectance + (0.3 - original.reflectance) * progress

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
