-- UiTheme.luau (StarterPlayerScripts.Client.UiTheme)
-- Purpose: UI colors in one place: the docs/01 J1 palette and rarity display colors (Rarities.luau says
-- "Dev 3 picks them with the UI"), plus small display helpers (money formatting) shared by screens.
-- Owner: Dev 3 (Sean). Depends on: nothing.

local UiTheme = {}

UiTheme.Teal = Color3.fromHex("1F7A7A") -- primary
UiTheme.Coral = Color3.fromHex("D2694A") -- accent / call to action
UiTheme.Cream = Color3.fromHex("22252B") -- panels
UiTheme.Ink = Color3.fromHex("F4F0E8") -- text
UiTheme.Disabled = Color3.fromRGB(74, 79, 88)
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

-- 1500 -> "$1,500". Used by every screen that shows money (HUD, Upgrades).
function UiTheme.formatCash(amount: number): string
	local formatted = tostring(math.floor(amount))
	repeat
		local count
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return "$" .. formatted
end

return UiTheme
