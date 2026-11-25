-- Customers.luau (ReplicatedStorage.Shared.Config.Customers)
-- Purpose: the 4 MVP customer types (docs/01_GameDesign.md B9; shape from docs/03_Architecture.md §10.2).
-- Owner: Dev 1 (Ace). Depends on: nothing (prefersMinRarity must match Rarities.luau).
-- Personalities (2026-11-25, so shopping is never the same twice): every type has
--   haggleChance (0-1) + haggleDiscount { min, max }: how often it asks for a discount at the till, and how much (fractions of the price)
--   patienceMult: x Economy.QueuePatienceSeconds before it gives up waiting at the till
--   browseMult: x how long / how many shelves it looks at before choosing
--   buyBonus: added to the chance of buying the item it looked at (impulse buyers +, careful shoppers -)
-- Services loop over every entry of this table (weights): keep only customer types here, never other data.

local Customers = {
	Kid = { -- rushes in, impatient, buys on impulse, never haggles
		id = "Kid",
		model = "Kid", -- ServerStorage.NPCs.Kid
		walkSpeed = 13,
		tipBonus = 0,
		weight = 25,
		haggleChance = 0,
		patienceMult = 0.6,
		browseMult = 0.7,
		buyBonus = 0.08,
	},
	Grandpa = { -- slow window shopper, patient, a careful buyer who likes a bargain
		id = "Grandpa",
		model = "Grandpa",
		walkSpeed = 8,
		tipBonus = 0,
		weight = 25,
		haggleChance = 0.35,
		haggleDiscount = { 0.10, 0.15 },
		patienceMult = 1.5,
		browseMult = 1.6,
		buyBonus = -0.05,
	},
	Collector = { -- exact example from docs/03 §10.2: knows what it wants, pays well
		id = "Collector",
		model = "Collector",
		walkSpeed = 10,
		prefersMinRarity = "Rare", -- picks Rare+ items if any are displayed
		tipBonus = 0.05,
		weight = 15,
		haggleChance = 0.10,
		haggleDiscount = { 0.05, 0.10 },
		patienceMult = 1.0,
		browseMult = 1.0,
		buyBonus = 0,
	},
	Teen = { -- the haggler
		id = "Teen",
		model = "Teen",
		walkSpeed = 11,
		tipBonus = 0,
		weight = 25,
		haggleChance = 0.5,
		haggleDiscount = { 0.10, 0.20 },
		patienceMult = 0.8,
		browseMult = 1.0,
		buyBonus = 0,
	},
}

return Customers
