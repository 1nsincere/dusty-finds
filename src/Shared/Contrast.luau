-- Contrast.luau (ReplicatedStorage.Shared.Contrast)
-- Purpose: the trim contrast guard (docs/12, universal shop plan): trim must always be clearly lighter or darker than the wall, or the
-- building's edges vanish (dark wall + dark trim = a flat blob). PURE: no game state. Used by PaintService (the real draw), the
-- client's Preview and the Paint Bar note "Trim adjusted for contrast". Only the SHOWN colour changes; what the player chose is saved as is.
-- Owner: Dev 1 (Ace).

local Contrast = {}

Contrast.MIN_GAP = 0.22 -- minimum difference in perceived lightness (0 = black, 1 = white)
local PUSH = 0.30 -- when a trim is too close, it is moved to this far from the wall's lightness

local function toLinear(v: number): number
	return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

-- Perceived lightness (CIE L*, scaled 0..1).
function Contrast.lightness(color: Color3): number
	local y = 0.2126 * toLinear(color.R) + 0.7152 * toLinear(color.G) + 0.0722 * toLinear(color.B)
	if y > 0.008856 then
		return 1.16 * y ^ (1 / 3) - 0.16
	end
	return 9.033 * y
end

-- The same hue and saturation, with the brightness (HSV value) changed until the lightness matches `target` (0..1).
local function withLightness(color: Color3, target: number): Color3
	local h, s = color:ToHSV()
	local result = color
	-- a strong colour (a deep red) cannot be made very light without washing out: if the target is out of reach, soften the saturation step by step
	for step = 0, 6 do
		local sat = s * (1 - step / 6)
		local lo, hi = 0, 1
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			if Contrast.lightness(Color3.fromHSV(h, sat, mid)) < target then
				lo = mid
			else
				hi = mid
			end
		end
		result = Color3.fromHSV(h, sat, (lo + hi) / 2)
		if math.abs(Contrast.lightness(result) - target) < 0.02 then
			break
		end
	end
	return result
end

-- Returns the trim colour to SHOW and whether it had to be changed. A trim that already differs from the wall by MIN_GAP is left alone.
function Contrast.fixTrim(wall: Color3, trim: Color3): (Color3, boolean)
	local lw, lt = Contrast.lightness(wall), Contrast.lightness(trim)
	if math.abs(lw - lt) >= Contrast.MIN_GAP then
		return trim, false
	end
	local goLighter = lw < 0.5 -- a dark wall gets a lighter trim, a light wall a darker one
	local target = if goLighter then lw + PUSH else lw - PUSH
	if target > 0.97 or target < 0.03 then -- no room on that side: use the other one
		target = if goLighter then lw - PUSH else lw + PUSH
	end
	return withLightness(trim, math.clamp(target, 0.02, 0.98)), true
end

return Contrast
