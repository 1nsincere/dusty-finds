-- ItemIcons.luau (ReplicatedStorage.Shared.Config.ItemIcons)
-- Purpose: the flat cartoon icon for every item (Figma "Item / ..." style), shown on the Inventory cards. The detail
-- panel still shows the item's real 3D model. An item missing here falls back to its 3D model, then to `Unknown`.
-- Owner: Dev 3 (Sean). Depends on: nothing (keys must match the ids in Config/Items.luau).
-- Made 2026-11-25: all 31 drawn with Gemini in one style (the first 9 + Unknown came from Figma and were redrawn to match) and
-- cleaned by tools/blender/clean_icons.py (checkerboard removed, same 512 px framing). All uploaded to the group.
-- Adding an item: put its PNG in assets/item-icons, run clean_icons.py, upload, add the id here.

local ItemIcons = {
	-- Tier 1
	RubberDuck = "rbxassetid://100375734680818",
	Teacup = "rbxassetid://138172072562483",
	ToyCar = "rbxassetid://81179004802463",
	SpinningTop = "rbxassetid://138312578065737",
	SlimeJar = "rbxassetid://91392565743235",
	StickerAlbum = "rbxassetid://80244657985981",
	AlarmClock = "rbxassetid://91405944960908",
	SnowGlobe = "rbxassetid://131290479312555",
	PlushBunny = "rbxassetid://80423563395440",
	PocketCompass = "rbxassetid://87488116521173",
	MusicBox = "rbxassetid://108636386389442",
	InstantCamera = "rbxassetid://113502530012902",
	CopperKettle = "rbxassetid://127191756300176",
	TinRobot = "rbxassetid://129457295219510",
	Gramophone = "rbxassetid://102425633569394",
	-- Tier 2
	VinylRecord = "rbxassetid://119465644268874",
	EnamelMug = "rbxassetid://80975017795180",
	LunchBox = "rbxassetid://79150510999708",
	RotaryPhone = "rbxassetid://87230699004992",
	LavaLamp = "rbxassetid://74149472115934",
	PocketWatch = "rbxassetid://104253260653968",
	Boombox = "rbxassetid://114865367146543",
	PixelBrick = "rbxassetid://94383458804586",
	Jukebox = "rbxassetid://97853169968804",
	StarlightOrrery = "rbxassetid://128045447876519",
	GoldenCartridge = "rbxassetid://80711099362790",
	CrystalMusicBox = "rbxassetid://85435129209521",
	JadeDragonClock = "rbxassetid://97021873417159",
	SunIdol = "rbxassetid://107389743616689",
	Astrolabe = "rbxassetid://134461603192460",
	-- shown for an item that has no icon and no model yet
	Unknown = "rbxassetid://113841312165127",
}

return ItemIcons
