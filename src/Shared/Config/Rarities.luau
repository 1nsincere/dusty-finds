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
	-- Relic: above Legendary. NEVER in a crate's odds table (all odds keep Relic = 0): relics come only from the special
	-- pull in ShipmentService.RollItem (Economy.RelicChance), so they stay a surprise and the odds still add up to 100.
	Relic = {
		id = "Relic",
		index = 6,
		xpPerRestore = 400,
		firstFindBonus = { 800, 4000 },
		exhibitPoints = 16,
	},
	-- Mythic and Secret (2026-11-20): above Relic, also special-pull only (Economy.MythicChance / SecretChance),
	-- never in a crate's odds table. Secret is the rarest thing in the game.
	Mythic = {
		id = "Mythic",
		index = 7,
		xpPerRestore = 900,
		firstFindBonus = { 2000, 10000 },
		exhibitPoints = 32,
	},
	Secret = {
		id = "Secret",
		index = 8,
		xpPerRestore = 2000,
		firstFindBonus = { 5000, 25000 },
		exhibitPoints = 64,
	},
}

return Rarities
