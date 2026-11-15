-- Formulas.luau (ReplicatedStorage.Shared.Formulas)
-- Purpose: pure price / quality / XP / rating math from docs/02_Economy.md, used by the server AND by UI previews.
-- Owner: Dev 1 (Ace). Depends on: Config/Economy, Config/Items, Config/Rarities.
-- "Pure" = no side effects, same inputs always give the same output. All numbers come from Config, never hardcoded.
-- Bad input never errors: it is clamped or gives 0 (rules are noted on each function). Prices round to whole dollars.

local Config = script.Parent:WaitForChild("Config")
local Economy = require(Config:WaitForChild("Economy"))
local Items = require(Config:WaitForChild("Items"))

local Formulas = {}

-- A usable number: not nil, not NaN, not infinite. Anything else becomes `fallback`.
local function cleanNumber(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- Rounds to the nearest whole number, with .5 going up. The tiny extra amount stops floating-point error from
-- turning an exact .5 into .4999999 (e.g. 2925 x 0.7 is stored as 2047.4999999999998 but should round to 2048).
local function round(x: number): number
	return math.floor(x + 0.5 + 1e-9)
end

-- Stars are whole numbers 1-3. Missing/invalid -> 1, decimals round down, out of range is clamped.
local function cleanStars(stars: any): number
	return math.clamp(math.floor(cleanNumber(stars, 1)), 1, #Economy.QualityMult)
end

-- baseValue x qualityMult x variantMult for one item. Returns 0 if the item id is unknown.
local function baseTimesQualityTimesVariant(itemId: any, stars: any, golden: any): number
	local item = type(itemId) == "string" and Items[itemId] or nil
	if item == nil then
		return 0
	end
	local variantMult = if golden == true then Economy.GoldenValueMult else 1
	return item.baseValue * Economy.QualityMult[cleanStars(stars)] * variantMult
end

-- What a customer pays before any tip: baseValue x qualityMult x variantMult x wishMult.
-- wishMatch = true when the item's category matches the customer's wish (x1.25).
function Formulas.sellPrice(itemId: string, stars: number, golden: boolean?, wishMatch: boolean?): number
	local wishMult = if wishMatch == true then Economy.WishMult else 1
	return round(baseTimesQualityTimesVariant(itemId, stars, golden) * wishMult)
end

-- Quick Sell at the counter: 70% of baseValue x qualityMult x variantMult. No wish bonus, no tip.
function Formulas.quickSellPrice(itemId: string, stars: number, golden: boolean?): number
	return round(baseTimesQualityTimesVariant(itemId, stars, golden) * Economy.QuickSellFraction)
end

-- Final quality: average step score + tool bonus, capped at 100, then >=90 -> 3 stars, >=70 -> 2 stars, else 1.
-- `averageScore` is clamped to 0-100 (missing = 0); `toolBonus` is clamped to 0-MaxToolQualityBonus (missing = 0).
function Formulas.qualityStars(averageScore: number, toolBonus: number?): number
	local score = math.clamp(cleanNumber(averageScore, 0), 0, 100)
	local bonus = math.clamp(cleanNumber(toolBonus, 0), 0, Economy.MaxToolQualityBonus)
	local final = math.min(100, score + bonus)
	if final >= Economy.QualityThreeStarMin then
		return 3
	elseif final >= Economy.QualityTwoStarMin then
		return 2
	end
	return 1
end

-- XP needed to go from `level` to level + 1: round(XpBase x level^XpExponent).
-- Level below 1 or missing counts as 1. At or above MaxLevel nothing is needed or possible: returns math.huge.
function Formulas.xpToNext(level: number): number
	local lv = math.max(1, math.floor(cleanNumber(level, 1)))
	if lv >= Economy.MaxLevel then
		return math.huge
	end
	return round(Economy.XpBase * lv ^ Economy.XpExponent)
end

-- Shop rating stars (1-5) from rating points (decor + expansions + exhibits).
-- Negative or missing points count as 0, so the result is never below 1.
function Formulas.ratingStars(points: number): number
	local p = math.max(0, cleanNumber(points, 0))
	local stars = 1
	for star, minPoints in Economy.RatingStarMinPoints do
		if p >= minPoints and star > stars then
			stars = star
		end
	end
	return stars
end

return Formulas
