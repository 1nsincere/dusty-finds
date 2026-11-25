-- UiSkin.luau (ReplicatedStorage.Shared.Config.UiSkin)
-- Purpose: the look of the HUD and windows: colours, fonts and icon images. Since 2026-11-25 this is the warm
-- "workshop" look from the Figma "Main HUD — Final Proposal" (walnut + cream panels, vivid tile colours, multicolour
-- icons). The old white glyphs (ICONS) stay as a fallback for windows that still use them. Read by HudSkinController,
-- HudKit, HudLayoutController, NotificationDock, TravelController, SprintController (client only).
-- Change values here to restyle; nothing else depends on the numbers.
-- Owner: Dev 1 (Ace).

local UiSkin = {}

-- Old white glyphs (rendered by tools/blender/ui_icons.py, uploaded 2026-11-20). Still used by the Travel window rows.
UiSkin.ICONS = {
	Inventory = "rbxassetid://90075328979794", -- bag
	Upgrades = "rbxassetid://122344302585636", -- hammer + wrench
	Collection = "rbxassetid://128487429548239", -- book
	Supply = "rbxassetid://96954138367414", -- crate
	MyShop = "rbxassetid://132322279788038", -- house
	Visit = "rbxassetid://80636990889831", -- two people
	Settings = "rbxassetid://120529847350796", -- gear
	Travel = "rbxassetid://83879510263299", -- map pin
	Sprint = "rbxassetid://112081913038531", -- lightning
	Coin = "rbxassetid://97840091327623",
	Star = "rbxassetid://88828443953957",
	Bell = "rbxassetid://119583724725227",
}

-- Multicolour icons exported from the Figma icon library (256 px PNGs, uploaded 2026-11-25). Keys are icon names,
-- not button names: use UiSkin.Art(name) so a missing id falls back to the white glyph.
UiSkin.ART = {
	Cash = "rbxassetid://116188880218539",
	Star = "rbxassetid://113362249509024",
	Clock = "rbxassetid://131913128929566",
	Inventory = "rbxassetid://90897441961822",
	Crate = "rbxassetid://87485232185095",
	Upgrades = "rbxassetid://77223664525010",
	Collection = "rbxassetid://125020256469917",
	Menu = "rbxassetid://93448505537683",
	Travel = "rbxassetid://122690682839888",
	Visit = "rbxassetid://131009428410338",
	GamePasses = "rbxassetid://104372347203890",
	Settings = "rbxassetid://137739230651809",
	Sprint = "rbxassetid://94399282721311",
	Invite = "rbxassetid://103749398351450",
	AutoRun = "rbxassetid://95333545179379",
	EditMode = "rbxassetid://109209282265503",
	Close = "rbxassetid://128936222115795",
	-- Window / Travel / Settings icons (uploaded 2026-11-25). An empty id falls back to a white glyph (see FALLBACK).
	Home = "rbxassetid://77959167204405",
	Museum = "rbxassetid://91274018182999",
	Jeepney = "rbxassetid://81083504240271",
	Tricycle = "rbxassetid://97712318006066",
	Bell = "rbxassetid://132161914391331",
	Music = "rbxassetid://99530388756609",
	Speaker = "rbxassetid://121606148900391",
	Sparkles = "rbxassetid://91216730425302",
}

-- Which white glyph to fall back to when an ART icon has no image yet.
local FALLBACK = {
	Cash = "Coin", Crate = "Supply", EditMode = "Upgrades", GamePasses = "Star", Menu = "Bell", Clock = "Bell", Invite = "Visit", AutoRun = "Sprint",
	Home = "MyShop", Museum = "Collection", Jeepney = "Travel", Tricycle = "Travel", Music = "Bell", Speaker = "Bell", Sparkles = "Star",
}

function UiSkin.Art(name: string): string
	local id = UiSkin.ART[name]
	if id and id ~= "" then
		return id
	end
	return UiSkin.ICONS[FALLBACK[name] or name] or ""
end

UiSkin.COLORS = {
	-- panels / windows: warm walnut gradient with a thin cream edge
	panelTop = Color3.fromRGB(92, 60, 42), -- gradient top of every panel
	panelBottom = Color3.fromRGB(40, 26, 18), -- gradient bottom
	panelTransparency = 0.04,
	edge = Color3.fromRGB(255, 241, 214), -- thin cream edge
	edgeTransparency = 0.7,
	accent = Color3.fromRGB(255, 200, 58), -- gold (bars, hover, highlights)
	accentDim = Color3.fromRGB(217, 138, 0),
	money = Color3.fromRGB(255, 200, 58),
	text = Color3.fromRGB(255, 241, 214), -- cream
	textDim = Color3.fromRGB(214, 190, 160),
	good = Color3.fromRGB(110, 214, 120),
	xpFrom = Color3.fromRGB(46, 230, 196),
	xpTo = Color3.fromRGB(180, 255, 232),
	-- HUD pieces (HudKit / HudLayoutController / NotificationDock)
	ink = Color3.fromRGB(43, 27, 20), -- outlines
	walnut = Color3.fromRGB(63, 40, 27),
	walnutLight = Color3.fromRGB(90, 59, 40),
	cream = Color3.fromRGB(255, 241, 214),
	gold = Color3.fromRGB(255, 200, 58),
}

-- Tile colours: face + darker lip, one per HUD action (same colours as the Figma tiles).
UiSkin.TILE = {
	Inventory = { face = Color3.fromRGB(31, 194, 165), lip = Color3.fromRGB(11, 127, 108) }, -- teal
	Menu = { face = Color3.fromRGB(255, 138, 61), lip = Color3.fromRGB(194, 85, 26) }, -- orange
	Travel = { face = Color3.fromRGB(63, 167, 255), lip = Color3.fromRGB(31, 107, 196) }, -- blue
	Visit = { face = Color3.fromRGB(255, 107, 142), lip = Color3.fromRGB(191, 58, 94) }, -- rose
	GamePasses = { face = Color3.fromRGB(145, 104, 255), lip = Color3.fromRGB(90, 58, 196) }, -- violet
	Settings = { face = Color3.fromRGB(134, 163, 181), lip = Color3.fromRGB(70, 101, 122) }, -- steel
	Sprint = { face = Color3.fromRGB(255, 106, 77), lip = Color3.fromRGB(184, 52, 31) }, -- coral
}

-- Notification kinds (NotificationDock): medallion colour, lip colour, icon name (UiSkin.Art).
UiSkin.TOAST = {
	Delivery = { color = Color3.fromRGB(255, 106, 77), lip = Color3.fromRGB(184, 52, 31), art = "Crate" },
	LevelUp = { color = Color3.fromRGB(255, 200, 58), lip = Color3.fromRGB(217, 138, 0), art = "Star" },
	Upgrade = { color = Color3.fromRGB(61, 190, 90), lip = Color3.fromRGB(30, 122, 54), art = "Upgrades" },
	Sale = { color = Color3.fromRGB(31, 194, 165), lip = Color3.fromRGB(11, 127, 108), art = "Cash" },
	Info = { color = Color3.fromRGB(134, 163, 181), lip = Color3.fromRGB(70, 101, 122), art = "Menu" },
}

UiSkin.CORNER = 10 -- px
UiSkin.FONT_TEXT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
UiSkin.FONT_BODY = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Regular)
UiSkin.FONT_NUMBER = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
UiSkin.FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

return UiSkin
