-- Customers.luau (ReplicatedStorage.Shared.Config.Customers)
-- Purpose: the 4 MVP customer types (docs/01_GameDesign.md B9; shape from docs/03_Architecture.md §10.2).
-- Owner: Dev 1 (Ace). Depends on: nothing (prefersMinRarity must match Rarities.luau).
-- Per Ace's decision: Kid, Grandpa and Teen are neutral (no rarity preference, no tip bonus, equal weights).
-- Only the Collector differs (docs/03 §10.2: prefers Rare+, tipBonus 0.05, weight 15). Dev 3 may tune later.

local Customers = {
	Kid = {
		id = "Kid",
		model = "Kid", -- ServerStorage.NPCs.Kid
		walkSpeed = 10,
		tipBonus = 0,
		weight = 25,
	},
	Grandpa = {
		id = "Grandpa",
		model = "Grandpa",
		walkSpeed = 10,
		tipBonus = 0,
		weight = 25,
	},
	Collector = { -- exact example from docs/03 §10.2
		id = "Collector",
		model = "Collector",
		walkSpeed = 10,
		prefersMinRarity = "Rare", -- picks Rare+ items if any are displayed
		tipBonus = 0.05,
		weight = 15,
	},
	Teen = {
		id = "Teen",
		model = "Teen",
		walkSpeed = 10,
		tipBonus = 0,
		weight = 25,
	},
}

return Customers
