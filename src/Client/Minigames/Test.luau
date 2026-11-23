-- Test.luau (StarterPlayerScripts.Client.Minigames.Test)
-- Purpose: Test step ("does it work?"): a needle sweeps back and forth; tap to stop it in the green zone (docs/01 C3).
-- Green = 100, yellow = 75, red = try again (the first miss is free, every later miss costs 10; never below 50).
-- The green zone is wider for common items. Pure logic: the adapter draws the bar and feeds Update(dt); no model is needed.
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: nothing (reads stepConfig.style and an optional stepConfig.rarity).
-- Interface: Test.new(model, stepConfig, onProgress, onComplete), :OnPointerDown(hit), :Update(dt), :OnDrag(), :OnPointerUp(), :Destroy().

local Test = {}
Test.__index = Test

local GREEN_WIDTH = { Common = 0.30, Uncommon = 0.24, Rare = 0.19, Epic = 0.15, Legendary = 0.12, Relic = 0.10, Mythic = 0.09, Secret = 0.08 }
local YELLOW_EXTRA = 0.10 -- extra width on EACH side of green
local SWEEP_SECONDS = 1.1 -- one way
local MISS_PENALTY = 10
local MIN_SCORE = 50

-- Where the zones are on the 0..1 bar: green is centred at `center`, yellow wraps it.
function Test.zones(rarity: string?, center: number?)
	local width = GREEN_WIDTH[rarity or "Common"] or GREEN_WIDTH.Common
	local c = center or 0.5
	return { greenFrom = c - width / 2, greenTo = c + width / 2, yellowFrom = c - width / 2 - YELLOW_EXTRA, yellowTo = c + width / 2 + YELLOW_EXTRA }
end

function Test.new(_model, stepConfig: { [string]: any }, onProgress, onComplete)
	local self = setmetatable({
		zone = Test.zones(stepConfig.rarity, stepConfig.center),
		needle = 0, direction = 1, misses = 0, stopped = false,
		onProgress = onProgress, onComplete = onComplete,
		destroyed = false, completed = false,
		lastResult = nil :: string?,
	}, Test)
	onProgress(0, 0, 1)
	return self
end

function Test:Update(dt: number)
	if self.destroyed or self.completed or self.stopped then
		return
	end
	self.needle += self.direction * dt / SWEEP_SECONDS
	if self.needle >= 1 then
		self.needle, self.direction = 1, -1
	elseif self.needle <= 0 then
		self.needle, self.direction = 0, 1
	end
end

function Test:Score(zone: string): number
	local base = if zone == "green" then 100 else 75
	return math.max(MIN_SCORE, base - MISS_PENALTY * math.max(0, self.misses - 1))
end

-- A tap stops the needle. Returns "green", "yellow" or "red".
function Test:OnPointerDown(_hit): string?
	if self.destroyed or self.completed then
		return nil
	end
	local p, z = self.needle, self.zone
	local result = if p >= z.greenFrom and p <= z.greenTo then "green" elseif p >= z.yellowFrom and p <= z.yellowTo then "yellow" else "red"
	self.lastResult = result
	if result == "red" then
		self.misses += 1
		self.needle, self.direction = 0, 1 -- try again from the start
		return result
	end
	self.completed = true
	self.stopped = true
	self.onProgress(1, 1, 1)
	self.onComplete(self:Score(result))
	return result
end

function Test:OnDrag() end

function Test:OnPointerUp() end

function Test:Destroy()
	self.destroyed = true
	self.onProgress = function() end
	self.onComplete = function() end
end

return Test
