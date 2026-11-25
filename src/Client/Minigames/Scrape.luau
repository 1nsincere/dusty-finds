-- Scrape.luau (StarterPlayerScripts.Client.Minigames.Scrape)
-- Purpose: Scrape step (rust): drag back and forth over a rust spot; every direction reversal scrapes one layer (docs/01 C3).
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: model.RustSpots (Folder of spot Parts). Optional per spot: a NumberValue
-- named Layers (default 3) and a Decal named Rust, whose Transparency is faded as layers go. The score is 100 when finished.
-- Interface: Scrape.new(model, stepConfig, onProgress, onComplete), :OnPointerDown(hit), :OnDrag(hit, delta, dt), :OnPointerUp(), :Destroy().

local WorkHints = require(script.Parent.WorkHints)

local Scrape = {}
Scrape.__index = Scrape
local DEBUG = true

local DEFAULT_LAYERS = 3
local STROKE_PIXELS = 14 -- a reversal only counts after this much movement, so jitter does not scrape

function Scrape.new(model: Instance, stepConfig: { [string]: any }, onProgress, onComplete)
	local folder = model:FindFirstChild("RustSpots")
	assert(folder and folder:IsA("Folder"), "the item model needs a RustSpots Folder")
	local self = setmetatable({
		spots = {}, totalLayers = 0, removed = 0, cleared = 0, total = 0,
		held = false, destroyed = false, completed = false,
		onProgress = onProgress, onComplete = onComplete,
	}, Scrape)
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local layersValue = part:FindFirstChild("Layers")
			local layers = if layersValue and layersValue:IsA("NumberValue") then math.max(1, math.floor(layersValue.Value)) else DEFAULT_LAYERS
			local decal = part:FindFirstChild("Rust")
			self.spots[part] = {
				layers = layers, left = layers, decal = if decal and decal:IsA("Decal") then decal else nil,
				direction = nil :: Vector2?, travelled = 0,
			}
			self.totalLayers += layers
			self.total += 1
			if decal and decal:IsA("Decal") then
				decal.Transparency = 0
			end
		end
	end
	assert(self.total > 0, "RustSpots needs at least one spot Part")
	self.hints = WorkHints.new(Color3.fromRGB(255, 170, 96)) -- a pulsing ring on every rusty spot
	for part in self.spots do
		self.hints:Add(part)
	end
	onProgress(0, 0, self.total)
	if DEBUG then
		print(`[Scrape] ready: {self.total} spots, {self.totalLayers} layers`)
	end
	return self
end

function Scrape:OnPointerDown(_hit)
	if not self.destroyed and not self.completed then
		self.held = true
	end
end

function Scrape:OnDrag(hit, delta: Vector2?, _dt)
	if self.destroyed or self.completed or not self.held or not hit or not delta then
		return
	end
	local spot = self.spots[hit.Instance]
	if spot == nil or spot.left <= 0 or delta.Magnitude < 0.01 then
		return
	end
	local direction = delta.Unit
	if spot.direction == nil then
		spot.direction, spot.travelled = direction, delta.Magnitude
		return
	end
	if direction:Dot(spot.direction) >= 0 then
		-- same way: keep going
		spot.travelled += delta.Magnitude
		spot.direction = direction
		return
	end
	-- turned around: a reversal, but only after a real stroke
	if spot.travelled >= STROKE_PIXELS then
		spot.left -= 1
		self.removed += 1
		self.hints:Set(hit.Instance, spot.left / spot.layers)
		if spot.decal then
			spot.decal.Transparency = 1 - spot.left / spot.layers
		end
		if spot.left == 0 then
			self.cleared += 1
		end
		self.onProgress(self.removed / self.totalLayers, self.cleared, self.total)
		if self.removed == self.totalLayers then
			self.completed = true
			self.held = false
			self.onComplete(100)
		end
	end
	spot.direction, spot.travelled = direction, delta.Magnitude
end

function Scrape:OnPointerUp()
	self.held = false
	for _, spot in self.spots do
		spot.direction, spot.travelled = nil, 0
	end
end

function Scrape:Destroy()
	self.destroyed = true
	self.held = false
	if self.hints then
		self.hints:Destroy()
	end
	self.onProgress = function() end
	self.onComplete = function() end
end

return Scrape
