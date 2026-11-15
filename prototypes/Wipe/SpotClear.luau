-- SpotClear.luau: Wipe only; fades dirt decals without changing the item's body.
-- Owner: Dev 2 (Dwayne). Depends on: Model.DirtSpots with direct child spot Parts.
-- Prototype callbacks are local feedback, never inventory updates or completion rewards.
-- Destroy disconnects input state; the runner owns resetting the disposable test clone.

local SpotClear = {}
SpotClear.__index = SpotClear
local DEBUG = true

function SpotClear.new(model, stepConfig, onProgress, onComplete)
	assert(stepConfig.type == "Wipe", "This prototype supports Wipe only")
	local folder = model:FindFirstChild("DirtSpots")
	assert(folder and folder:IsA("Folder"), "WipeTestItem needs a DirtSpots Folder")
	local seconds = stepConfig.secondsPerSpot or 1.5
	assert(type(seconds) == "number" and seconds > 0 and seconds < math.huge,
		"secondsPerSpot must be a positive finite number")
	local self = setmetatable({
		spots = {}, total = 0, cleared = 0, seconds = seconds,
		held = false, destroyed = false, completed = false,
		onProgress = onProgress, onComplete = onComplete,
	}, SpotClear)

	-- Validate the whole fixture before changing visuals: malformed spots cannot silently disappear.
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			assert(part.Anchored and part.CanQuery and not part.CanCollide,
				`{part.Name}: set Anchored=true, CanQuery=true, CanCollide=false`)
			local decal = part:FindFirstChild("Dirt")
			assert(decal and decal:IsA("Decal"), `{part.Name} needs a Decal named Dirt`)
			self.spots[part] = { decal = decal, health = 1 }
			self.total += 1
		end
	end
	assert(self.total > 0, "DirtSpots needs at least one spot Part")
	for _, spot in self.spots do
		spot.decal.Transparency = 0
	end
	onProgress(0, 0, self.total)
	if DEBUG then
		print(`[WipeSpotClear] ready: {self.total} spots`)
	end
	return self
end

function SpotClear:OnPointerDown(_hit)
	if not self.destroyed and not self.completed then
		self.held = true
	end
end

function SpotClear:OnDrag(hit, _delta, dt)
	if self.destroyed or self.completed or not self.held or not hit then
		return
	end
	local spot = self.spots[hit.Instance]
	if not spot or spot.health <= 0 then
		return
	end
	spot.health = math.max(0, spot.health - math.clamp(dt, 0, 0.1) / self.seconds)
	spot.decal.Transparency = 1 - spot.health
	if spot.health == 0 then
		self.cleared += 1
		if DEBUG then
			print(`[WipeSpotClear] cleared {self.cleared}/{self.total}`)
		end
	end
	-- Fractional progress makes the bar respond throughout a wipe, not only at spot boundaries.
	local remaining = 0
	for _, entry in self.spots do
		remaining += entry.health
	end
	self.onProgress(1 - remaining / self.total, self.cleared, self.total)
	if self.cleared == self.total then
		self.completed = true
		self.held = false
		if DEBUG then
			print("[WipeSpotClear] complete (local Wipe step only)")
		end
		self.onComplete(100)
	end
end

function SpotClear:OnPointerUp()
	self.held = false
end

function SpotClear:Destroy()
	self.destroyed = true
	self.held = false
	self.onProgress = function() end
	self.onComplete = function() end
end

return SpotClear
