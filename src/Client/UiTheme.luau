-- UiTheme.luau (StarterPlayerScripts.Client.UiTheme)
-- Purpose: UI colors in one place: the docs/01 J1 palette and rarity display colors (Rarities.luau says
-- "Dev 3 picks them with the UI"), plus small display helpers (money formatting) shared by screens.
-- Owner: Dev 3 (Sean). Depends on: nothing.

local UiTheme = {}

-- 2026-11-25: aligned with the Figma "Main HUD" palette (warm walnut panels, cream text, vivid teal / coral / gold).
-- The names stay (screens read UiTheme.Teal etc.); only the values changed.
UiTheme.Teal = Color3.fromHex("1FC2A5") -- primary (was 1F7A7A)
UiTheme.Coral = Color3.fromHex("FF6A4D") -- accent / call to action (was D2694A)
UiTheme.Cream = Color3.fromHex("3F281B") -- panels: walnut (was 22252B)
UiTheme.Ink = Color3.fromHex("FFF1D6") -- text: cream (was F4F0E8)
UiTheme.Disabled = Color3.fromRGB(122, 106, 96) -- warm grey (was 4A4F58)
UiTheme.Golden = Color3.fromHex("FFC83A")

-- Keys match the rarity ids in Shared/Config/Rarities.luau.
UiTheme.Rarity = {
	Common = Color3.fromHex("CFC7B8"), -- parchment
	Uncommon = Color3.fromHex("5FD16B"),
	Rare = Color3.fromHex("4DA3FF"),
	Epic = Color3.fromHex("B070FF"),
	Legendary = Color3.fromHex("FFC83A"),
	Relic = Color3.fromHex("FF7A4D"), -- orange-red (was icy cyan; it clashed with Rare blue on warm panels)
	Mythic = Color3.fromHex("FF5FB8"), -- magenta
	Secret = Color3.fromHex("FF3B3B"), -- deep red: the rarest
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
