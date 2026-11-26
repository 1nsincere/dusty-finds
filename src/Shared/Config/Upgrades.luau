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
		comingSoon = true, -- 2026-11-26: the old greybox decor waits for its real models
		id = "PottedPlants", name = "Potted Plants", tab = "Decor",
		maxLevel = 2,
		costs = { 80, 80 },
		requiredLevel = { 1, 1 },
		effect = { ratingPoints = { 1, 2 } }, -- total points owned at each level
		decorSlots = { "PottedPlant1", "PottedPlant2" }, -- plot DecorSlots shown at each level (slot i shows at level >= i)
		description = "A little green for the shop",
	},
	Rug = {
		comingSoon = true, -- 2026-11-26: the old greybox decor waits for its real models (the Cozy Living set replaces the rug and plants)
		id = "Rug", name = "Rug", tab = "Decor",
		maxLevel = 1, costs = { 150 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 2 } },
		decorSlots = { "Rug" },
		description = "Cozy floor rug",
	},
	WallPosters = {
		comingSoon = true, -- 2026-11-26: the old greybox decor waits for its real models (the Cozy Living set replaces the rug and plants)
		id = "WallPosters", name = "Wall Posters", tab = "Decor",
		maxLevel = 1, costs = { 200 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 2 } },
		decorSlots = { "WallPosters" },
		description = "Posters for the walls",
	},
	PendantLamps = {
		comingSoon = true, -- 2026-11-26: the old greybox decor waits for its real models (the Cozy Living set replaces the rug and plants)
		id = "PendantLamps", name = "Pendant Lamps", tab = "Decor",
		maxLevel = 1, costs = { 400 }, requiredLevel = { 1 },
		effect = { ratingPoints = { 3 } },
		decorSlots = { "PendantLamps" },
		description = "Warm hanging lights",
	},
	NeonSign = { -- the doc's "Neon RE:STORE Sign"; the in-game sign text is Dev 3's call
		comingSoon = true,
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

	-- ===== Cozy Living decor (2026-11-26, Ace + Claude): the first real decor set. SOLD THROUGH THE DECOR STOCK: `rarity` decides how often a piece is in stock (Shared/DecorStock, Config/Stock.RarityChance): the nicer, the rarer. One-time purchases, each shows a model in a FIXED spot of
	-- the shop (Plot.DecorSlots.<slot>, built from ReplicatedStorage.Assets.Decor.<template>); parts named Accent / Trim take the shop's paint
	-- (PlotTargets). Cosmetic only: ratingPoints add to the shop rating like the older decor. Models: tools/blender/decor_cozy_v2.py.
	CozyRug = {
		id = "CozyRug", name = "Banig Rug", tab = "Decor", rarity = "Common", room = "CozyLiving",
		maxLevel = 1, costs = { 400 }, requiredLevel = { 1 }, effect = { ratingPoints = { 2 } },
		decorSlots = { "CozyRug" }, description = "A woven banig mat in your shop's colours",
	},
	CozyPlant = {
		id = "CozyPlant", name = "Basket Plant", tab = "Decor", rarity = "Common", room = "CozyLiving",
		maxLevel = 1, costs = { 300 }, requiredLevel = { 1 }, effect = { ratingPoints = { 1 } },
		decorSlots = { "CozyPlant" }, description = "A tall leafy plant in a woven basket",
	},
	CozyLamp = {
		id = "CozyLamp", name = "Capiz Lamp", tab = "Decor", rarity = "Uncommon", room = "CozyLiving",
		maxLevel = 1, costs = { 600 }, requiredLevel = { 1 }, effect = { ratingPoints = { 2 } },
		decorSlots = { "CozyLamp" }, description = "A floor lamp with a shade of capiz shell tiles",
	},
	CozyTeaTable = {
		id = "CozyTeaTable", name = "Tea Table", tab = "Decor", rarity = "Uncommon", room = "CozyLiving",
		maxLevel = 1, costs = { 500 }, requiredLevel = { 1 }, effect = { ratingPoints = { 1 } },
		decorSlots = { "CozyTeaTable" }, description = "A turned side table with a kettle and two cups",
	},
	CozyTable = {
		id = "CozyTable", name = "Tinikling Table", tab = "Decor", rarity = "Rare", room = "CozyLiving",
		maxLevel = 1, costs = { 900 }, requiredLevel = { 1 }, effect = { ratingPoints = { 2 } },
		decorSlots = { "CozyTable" }, description = "A low table on crossed bamboo poles, for the tinikling dance",
	},
	CozyChair = {
		id = "CozyChair", name = "Peacock Chair", tab = "Decor", rarity = "Rare", room = "CozyLiving",
		maxLevel = 1, costs = { 1200 }, requiredLevel = { 1 }, effect = { ratingPoints = { 3 } },
		decorSlots = { "CozyChair" }, description = "A rattan peacock chair with a sleepy cat",
	},
	CozyBookcase = {
		id = "CozyBookcase", name = "Arch Bookcase", tab = "Decor", rarity = "Epic", room = "CozyLiving",
		maxLevel = 1, costs = { 1500 }, requiredLevel = { 1 }, effect = { ratingPoints = { 3 } },
		decorSlots = { "CozyBookcase" }, description = "Books, a globe, a ladder and a jar of fireflies",
	},
	CozyLoveseat = {
		id = "CozyLoveseat", name = "Peacock Loveseat", tab = "Decor", rarity = "Epic", room = "CozyLiving",
		maxLevel = 1, costs = { 1800 }, requiredLevel = { 1 }, effect = { ratingPoints = { 4 } },
		decorSlots = { "CozyLoveseat" }, description = "A rattan loveseat with a big fan back",
	},

	-- ===== Kitchen Nook decor (2026-11-26, Ace + Claude): the second set, sold at the Kitchen Nook counter in the market (Config/DecorRooms).
	-- Same rules as Cozy Living: stock rarity, parts named Accent / Trim follow the shop's paint, placed in fixed spots (Plot.DecorSlots.<slot>).
	-- Models: tools/blender/decor_kitchen.py (asset 79976025172957).
	KitchenFruit = {
		id = "KitchenFruit", name = "Fruit Stand", tab = "Decor", rarity = "Common", room = "KitchenNook",
		maxLevel = 1, costs = { 350 }, requiredLevel = { 1 }, effect = { ratingPoints = { 1 } },
		decorSlots = { "KitchenFruit" }, description = "A basket of mangoes, kalamansi and bananas",
	},
	KitchenBanga = {
		id = "KitchenBanga", name = "Banga Water Jar", tab = "Decor", rarity = "Common", room = "KitchenNook",
		maxLevel = 1, costs = { 400 }, requiredLevel = { 1 }, effect = { ratingPoints = { 1 } },
		decorSlots = { "KitchenBanga" }, description = "A clay water jar with a coconut dipper",
	},
	KitchenJarShelf = {
		id = "KitchenJarShelf", name = "Jar Shelf", tab = "Decor", rarity = "Uncommon", room = "KitchenNook",
		maxLevel = 1, costs = { 700 }, requiredLevel = { 1 }, effect = { ratingPoints = { 2 } },
		decorSlots = { "KitchenJarShelf" }, description = "Candy and preserves, and a jar of fireflies",
	},
	KitchenPotRack = {
		id = "KitchenPotRack", name = "Pot Rack", tab = "Decor", rarity = "Uncommon", room = "KitchenNook",
		maxLevel = 1, costs = { 600 }, requiredLevel = { 1 }, effect = { ratingPoints = { 2 } },
		decorSlots = { "KitchenPotRack" }, description = "Pots, a kawali, garlic and dried chillies",
	},
	KitchenStove = {
		id = "KitchenStove", name = "Clay Stove", tab = "Decor", rarity = "Rare", room = "KitchenNook",
		maxLevel = 1, costs = { 1100 }, requiredLevel = { 1 }, effect = { ratingPoints = { 3 } },
		decorSlots = { "KitchenStove" }, description = "A kalan with glowing embers and a clay pot",
	},
	KitchenAparador = {
		id = "KitchenAparador", name = "Aparador", tab = "Decor", rarity = "Rare", room = "KitchenNook",
		maxLevel = 1, costs = { 1400 }, requiredLevel = { 1 }, effect = { ratingPoints = { 3 } },
		decorSlots = { "KitchenAparador" }, description = "A louvered cabinet with a capiz transom",
	},
	KitchenDining = {
		id = "KitchenDining", name = "Dining Set", tab = "Decor", rarity = "Epic", room = "KitchenNook",
		maxLevel = 1, costs = { 1900 }, requiredLevel = { 1 }, effect = { ratingPoints = { 4 } },
		decorSlots = { "KitchenDining" }, description = "A narra table with a banig runner and woven stools",
	},
	KitchenCart = {
		id = "KitchenCart", name = "Pandesal Cart", tab = "Decor", rarity = "Epic", room = "KitchenNook",
		maxLevel = 1, costs = { 2200 }, requiredLevel = { 1 }, effect = { ratingPoints = { 4 } },
		decorSlots = { "KitchenCart" }, description = "A little bakery cart with a striped awning",
	},

	-- ===== Expansions =====
	-- Order (Sean, 2026-11-24): the Back Room is the first expansion (pedestals 1-4 move into it), the second floor
	-- (Showroom) comes later with 6 pedestals of its own.
	BackRoom = {
		id = "BackRoom", name = "Back Room", tab = "Expansions",
		maxLevel = 1, costs = { 6500 }, requiredLevel = { 4 }, -- $6,500 (Sean, 2026-11-24)
		effect = { expansion = "BackRoom", ratingPoints = 3 }, -- the second workbench was removed (2026-11-24)
		description = "A big room behind your shop for your exhibits",
	},
	Showroom = {
		id = "Showroom", name = "Showroom", tab = "Expansions",
		maxLevel = 1, costs = { 20000 }, requiredLevel = { 10 }, -- $20,000 (Sean, 2026-11-24)
		effect = {
			expansion = "Showroom",
			ratingPoints = 8,
			premiumDisplaySlots = 6,
			exhibitPedestals = 6, -- 6 pedestals upstairs (5-10); pedestals 1-4 stay downstairs / in the Back Room. (Removed and put back on 2026-11-26: the ground floor is tight, so the second floor holds exhibits.)
			maxCustomers = 5,
		},
		description = "A second floor gallery: 6 more exhibit pedestals and more customers",
	},
	-- Second floor above the Back Room (Ace, 2026-11-26): walk through from the Showroom gallery. The Showroom's arched gallery and its
	-- six pedestals move into it, and it brings 4 NEW pedestals of its own (11-14). The 4 only count together with the Showroom
	-- (PlotService.slotCounts). The price and rating points are a first guess, tune them with the economy sim.
	UpperBackRoom = {
		comingSoon = true, -- 2026-11-26 (Ace): waits for the decor spots upstairs (it becomes the decor floor); remove this line to sell it
		id = "UpperBackRoom", name = "Upper Back Room", tab = "Expansions",
		maxLevel = 1, costs = { 35000 }, requiredLevel = { 12 },
		requires = "BackRoom", -- it is built over the Back Room (reach it from the Showroom upstairs)
		effect = { expansion = "UpperBackRoom", ratingPoints = 6, exhibitPedestals = 0 }, -- 2026-11-26 (Ace): was 4 (pedestals 11-14); upstairs is kept free for decor
		description = "A gallery above the Back Room: a higher shop rating (room for decor; needs the Showroom to reach it)",
	},
}

return Upgrades
