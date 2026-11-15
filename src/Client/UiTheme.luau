-- UiTheme.luau (StarterPlayerScripts.Client.UiTheme)
-- Purpose: UI colors in one place: the docs/01 J1 palette and rarity display colors (Rarities.luau says
-- "Dev 3 picks them with the UI"). Screens read colors from here instead of hard-coding them.
-- Owner: Dev 3 (Sean). Depends on: nothing.

local UiTheme = {}

UiTheme.Teal = Color3.fromHex("0E7C7B") -- primary
UiTheme.Coral = Color3.fromHex("F2784B") -- accent / call to action
UiTheme.Cream = Color3.fromHex("FFF8EE") -- panels
UiTheme.Ink = Color3.fromHex("1F2D3A") -- text
UiTheme.Disabled = Color3.fromRGB(190, 185, 175)
UiTheme.Golden = Color3.fromHex("FFD43B")

-- Keys match the rarity ids in Shared/Config/Rarities.luau.
UiTheme.Rarity = {
	Common = Color3.fromHex("9AA0A6"),
	Uncommon = Color3.fromHex("3DBE6B"),
	Rare = Color3.fromHex("2F80ED"),
	Epic = Color3.fromHex("9B51E0"),
	Legendary = Color3.fromHex("F2A93B"),
}

function UiTheme.rarityColor(rarity: string?): Color3
	return (rarity and UiTheme.Rarity[rarity]) or UiTheme.Rarity.Common
end

return UiTheme
