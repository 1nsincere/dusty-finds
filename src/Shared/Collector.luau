-- Collector.luau (ReplicatedStorage.Shared.Collector)
-- Purpose: the collector score formula and tier lookup (docs/12 Stage 4). Pure functions: the server uses them to set each
-- player's tier (CollectorService); tests and any UI can use them too. Numbers live in Config.Collector.
-- Owner: Dev 1 (Ace). Depends on: Config.Collector, Config.Items, Config.Rarities (names only).

local Config = script.Parent:WaitForChild("Config")
local Settings = require(Config:WaitForChild("Collector"))
local Items = require(Config:WaitForChild("Items"))

local Collector = {}

-- collection = data.collection ({ [itemId] = { found, bestStars, golden } }); ratingStars = 0..5. Unknown items count 0.
function Collector.score(collection: any, ratingStars: number?): number
	local total = 0
	if type(collection) == "table" then
		for itemId, entry in collection do
			local def = Items[itemId]
			local points = def and Settings.RarityPoints[def.rarity]
			if points and type(entry) == "table" then
				local stars = if type(entry.bestStars) == "number" then math.clamp(entry.bestStars, 0, 3) else 0
				local value = points * (1 + Settings.StarBonus * stars)
				if entry.golden == true then
					value *= Settings.GoldenMult
				end
				total += value
			end
		end
	end
	local stars = if type(ratingStars) == "number" then math.clamp(ratingStars, 0, 5) else 0
	total += stars * Settings.RatingStarPoints
	return math.floor(total + 0.5)
end

-- Returns the tier table, its number (1 = lowest) and the points still missing for the next tier (nil at the top).
function Collector.tier(score: number): (any, number, number?)
	local index = 1
	for i, tier in Settings.TIERS do
		if score >= tier.min then
			index = i
		end
	end
	local nextTier = Settings.TIERS[index + 1]
	return Settings.TIERS[index], index, if nextTier then nextTier.min - score else nil
end

return Collector
