-- Crates.luau (ReplicatedStorage.Shared.Config.Crates)
-- Purpose: shipment crates: price, unlock level, how many items, rarity odds (docs/02_Economy.md §3).
-- Owner: Dev 1 (Ace). Depends on: nothing (rarity names must match Rarities.luau).
-- `tier` says which item tier the crate draws from. Odds are percentages and each crate adds up to exactly 100.
-- Antique Dealer and Estate Sale (2026-11-25) draw from tier 2 for now: there are no tier 3 items yet.
-- boxModel = the model in ReplicatedStorage.Assets.Boxes (built by tools/blender/crates.py, asset 115623994024952).

local Crates = {
	FreeDelivery = {
		id = "FreeDelivery",
		name = "Free Delivery",
		boxModel = "CrateFree", -- ReplicatedStorage.Assets.Boxes.CrateFree (2026-11-25; the plain "Box" stays as the fallback)
		price = 0,
		requiredLevel = 1,
		itemCount = 2, -- was 1 (2026-11-20: more items per box)
		tier = 1,
		odds = { Common = 75, Uncommon = 20, Rare = 5, Epic = 0, Legendary = 0, Relic = 0, Mythic = 0, Secret = 0 },
	},
	Starter = {
		id = "Starter",
		name = "Starter Crate",
		boxModel = "CrateStarter",
		price = 50,
		requiredLevel = 1,
		itemCount = 5, -- was 3
		tier = 1,
		odds = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1, Relic = 0, Mythic = 0, Secret = 0 },
	},
	-- Yard Sale (Sean, 2026-11-25): between Starter and Flea Market. Same tier 1 items as Starter, fewer Commons, so each
	-- inventory slot is worth more. Odds ladder (Sean, 2026-11-25): a pricier crate is never worse on Rare / Epic / Legendary,
	-- so Yard Sale sits between Starter and Flea Market (was 45/30/16/7/2, which beat Flea Market). ~2.4x the price.
	YardSale = {
		id = "YardSale",
		name = "Yard Sale Crate",
		boxModel = "CrateYardSale",
		price = 90,
		requiredLevel = 3,
		itemCount = 5,
		tier = 1,
		odds = { Common = 54, Uncommon = 28, Rare = 12, Epic = 4, Legendary = 2, Relic = 0, Mythic = 0, Secret = 0 },
	},
	FleaMarket = {
		id = "FleaMarket",
		name = "Flea Market Crate",
		boxModel = "CrateFlea",
		price = 300,
		requiredLevel = 5,
		itemCount = 6, -- was 3
		tier = 2,
		odds = { Common = 53, Uncommon = 28, Rare = 12, Epic = 5, Legendary = 2, Relic = 0, Mythic = 0, Secret = 0 },
	},
	-- Antique Dealer + Estate Sale (Sean, 2026-11-25): tier 2 items (no tier 3 items exist yet) with better odds and more
	-- special pulls (Economy RelicChance / MythicChance / SecretChance / TimeCapsuleChance). Expected value ~$2,590 and
	-- ~$4,660 at 2 stars (~3.2x / ~3.1x). Point them at tier 3 when Dev 2 adds those items.
	AntiqueDealer = {
		id = "AntiqueDealer",
		name = "Antique Dealer Crate",
		boxModel = "CrateAntique",
		price = 800,
		requiredLevel = 10,
		itemCount = 6,
		tier = 2,
		odds = { Common = 35, Uncommon = 30, Rare = 20, Epic = 11, Legendary = 4, Relic = 0, Mythic = 0, Secret = 0 },
	},
	EstateSale = {
		id = "EstateSale",
		name = "Estate Sale Crate",
		boxModel = "CrateEstate",
		price = 11000, -- Sean 2026-11-25 (was 1,500): a premium chase crate; expected value ~$4,660, so it pays back less than it costs on average
		requiredLevel = 13, -- Sean 2026-11-25 (was 18)
		itemCount = 6,
		tier = 2,
		odds = { Common = 20, Uncommon = 25, Rare = 27, Epic = 18, Legendary = 10, Relic = 0, Mythic = 0, Secret = 0 },
	},
}

return Crates
