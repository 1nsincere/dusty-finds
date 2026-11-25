-- Collector.luau (ReplicatedStorage.Shared.Config.Collector)
-- Purpose: the COLLECTOR SCORE and the aura tiers (docs/12 Stage 4). The score says how good a collector you are; it is worked
-- out from data we already save (Collection Book entries + shop rating), so nothing new is saved and nothing can be bought:
-- it is earned only. Higher tier = a nicer aura round your avatar that every player sees.
-- Owner: Dev 1 (Ace): tune freely. Read by: Shared.Collector (the formula), CollectorService (server), AuraController (client).
--
-- score = sum over Collection Book entries of  rarityPoints x (1 + StarBonus x bestStars) x (golden ? GoldenMult : 1)
--         + shop rating stars x RatingStarPoints
-- With the 30 items today the top is about 1,100; the tiers below are spread over that.

local Collector = {
	-- points for finding an item of that rarity (found = in the Collection Book; stars come from restoring it)
	RarityPoints = {
		Common = 1,
		Uncommon = 2,
		Rare = 4,
		Epic = 8,
		Legendary = 16,
		Relic = 24,
		Mythic = 32,
		Secret = 40,
	},
	StarBonus = 0.5, -- each best-restore star adds this fraction of the item's points (3 stars = x2.5)
	GoldenMult = 1.5, -- a golden copy counts 1.5x
	RatingStarPoints = 20, -- per shop rating star (0..5)

	-- tiers, lowest first. `min` = score needed. Aura: colour, how many sparkles per second, light brightness.
	TIERS = {
		{ id = "Dusty", name = "Dusty Collector", min = 0 },
		{ id = "Polished", name = "Polished Collector", min = 40, color = Color3.fromRGB(205, 214, 224), rate = 4, light = 0 },
		{ id = "Brass", name = "Brass Collector", min = 160, color = Color3.fromRGB(214, 168, 86), rate = 7, light = 0.4 },
		{ id = "Gilded", name = "Gilded Collector", min = 420, color = Color3.fromRGB(255, 208, 92), rate = 11, light = 0.8 },
		{ id = "Radiant", name = "Radiant Collector", min = 800, color = Color3.fromRGB(255, 160, 226), rate = 16, light = 1.2 },
	},

	-- the aura only draws on players within this many studs of you (phones: fewer particles on screen)
	AuraDrawDistance = 80,
}

return Collector
