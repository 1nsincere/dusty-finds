-- Rub.luau
-- Purpose: production movement-based Polish (adapted from the tested surface-entry and sample guards). Reworked 2026-11-25
-- (Ace + Claude): every polish surface now has its OWN shine. A dull surface wears a pulsing gold outline ("rub me");
-- rubbing it brings its colour back, adds a clear gleam and, when it is done, flashes and sparkles while its outline goes
-- out. The outlines left on the item show exactly what is still to polish. A surface the camera cannot reach (hidden behind
-- other parts) shines along with the average of the others, so the step can never get stuck. Completion is local.
-- Owner: Dev 2 (Dwayne), polish pass by Dev 1 (Ace). Depends on: disposable Model.PolishSurfaces and explicit movement tuning.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Rub = {}
Rub.__index = Rub
local DEBUG = true
local GRIME = Color3.fromRGB(105, 92, 78) -- what an unpolished surface is tinted toward
local DULL_AMOUNT = 0.55 -- how far toward GRIME the surface starts (clearer difference than before)
local SHINE = 0.34 -- reflectance reached at 100%
local GLEAM = 0.12 -- how much lighter than its own colour a finished surface gets (the visible "polished" glint)
local HINT_FILL = Color3.fromRGB(255, 226, 140)
local HINT_LINE = Color3.fromRGB(255, 244, 200)

-- Sparkle burst when a surface finishes (client-only visual).
local function sparkle(part: BasePart, amount: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(1, 3.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(amount)
	Debris:AddItem(attachment, 1.6)
end

local function positiveNumber(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Can a pointer actually land on this surface from where the camera is? (a grid of rays over its on-screen box)
local function reachable(model: Instance, part: BasePart): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = false
	local half = part.Size / 2
	local lox, hix, loy, hiy = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local v, onScreen = camera:WorldToViewportPoint((part.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
				if v.Z > 0 then
					lox, hix, loy, hiy = math.min(lox, v.X), math.max(hix, v.X), math.min(loy, v.Y), math.max(hiy, v.Y)
				end
			end
		end
	end
	if lox == math.huge then
		return false
	end
	local view = camera.ViewportSize
	lox, hix, loy, hiy = math.max(lox, 0), math.min(hix, view.X), math.max(loy, 0), math.min(hiy, view.Y)
	if hix <= lox or hiy <= loy then
		return false
	end
	local hits = 0
	for i = 0, 4 do
		for j = 0, 4 do
			local ray = camera:ViewportPointToRay(lox + (hix - lox) * (i + 0.5) / 5, loy + (hiy - loy) * (j + 0.5) / 5)
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
			if hit and (hit.Instance == part or hit.Instance:IsDescendantOf(part)) then
				hits += 1
			end
		end
	end
	return hits >= 2
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
		surfaces = {}, count = 0, reachableCount = 0, held = false, completed = false, destroyed = false,
		lastSurface = nil, lastViewport = nil, travel = 0, milestone = 0, shineSum = 0,
		tuning = table.clone(tuning), onProgress = onProgress, onComplete = onComplete, t0 = os.clock(),
	}, Rub)
	-- Validate before changing any surface, so malformed fixtures cannot partially start.
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			assert(part.Anchored and part.CanQuery and not part.CanCollide,
				`{part.Name}: set Anchored=true, CanQuery=true, CanCollide=false`)
			assert(part.Transparency == 0, `{part.Name}: set Transparency=0 so shine is visible`)
			self.surfaces[part] = { color = part.Color, material = part.Material, reflectance = part.Reflectance, own = 0, shine = 0, done = false }
			self.count += 1
		end
	end
	assert(self.count > 0, "PolishSurfaces needs at least one direct child surface Part")
	for part, s in self.surfaces do
		s.reach = reachable(model, part)
		if s.reach then
			self.reachableCount += 1
		end
	end
	if self.reachableCount == 0 then
		-- nothing can be touched from here (a model problem): every surface shines with the overall progress instead of never
		for _, s in self.surfaces do
			s.reach = true
		end
		self.reachableCount = self.count
		warn("[PolishRub] no polish surface is reachable from the camera; letting any of them take the rubbing")
	end
	-- Start dull, each surface with its pulsing "rub me" outline.
	for part, s in self.surfaces do
		s.dull = s.color:Lerp(GRIME, DULL_AMOUNT)
		s.bright = s.color:Lerp(Color3.new(1, 1, 1), GLEAM)
		part.Color = s.dull
		part.Reflectance = 0
		local h = Instance.new("Highlight")
		h.Name = "PolishHint"
		h.Adornee = part
		h.FillColor = HINT_FILL
		h.OutlineColor = HINT_LINE
		h.FillTransparency = 0.8
		h.OutlineTransparency = 0.25
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = part
		s.hint = h
	end
	self.hintConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - self.t0
		for _, s in self.surfaces do
			if s.hint and s.hint.Parent then
				local pulse = 0.5 + 0.5 * math.sin(t * 3.2)
				local left = 1 - s.shine
				s.hint.FillTransparency = 1 - (0.1 + 0.28 * pulse) * left
				s.hint.OutlineTransparency = 1 - (0.35 + 0.5 * pulse) * math.min(1, left * 1.5)
			end
		end
	end)
	onProgress(0, 0, self.count)
	if DEBUG then
		print(`[PolishRub] ready: {self.count} surfaces ({self.reachableCount} reachable); target {tuning.requiredTravel} viewport units`)
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

-- the surfaces' look follows their shine; a finished one flashes, sparkles and loses its outline
function Rub:Refresh()
	local reachableMean, n = 0, 0
	for _, s in self.surfaces do
		if s.reach then
			reachableMean += s.own
			n += 1
		end
	end
	reachableMean = if n > 0 then reachableMean / n else 0
	local sum = 0
	for part, s in self.surfaces do
		s.shine = if s.reach then s.own else reachableMean -- a surface nobody can reach shines with the others
		sum += s.shine
		part.Color = s.dull:Lerp(s.bright, s.shine)
		part.Reflectance = s.reflectance + (SHINE - s.reflectance) * s.shine
		if s.shine >= 0.999 and not s.done then
			s.done = true
			sparkle(part, 18)
			if s.hint then
				s.hint:Destroy()
				s.hint = nil
			end
		end
	end
	self.shineSum = sum
	return sum / self.count
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
	local credit = math.min(distance, self.tuning.maxCreditPerSample)
	self.travel += credit
	local s = self.surfaces[part]
	if s.reach and not s.done then
		-- each reachable surface needs its share of the total rubbing; all of them together make the whole step
		s.own = math.min(1, s.own + credit / (self.tuning.requiredTravel / self.reachableCount))
	end
	local progress = self:Refresh()
	local milestone = math.floor(progress * 4)
	if milestone > self.milestone then
		self.milestone = milestone
		if DEBUG then
			print(`[PolishRub] shine {milestone * 25}%`)
		end
	end
	self.onProgress(progress, self.travel, self.count)
	if progress >= 0.999 then
		self.completed = true
		self.held = false
		self.lastSurface = nil
		for surface, st in self.surfaces do
			if not st.done then
				sparkle(surface, 18)
			end
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
	if self.hintConn then
		self.hintConn:Disconnect()
	end
	for part, original in self.surfaces do
		if original.hint then
			original.hint:Destroy()
		end
		if part.Parent then
			part.Color = if self.completed then original.bright else original.color
			part.Material = original.material
			-- a finished polish keeps its shine for the next steps; an abandoned one goes back to how it was
			part.Reflectance = if self.completed then math.max(original.reflectance, SHINE) else original.reflectance
		end
	end
	self.onProgress = function() end
	self.onComplete = function() end
end

return Rub
