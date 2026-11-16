-- Items.luau (ReplicatedStorage.Shared.Config.Items)
-- Purpose: all 22 item definitions (20 MVP + 2 Relics) (docs/02_Economy.md §4, shape from docs/03_Architecture.md §10.1).
-- Owner: Dev 1 (Ace). Depends on: nothing (rarity and category names must match Rarities.luau / Economy.Categories).
-- Recipe step parameters come from the "(...)" notes in docs/02, e.g. "Reassemble (wheel)" -> parts = { "Wheel" }.
-- Only TinRobot has layers / greenZone / flavor because docs/03 §10.1 gives those; Dev 2 tunes the rest.
-- The 15 part names are FINAL MVP decisions (docs/STATUS.md): one socket and one loose part per name (docs/01 §C2).

local Items = {
	-- ===== Tier 1: Starter (12 items) =====
	RubberDuck = {
		id = "RubberDuck", name = "Rubber Duck", tier = 1, rarity = "Common", category = "Toys", baseValue = 12,
		model = "RubberDuck",
		recipe = { { type = "Wipe" }, { type = "Polish" } },
	},
	Teacup = {
		id = "Teacup", name = "Floral Teacup", tier = 1, rarity = "Common", category = "Kitchen", baseValue = 14,
		model = "Teacup",
		recipe = { { type = "Wipe" }, { type = "Polish" } },
	},
	ToyCar = {
		id = "ToyCar", name = "Toy Race Car", tier = 1, rarity = "Common", category = "Toys", baseValue = 16,
		model = "ToyCar",
		recipe = { { type = "Wipe" }, { type = "Reassemble", parts = { "Wheel" } }, { type = "Polish" } },
	},
	DeskLamp = {
		id = "DeskLamp", name = "Desk Lamp", tier = 1, rarity = "Common", category = "Decor", baseValue = 18,
		model = "DeskLamp",
		recipe = { { type = "Wipe" }, { type = "Replace", parts = { "Bulb" } }, { type = "Test", style = "Switch" } },
	},
	AlarmClock = {
		id = "AlarmClock", name = "Alarm Clock", tier = 1, rarity = "Uncommon", category = "Electronics", baseValue = 32,
		model = "AlarmClock",
		recipe = { { type = "Scrape" }, { type = "Reassemble", parts = { "Bell" } }, { type = "Test", style = "Wind" } },
	},
	SnowGlobe = {
		id = "SnowGlobe", name = "Snow Globe", tier = 1, rarity = "Uncommon", category = "Decor", baseValue = 35,
		model = "SnowGlobe",
		recipe = { { type = "Wipe" }, { type = "Polish" }, { type = "Test", style = "Shake" } },
	},
	CassettePlayer = {
		id = "CassettePlayer", name = "Cassette Player", tier = 1, rarity = "Uncommon", category = "Music", baseValue = 38,
		model = "CassettePlayer",
		recipe = { { type = "Wipe" }, { type = "Replace", parts = { "Button" } }, { type = "Test", style = "Play" } },
	},
	MusicBox = {
		id = "MusicBox", name = "Music Box", tier = 1, rarity = "Rare", category = "Music", baseValue = 80,
		model = "MusicBox",
		recipe = {
			{ type = "Scrape" },
			{ type = "Reassemble", parts = { "Dancer" } },
			{ type = "Polish" },
			{ type = "Test", style = "Wind" },
		},
	},
	RetroCamera = {
		id = "RetroCamera", name = "Retro Camera", tier = 1, rarity = "Rare", category = "Electronics", baseValue = 85,
		model = "RetroCamera",
		recipe = {
			{ type = "Wipe" },
			{ type = "Replace", parts = { "Lens" } },
			{ type = "Polish" },
			{ type = "Test", style = "Flash" },
		},
	},
	CopperKettle = {
		id = "CopperKettle", name = "Copper Kettle", tier = 1, rarity = "Epic", category = "Kitchen", baseValue = 170,
		model = "CopperKettle",
		recipe = {
			{ type = "Scrape" },
			{ type = "Reassemble", parts = { "Lid" } },
			{ type = "Polish" },
			{ type = "Test", style = "Whistle" },
		},
	},
	TinRobot = { -- example from docs/03 §10.1 (its part is now "LeftArm")
		id = "TinRobot", name = "Vintage Tin Robot", tier = 1, rarity = "Epic", category = "Toys", baseValue = 180,
		model = "TinRobot",
		flavor = "Wind it up and watch it march!",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape", layers = 3 },
			{ type = "Reassemble", parts = { "LeftArm" } },
			{ type = "Polish" },
			{ type = "Test", style = "Wind", greenZone = 0.25 },
		},
	},
	Gramophone = {
		id = "Gramophone", name = "Antique Gramophone", tier = 1, rarity = "Legendary", category = "Music", baseValue = 450,
		model = "Gramophone",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Replace", parts = { "Horn" } },
			{ type = "Polish" },
			{ type = "Test", style = "Play" },
		},
	},

	-- ===== Tier 2: Flea Market (8 items) =====
	VinylRecord = {
		id = "VinylRecord", name = "Vinyl Record", tier = 2, rarity = "Common", category = "Music", baseValue = 70,
		model = "VinylRecord",
		recipe = { { type = "Wipe" }, { type = "Polish" } },
	},
	EnamelMug = {
		id = "EnamelMug", name = "Enamel Camp Mug", tier = 2, rarity = "Common", category = "Kitchen", baseValue = 75,
		model = "EnamelMug",
		recipe = { { type = "Scrape" }, { type = "Polish" } },
	},
	RotaryPhone = {
		id = "RotaryPhone", name = "Rotary Phone", tier = 2, rarity = "Uncommon", category = "Electronics", baseValue = 170,
		model = "RotaryPhone",
		recipe = { { type = "Wipe" }, { type = "Reassemble", parts = { "Handset" } }, { type = "Test", style = "Ring" } },
	},
	Marionette = {
		id = "Marionette", name = "Wooden Marionette", tier = 2, rarity = "Uncommon", category = "Toys", baseValue = 180,
		model = "Marionette",
		recipe = { { type = "Wipe" }, { type = "Reassemble", parts = { "Leg" } }, { type = "Polish" } },
	},
	PocketWatch = {
		id = "PocketWatch", name = "Pocket Watch", tier = 2, rarity = "Rare", category = "Decor", baseValue = 400,
		model = "PocketWatch",
		recipe = {
			{ type = "Scrape" },
			{ type = "Replace", parts = { "Gear" } },
			{ type = "Polish" },
			{ type = "Test", style = "Tick" },
		},
	},
	TubeRadio = {
		id = "TubeRadio", name = "Tube Radio", tier = 2, rarity = "Rare", category = "Electronics", baseValue = 420,
		model = "TubeRadio",
		recipe = {
			{ type = "Wipe" },
			{ type = "Replace", parts = { "Tube" } },
			{ type = "Polish" },
			{ type = "Test", style = "Tune" },
		},
	},
	ShipInBottle = {
		id = "ShipInBottle", name = "Ship in a Bottle", tier = 2, rarity = "Epic", category = "Decor", baseValue = 900,
		model = "ShipInBottle",
		recipe = {
			{ type = "Wipe" },
			{ type = "Reassemble", parts = { "Mast" } },
			{ type = "Polish" },
			{ type = "Test", style = "Light" },
		},
	},
	Jukebox = {
		id = "Jukebox", name = "Mini Jukebox", tier = 2, rarity = "Legendary", category = "Music", baseValue = 2250,
		model = "Jukebox",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Replace", parts = { "Record" } },
			{ type = "Polish" },
			{ type = "Test", style = "Play" },
		},
	},

	-- ===== Relics (2): the Lost Masterpieces. Special pull only (Economy.RelicChance), never in a crate's odds table =====
	StarlightOrrery = {
		id = "StarlightOrrery", name = "Starlight Orrery", tier = 2, rarity = "Relic", category = "Decor", baseValue = 6000,
		model = "StarlightOrrery",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Reassemble", parts = { "Ring" } },
			{ type = "Polish" },
			{ type = "Test", style = "Wind" },
		},
	},
	ClockworkCarousel = {
		id = "ClockworkCarousel", name = "Clockwork Carousel", tier = 2, rarity = "Relic", category = "Toys", baseValue = 9000,
		model = "ClockworkCarousel",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Replace", parts = { "Horse" } },
			{ type = "Polish" },
			{ type = "Test", style = "Play" },
		},
	},
}

return Items
