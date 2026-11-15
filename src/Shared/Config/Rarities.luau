-- Rarities.luau (ReplicatedStorage.Shared.Config.Rarities)
-- Purpose: per-rarity numbers from docs/02_Economy.md §2.
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- index orders the rarities (1 = lowest). firstFindBonus is cash for the first time an item is found, by item tier.
-- Display colors are NOT here: the docs give none, so Dev 3 picks them with the UI.

local Rarities = {
	Common = {
		id = "Common",
		index = 1,
		xpPerRestore = 10,
		firstFindBonus = { 10, 50 }, -- { Tier 1, Tier 2 }
		exhibitPoints = 0,
	},
	Uncommon = {
		id = "Uncommon",
		index = 2,
		xpPerRestore = 20,
		firstFindBonus = { 25, 125 },
		exhibitPoints = 1,
	},
	Rare = {
		id = "Rare",
		index = 3,
		xpPerRestore = 40,
		firstFindBonus = { 60, 300 },
		exhibitPoints = 2,
	},
	Epic = {
		id = "Epic",
		index = 4,
		xpPerRestore = 80,
		firstFindBonus = { 120, 600 },
		exhibitPoints = 4,
	},
	Legendary = {
		id = "Legendary",
		index = 5,
		xpPerRestore = 160,
		firstFindBonus = { 300, 1500 },
		exhibitPoints = 8,
	},
}

return Rarities
