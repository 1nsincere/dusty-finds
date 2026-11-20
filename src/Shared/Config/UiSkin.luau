-- UiSkin.luau (ReplicatedStorage.Shared.Config.UiSkin)
-- Purpose: the look of the HUD and windows (a sleek, dark, angular "shooter HUD" style): colours, fonts and the icon
-- images (white glyphs rendered by tools/blender/ui_icons.py, uploaded 2026-11-20). Read by HudSkinController,
-- TravelController and SprintController (client only). Change values here to restyle; nothing else depends on them.
-- Owner: Dev 1 (Ace).

local UiSkin = {}

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

UiSkin.COLORS = {
	panelTop = Color3.fromRGB(38, 45, 58), -- gradient top of every panel
	panelBottom = Color3.fromRGB(13, 16, 22), -- gradient bottom
	panelTransparency = 0.12,
	edge = Color3.fromRGB(255, 255, 255), -- thin bright edge
	edgeTransparency = 0.78,
	accent = Color3.fromRGB(255, 176, 46), -- orange-gold accent (bars, hover, highlights)
	accentDim = Color3.fromRGB(188, 120, 28),
	money = Color3.fromRGB(255, 214, 92),
	text = Color3.fromRGB(240, 242, 246),
	textDim = Color3.fromRGB(158, 166, 180),
	good = Color3.fromRGB(110, 214, 120),
	xpFrom = Color3.fromRGB(255, 140, 38),
	xpTo = Color3.fromRGB(255, 214, 92),
}

UiSkin.CORNER = 4 -- px: small radius = angular look
UiSkin.FONT_TEXT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
UiSkin.FONT_NUMBER = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
UiSkin.FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

return UiSkin
