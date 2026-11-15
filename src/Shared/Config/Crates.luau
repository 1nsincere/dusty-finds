-- Crates.luau (ReplicatedStorage.Shared.Config.Crates)
-- Purpose: shipment crates: price, unlock level, how many items, rarity odds (docs/02_Economy.md §3).
-- Owner: Dev 1 (Ace). Depends on: nothing (rarity names must match Rarities.luau).
-- `tier` says which item tier the crate draws from. Odds are percentages and each crate adds up to exactly 100.
-- Antique Dealer (Update 1) and Estate Sale (Update 2) crates are not here: the MVP has no Tier 3+ items to put in them.

local Crates = {
	FreeDelivery = {
		id = "FreeDelivery",
		name = "Free Delivery",
		boxModel = "Box", -- ReplicatedStorage.Assets.Boxes.Box (docs/03 §2)
		price = 0,
		requiredLevel = 1,
		itemCount = 1,
		tier = 1,
		odds = { Common = 75, Uncommon = 20, Rare = 5, Epic = 0, Legendary = 0 },
	},
	Starter = {
		id = "Starter",
		name = "Starter Crate",
		boxModel = "CrateStarter",
		price = 50,
		requiredLevel = 1,
		itemCount = 3,
		tier = 1,
		odds = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 },
	},
	FleaMarket = {
		id = "FleaMarket",
		name = "Flea Market Crate",
		boxModel = "CrateFlea",
		price = 300,
		requiredLevel = 5,
		itemCount = 3,
		tier = 2,
		odds = { Common = 55, Uncommon = 27, Rare = 12, Epic = 5, Legendary = 1 },
	},
}

return Crates
