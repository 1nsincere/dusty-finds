-- Themes.luau (ReplicatedStorage.Shared.Config.Themes)
-- Purpose: one-tap shop looks for the Paint Bar (docs/12, universal shop plan). A theme is just FOUR paints (wall, floor, trim, accent)
-- that look good together, so most players never mix colours by hand. DATA + two pure rules, no game state.
-- Owner: Dev 1 (Ace). Read by: PaintService (buy / apply a theme), PaintShopController (the Themes tab).
-- looks = { Wall, Floor, Trim, Accent } paint ids from Config.Paints; "" = the original (default) look.
-- tier: "starter" = the default look, always yours; "free" = claim it at the Paint Bar for $0 (cheap basics, so new players start with a choice);
--       "cash" = buy the whole look at a small bundle discount (owned pieces are not charged again); "pass" = comes with a Robux pass
--       (Config.Monetization), Collector's Corner. Looks only, never an advantage (docs/11).

local Paints = require(script.Parent.Paints)

local Themes = {}

Themes.BUNDLE_DISCOUNT = 0.85 -- a cash theme costs 85% of its not-yet-owned paints, rounded up to $10

Themes.LIST = {
	{ id = "CapizCream", name = "Capiz Cream", tier = "starter", note = "Warm plaster and narra wood: the default look.",
		looks = { Wall = "", Floor = "", Trim = "", Accent = "" } },
	{ id = "PandanLeaf", name = "Pandan Leaf", tier = "free", note = "Calm botanical green with golden honey.",
		looks = { Wall = "WallPandan", Floor = "FloorPine", Trim = "TrimBigas", Accent = "AccentHoney" } },
	{ id = "KalamansiMist", name = "Kalamansi Mist", tier = "free", note = "Fresh and airy, with a citrus accent.",
		looks = { Wall = "WallKalamansi", Floor = "FloorCement", Trim = "TrimCoral", Accent = "AccentKalamansi" } },
	{ id = "UbeHalaya", name = "Ube Halaya", tier = "cash", note = "Soft pastel violet with coconut-milk trim.",
		looks = { Wall = "WallUbe", Floor = "FloorPine", Trim = "TrimSampaguita", Accent = "AccentUbe" } },
	{ id = "SantanSunset", name = "Santan Sunset", tier = "cash", note = "Bold shophouse coral with deep teal.",
		looks = { Wall = "WallSantan", Floor = "FloorNarra", Trim = "TrimCapiz", Accent = "AccentTeal" } },
	{ id = "BarakoRoast", name = "Barako Roast", tier = "cash", note = "A classic antique parlour in coffee browns.",
		looks = { Wall = "WallTsokolate", Floor = "FloorNarra", Trim = "TrimBigas", Accent = "AccentBrick" } },
	{ id = "MayonAsh", name = "Mayon Ash", tier = "cash", note = "Moody volcanic slate with limestone trim.",
		looks = { Wall = "WallMayon", Floor = "FloorCement", Trim = "TrimCoral", Accent = "AccentTerracotta" } },
	{ id = "RetroArcade", name = "Retro Arcade", tier = "pass", pass = "ThemeArcade", note = "Neon pink on midnight blue.",
		looks = { Wall = "WallArcade", Floor = "FloorArcade", Trim = "TrimArcade", Accent = "AccentArcade" } },
	{ id = "CozyCabin", name = "Cozy Cabin", tier = "pass", pass = "ThemeCabin", note = "Warm logs and honey wood.",
		looks = { Wall = "WallCabin", Floor = "FloorCabin", Trim = "TrimCabin", Accent = "AccentCabin" } },
	{ id = "ParolPasko", name = "Parol Pasko", tier = "pass", pass = "ThemePasko", note = "Cream, deep red and gold: a parol lit at night.",
		looks = { Wall = "WallPasko", Floor = "FloorPasko", Trim = "TrimPasko", Accent = "AccentPasko" } },
	{ id = "NocheBuena", name = "Noche Buena", tier = "pass", pass = "ThemePasko", note = "Pine green with cream trim and warm gold.",
		looks = { Wall = "WallNoche", Floor = "FloorNoche", Trim = "TrimNoche", Accent = "AccentNoche" } },
}

Themes.BY_ID = {}
for _, theme in Themes.LIST do
	Themes.BY_ID[theme.id] = theme
end

Themes.SLOTS = { "Wall", "Floor", "Trim", "Accent" }

-- The paint ids of a theme that are real paints (not the "" default look), as a list.
function Themes.paintIds(theme: any): { string }
	local ids = {}
	for _, slot in Themes.SLOTS do
		local id = theme.looks[slot]
		if id ~= "" and id ~= nil then
			table.insert(ids, id)
		end
	end
	return ids
end

-- What it costs to buy this theme now: the not-yet-owned paints at the bundle discount, rounded up to $10. owned = { [paintId] = true }.
-- free and starter themes cost 0; a pass theme has no cash price (returns nil).
function Themes.price(theme: any, owned: { [string]: boolean }): number?
	if theme.tier == "pass" then
		return nil
	end
	if theme.tier == "free" or theme.tier == "starter" then
		return 0
	end
	local sum = 0
	for _, id in Themes.paintIds(theme) do
		local paint = Paints.BY_ID[id]
		if paint and not owned[id] then
			sum += paint.price
		end
	end
	return math.ceil(sum * Themes.BUNDLE_DISCOUNT / 10) * 10
end

-- Does the player own every paint of the theme?
function Themes.ownsAll(theme: any, owned: { [string]: boolean }): boolean
	for _, id in Themes.paintIds(theme) do
		if not owned[id] then
			return false
		end
	end
	return true
end

-- Is this theme the look in use? current = { wall = "", floor = "", trim = "", accent = "" } (the saved paints table).
function Themes.isInUse(theme: any, current: any): boolean
	return (current.wall or "") == theme.looks.Wall and (current.floor or "") == theme.looks.Floor
		and (current.trim or "") == theme.looks.Trim and (current.accent or "") == theme.looks.Accent
end

return Themes
