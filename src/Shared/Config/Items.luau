-- Items.luau (ReplicatedStorage.Shared.Config.Items)
-- Purpose: all 26 item definitions (24 + 2 Relics; see the item-mix comment) (docs/02_Economy.md §4, shape from docs/03_Architecture.md §10.1).
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
	CopperKettle = {
		id = "CopperKettle", name = "The Brass Baron Kettle", tier = 1, rarity = "Epic", category = "Kitchen", baseValue = 170,
		model = "CopperKettle",
		recipe = {
			{ type = "Scrape" },
			{ type = "Reassemble", parts = { "Lid" } },
			{ type = "Polish" },
			{ type = "Test", style = "Whistle" },
		},
	},
	TinRobot = { -- example from docs/03 §10.1 (its part is now "LeftArm")
		id = "TinRobot", name = "Sir Clank, the Tin Robot", tier = 1, rarity = "Epic", category = "Toys", baseValue = 180,
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
		id = "Gramophone", name = "The Silver-Tongue Gramophone", tier = 1, rarity = "Legendary", category = "Music", baseValue = 450,
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
	Jukebox = {
		id = "Jukebox", name = "The Midnight Neon Jukebox", tier = 2, rarity = "Legendary", category = "Music", baseValue = 2250,
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

	-- ===== Item mix (Ace's decision, 2026-11-16): new items replace the hardest builds. Names for Epic and Legendary are proper names. =====
	-- Tier 1 additions
	SpinningTop = {
		id = "SpinningTop", name = "Spinning Top", tier = 1, rarity = "Common", category = "Toys", baseValue = 15,
		model = "SpinningTop",
		recipe = { { type = "Wipe" }, { type = "Polish" }, { type = "Test", style = "Wind" } },
	},
	SlimeJar = {
		id = "SlimeJar", name = "Slime Jar", tier = 1, rarity = "Common", category = "Toys", baseValue = 17,
		model = "SlimeJar",
		recipe = { { type = "Wipe" }, { type = "Polish" }, { type = "Test", style = "Shake" } },
	},
	StickerAlbum = {
		id = "StickerAlbum", name = "Sticker Album", tier = 1, rarity = "Common", category = "Decor", baseValue = 19,
		model = "StickerAlbum",
		recipe = { { type = "Wipe" }, { type = "Polish" } },
	},
	PlushBunny = {
		id = "PlushBunny", name = "Plush Bunny", tier = 1, rarity = "Uncommon", category = "Toys", baseValue = 36,
		model = "PlushBunny",
		recipe = { { type = "Wipe" }, { type = "Replace", parts = { "Eye" } }, { type = "Polish" } },
	},
	PocketCompass = {
		id = "PocketCompass", name = "Pocket Compass", tier = 1, rarity = "Uncommon", category = "Decor", baseValue = 34,
		model = "PocketCompass",
		recipe = { { type = "Wipe" }, { type = "Polish" }, { type = "Test", style = "Switch" } },
	},
	InstantCamera = {
		id = "InstantCamera", name = "Instant Camera", tier = 1, rarity = "Rare", category = "Electronics", baseValue = 85,
		model = "InstantCamera",
		recipe = { { type = "Wipe" }, { type = "Replace", parts = { "Lens" } }, { type = "Polish" }, { type = "Test", style = "Switch" } },
	},
	-- Tier 2 additions
	LunchBox = {
		id = "LunchBox", name = "Lunch Box", tier = 2, rarity = "Common", category = "Kitchen", baseValue = 72,
		model = "LunchBox",
		recipe = { { type = "Scrape" }, { type = "Polish" } },
	},
	LavaLamp = {
		id = "LavaLamp", name = "Lava Lamp", tier = 2, rarity = "Uncommon", category = "Decor", baseValue = 165,
		model = "LavaLamp",
		recipe = { { type = "Wipe" }, { type = "Replace", parts = { "Bulb" } }, { type = "Test", style = "Switch" } },
	},
	Boombox = {
		id = "Boombox", name = "Boombox", tier = 2, rarity = "Rare", category = "Music", baseValue = 410,
		model = "Boombox",
		recipe = { { type = "Scrape" }, { type = "Replace", parts = { "Dial" } }, { type = "Polish" }, { type = "Test", style = "Play" } },
	},
	PixelBrick = {
		id = "PixelBrick", name = "The Pixel Brick", tier = 2, rarity = "Epic", category = "Electronics", baseValue = 890,
		model = "PixelBrick",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Reassemble", parts = { "Button" } },
			{ type = "Polish" },
			{ type = "Test", style = "Play" },
		},
	},
	-- Relic (Lost Masterpiece) replacing the Clockwork Carousel
	GoldenCartridge = {
		id = "GoldenCartridge", name = "The Golden Cartridge", tier = 2, rarity = "Relic", category = "Electronics", baseValue = 9000,
		model = "GoldenCartridge",
		recipe = {
			{ type = "Wipe" },
			{ type = "Scrape" },
			{ type = "Replace", parts = { "Chip" } },
			{ type = "Polish" },
			{ type = "Test", style = "Play" },
		},
	},
}

return Items
