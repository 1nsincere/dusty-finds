-- Upgrades.luau (ReplicatedStorage.Shared.Config.Upgrades)
-- Purpose: tools, shop upgrades, decor and expansions (docs/02_Economy.md §6; shape from docs/03 §10.3).
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- costs[i] and requiredLevel[i] belong to level i. effect arrays are indexed by the level owned.
-- Choices the docs leave open are written in docs/WHILE_AWAY.md (decor unlock levels, effect field names, tool speed steps).

local Upgrades = {
	-- ===== Tools =====
	CleaningBrush = {
		id = "CleaningBrush", name = "Cleaning Brush", tab = "Tools",
		maxLevel = 3,
		costs = { 150, 1500, 8000 },
		requiredLevel = { 1, 5, 10 },
		effect = { wipeSpeedMult = { 1.25, 1.5, 1.75 }, scrapeSpeedMult = { 1.25, 1.5, 1.75 } }, -- "Wipe/Scrape +25% per level"
		description = "Scrub %d%% faster",
	},
	RepairToolkit = {
		id = "RepairToolkit", name = "Repair Toolkit", tab = "Tools",
		maxLevel = 3,
		costs = { 250, 2000, 9000 },
		requiredLevel = { 2, 6, 11 },
		-- L1 hover highlight, L2 correct part glows in Replace, L3 +5 quality
		effect = {
			hoverHighlight = { true, true, true },
			replaceGlow = { false, true, true },
			qualityBonus = { 0, 0, 5 },
		},
		description = "Helpful repair tools",
	},
	Polisher = {
		id = "Polisher", name = "Polisher", tab = "Tools",
		maxLevel = 3,
		costs = { 200, 1800, 8500 },
		requiredLevel = { 2, 5, 10 },
		effect = { polishSpeedMult = { 1.3, 1.6, 1.9 }, qualityBonus = { 0, 0, 5 } }, -- "+30% speed"; L3 +5 quality
		description = "Polish %d%% faster",
	},

	-- ===== Shop =====
	DisplayShelves = {
		id = "DisplayShelves", name = "Display Shelves", tab = "Shop",
		maxLevel = 3,
		costs = { 120, 900, 4000 },
		requiredLevel = { 1, 3, 7 },
		effect = { displaySlots = { 6, 9, 12 } }, -- +3 slots each level, from the starting 3 up to 12
		description = "More display slots",
	},
	StorageRacks = {
		id = "StorageRacks", name = "Storage Racks", tab = "Shop",
		maxLevel = 3,
		costs = { 100, 1000, 5000 },
		requiredLevel = { 1, 4, 8 },
		effect = { inventoryCapacity = { 16, 24, 40 } }, -- 8 -> 16 -> 24 -> 40
		description = "More inventory space",
	},
	ShopSign = {
		id = "ShopSign", name = "Shop Sign", tab = "Shop",
		maxLevel = 3,
		costs = { 300, 2500, 12000 },
		requiredLevel = { 2, 6, 12 },
		effect = { signLevel = { 1, 2, 3 } }, -- customer interval is x0.9 per sign level (Economy.CustomerSpawnSignFactor)
		description = "Customers arrive 10% faster per level",
	},

	-- ===== Decor (one-time purchases in fixed slots; ratingPoints add to the shop rating) =====
	PottedPlants = { -- two plants, $80 each, 1 point each; level 1 = first plant, level 2 = second
		id = "PottedPlants", name = "Potted Plants", tab = "Decor",
		maxLevel = 2,
		costs = { 80, 80 },
		requiredLevel = { 1, 1 },
		effect = { ratingPoints = { 1, 2 } }, -- total points owned at each level
		decorSlots = { "PottedPlant1", "PottedPlant2" }, -- plot DecorSlots shown at each level (slot i shows at level >= i)
		description = "A little green for the shop",
	},
	Rug = {
		id = "Rug", name = "Rug", tab = "Decor",
		maxLevel = 1, costs = { 150 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 2 } },
		decorSlots = { "Rug" },
		description = "Cozy floor rug",
	},
	WallPosters = {
		id = "WallPosters", name = "Wall Posters", tab = "Decor",
		maxLevel = 1, costs = { 200 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 2 } },
		decorSlots = { "WallPosters" },
		description = "Posters for the walls",
	},
	PendantLamps = {
		id = "PendantLamps", name = "Pendant Lamps", tab = "Decor",
		maxLevel = 1, costs = { 400 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 3 } },
		decorSlots = { "PendantLamps" },
		description = "Warm hanging lights",
	},
	NeonSign = { -- the doc's "Neon RE:STORE Sign"; the in-game sign text is Dev 3's call
		id = "NeonSign", name = "Neon Sign", tab = "Decor",
		maxLevel = 1, costs = { 1500 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 5 } },
		decorSlots = { "NeonSign" },
		description = "A glowing neon sign",
	},
	FishTank = {
		id = "FishTank", name = "Fish Tank", tab = "Decor",
		maxLevel = 1, costs = { 3000 }, requiredLevel = { 1 }, -- all decor unlocks at Lv 1 (Ace's decision)
		requires = "BackRoom", -- but you must own the Back Room first (it has the Fish Tank slot)
		decorSlots = { "FishTank" }, -- shown by PlotService from the Back Room template (ServerStorage.Expansions)
		effect = { ratingPoints = { 6 } },
		description = "Fish for the Back Room",
	},
	Fountain = {
		id = "Fountain", name = "Fountain", tab = "Decor",
		maxLevel = 1, costs = { 10000 }, requiredLevel = { 1 }, -- all decor unlocks at Lv 1 (Ace's decision)
		requires = "Showroom", -- but you must own the Showroom first (it has the Fountain slot)
		decorSlots = { "Fountain" }, -- shown by PlotService from the Showroom template (ServerStorage.Expansions)
		effect = { ratingPoints = { 10 } },
		description = "A fountain for the Showroom",
	},

	-- ===== Expansions =====
	-- Order changed 2026-11-24 (Sean): the second floor (Showroom) is the FIRST expansion, the Back Room comes later.
	BackRoom = {
		id = "BackRoom", name = "Back Room", tab = "Expansions",
		maxLevel = 1, costs = { 20000 }, requiredLevel = { 10 }, -- was $2,500 at Lv 4
		effect = { expansion = "BackRoom", ratingPoints = 3 }, -- the second workbench was removed (2026-11-24)
		description = "A big extra room behind your shop",
	},
	Showroom = {
		id = "Showroom", name = "Showroom", tab = "Expansions",
		maxLevel = 1, costs = { 9000 }, requiredLevel = { 4 }, -- was $20,000 at Lv 10
		effect = {
			expansion = "Showroom",
			ratingPoints = 8,
			premiumDisplaySlots = 6,
			-- 6 more pedestals upstairs; pedestals 1-4 (Economy.StartingExhibitPedestals) move up with them: 10 in the gallery
			exhibitPedestals = 6,
			maxCustomers = 5,
		},
		description = "A second floor gallery: 6 more exhibit pedestals and more customers",
	},
}

return Upgrades
