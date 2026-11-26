-- Skins.luau (ReplicatedStorage.Shared.Config.Skins)
-- Purpose: every shelf and pedestal skin sold at the skins stall (docs/10_Stock_Shop_And_Skins.md). Looks only: a skin
-- never changes how many shelves / pedestals you have, prices, or rating points. Bought once, owned forever.
-- Owner: Dev 3 (Sean) for the looks; Dev 1 (Ace) for prices. Depends on: Config.Rarities (rarity names and colours).
-- Read by: Shared.Stock (what can be in stock), SkinService (server: buy, apply, draw), SkinShopController (window).
-- A look is built from what the pieces already are (no new assets): colour + material, and for the rarer ones a trim
-- band, a light and sparkles (sparkles turn off with Settings "Reduce effects").
--   look = { color, material, reflectance?, trim? = Color3, trimMaterial?, light? = Color3, sparkle? = Color3 }
-- The top of a piece never moves (items sit on it): a skin only changes how the same block looks.

local Skins = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

Skins.LIST = {
	-- ===== Shelf skins (all display shelves in the shop) =====
	{ id = "ShelfPine", name = "Painted Pine", kind = "Shelf", rarity = "Common", price = 250,
		look = { color = rgb(236, 226, 205), material = M.WoodPlanks } },
	{ id = "ShelfMint", name = "Mint Paint", kind = "Shelf", rarity = "Common", price = 250,
		look = { color = rgb(150, 205, 180), material = M.WoodPlanks } },
	{ id = "ShelfWalnut", name = "Walnut", kind = "Shelf", rarity = "Uncommon", price = 600,
		look = { color = rgb(112, 74, 46), material = M.Wood } },
	{ id = "ShelfCoral", name = "Coral Lacquer", kind = "Shelf", rarity = "Uncommon", price = 600,
		look = { color = rgb(232, 120, 100), material = M.SmoothPlastic, reflectance = 0.05 } },
	{ id = "ShelfBrass", name = "Brass Trim", kind = "Shelf", rarity = "Rare", price = 1500,
		look = { color = rgb(120, 80, 50), material = M.Wood, trim = rgb(214, 168, 70), trimMaterial = M.Metal } },
	{ id = "ShelfTeal", name = "Teal Cabinet", kind = "Shelf", rarity = "Epic", price = 4000,
		look = { color = rgb(31, 122, 122), material = M.SmoothPlastic, reflectance = 0.08, trim = rgb(240, 232, 214), trimMaterial = M.SmoothPlastic } },
	{ id = "ShelfGilded", name = "Gilded Showcase", kind = "Shelf", rarity = "Legendary", price = 10000,
		look = { color = rgb(58, 38, 28), material = M.Wood, trim = rgb(236, 190, 80), trimMaterial = M.Metal, light = rgb(255, 214, 150) } },
	-- Relic and Mythic are only Sean's model skins (placeholders Relic Oak / Relic Stone / Starlight Shelf /
	-- Floating Crystal removed 2026-11-24; a save that owns or uses one just shows the classic look).
	-- Model skins (Sean's designs, built in tools/blender/skins.py): `model` = ReplicatedStorage.Assets.Skins.<model>,
	-- drawn on each screen by SkinModelController over the classic block; `color` / `material` are the fallback if the
	-- model can't be drawn. `aura` = dark glowing mist round the base (off with Reduce effects).
	{ id = "ShelfRunic", name = "Runic Antique", kind = "Shelf", rarity = "Relic", price = 20000,
		look = { model = "ShelfRunic", color = rgb(74, 69, 82), material = M.Slate, light = rgb(142, 108, 239), aura = rgb(46, 16, 88) } },
	-- pulse = the glow breathes slowly (light brightness + neon), an "alive" feel without moving parts
	{ id = "ShelfCelestial", name = "Celestial Ascension", kind = "Shelf", rarity = "Legendary", price = 8500,
		look = { model = "ShelfCelestial", color = rgb(242, 236, 225), material = M.Marble, light = rgb(255, 222, 160),
			aura = rgb(255, 196, 92), pulse = true } },
	-- Galaxy effects (all off with Reduce effects): sparkle = twinkles round the top rim and the glowing parts;
	-- starDust = tiny stars drifting up from the base; orbit = glowing star orbs circling the piece (one colour each);
	-- swirl = the model's Nebula / NebulaCore parts slowly shift through these colours
	{ id = "ShelfCosmic", name = "Cosmic Harmony", kind = "Shelf", rarity = "Mythic", price = 35000,
		look = { model = "ShelfCosmic", color = rgb(20, 24, 56), material = M.SmoothPlastic, light = rgb(190, 150, 255),
			sparkle = rgb(255, 242, 204), starDust = rgb(255, 242, 204), pulse = true,
			orbit = { rgb(255, 140, 220), rgb(140, 232, 232), rgb(255, 242, 204) },
			swirl = { rgb(176, 71, 159), rgb(110, 70, 200), rgb(50, 160, 210) } } },
	-- Sakura Starlight (Sean, 2026-11-24): gems = glowing pink cut diamonds floating round the piece with pink trails;
	-- aura = a rose-pink mist round the base (all off with Reduce effects)
	{ id = "ShelfSakura", name = "Sakura Starlight", kind = "Shelf", rarity = "Mythic", price = 35000,
		look = { model = "ShelfSakura", color = rgb(248, 232, 238), material = M.Marble, light = rgb(255, 150, 200),
			sparkle = rgb(255, 209, 230), starDust = rgb(255, 170, 210), pulse = true, gems = rgb(255, 70, 160), petals = true, floatItems = true,
			aura = rgb(215, 70, 150) } },

	-- ===== Pedestal skins (all exhibit pedestals in the shop) =====
	{ id = "PedestalCream", name = "Cream Paint", kind = "Pedestal", rarity = "Common", price = 250,
		look = { color = rgb(246, 236, 214), material = M.SmoothPlastic } },
	{ id = "PedestalCrate", name = "Wooden Crate", kind = "Pedestal", rarity = "Common", price = 250,
		look = { color = rgb(190, 150, 100), material = M.WoodPlanks } },
	{ id = "PedestalSandstone", name = "Sandstone", kind = "Pedestal", rarity = "Uncommon", price = 600,
		look = { color = rgb(214, 190, 150), material = M.Sandstone } },
	{ id = "PedestalWalnut", name = "Walnut & Brass", kind = "Pedestal", rarity = "Uncommon", price = 600,
		look = { color = rgb(112, 74, 46), material = M.Wood, trim = rgb(214, 168, 70), trimMaterial = M.Metal } },
	{ id = "PedestalMarble", name = "Marble", kind = "Pedestal", rarity = "Rare", price = 1500,
		look = { color = rgb(236, 236, 240), material = M.Marble } },
	{ id = "PedestalVelvet", name = "Velvet Top", kind = "Pedestal", rarity = "Epic", price = 4000,
		look = { color = rgb(40, 32, 30), material = M.Wood, trim = rgb(142, 31, 47), trimMaterial = M.Fabric } },
	{ id = "PedestalGilded", name = "Gilded Pillar", kind = "Pedestal", rarity = "Legendary", price = 10000,
		look = { color = rgb(246, 240, 228), material = M.Marble, trim = rgb(236, 190, 80), trimMaterial = M.Metal, light = rgb(255, 220, 160) } },
	{ id = "PedestalRunic", name = "Runic Antique", kind = "Pedestal", rarity = "Relic", price = 21000,
		look = { model = "PedestalRunic", color = rgb(74, 69, 82), material = M.Slate, light = rgb(142, 108, 239), aura = rgb(46, 16, 88) } },
	{ id = "PedestalCelestial", name = "Celestial Ascension", kind = "Pedestal", rarity = "Legendary", price = 9100,
		look = { model = "PedestalCelestial", color = rgb(242, 236, 225), material = M.Marble, light = rgb(255, 222, 160),
			aura = rgb(255, 196, 92), pulse = true } },
	{ id = "PedestalCosmic", name = "Cosmic Harmony", kind = "Pedestal", rarity = "Mythic", price = 37000,
		look = { model = "PedestalCosmic", color = rgb(20, 24, 56), material = M.SmoothPlastic, light = rgb(190, 150, 255),
			sparkle = rgb(255, 242, 204), starDust = rgb(255, 242, 204), pulse = true,
			orbit = { rgb(255, 140, 220), rgb(140, 232, 232), rgb(255, 242, 204) },
			swirl = { rgb(176, 71, 159), rgb(110, 70, 200), rgb(50, 160, 210) } } },
	{ id = "PedestalSakura", name = "Sakura Starlight", kind = "Pedestal", rarity = "Mythic", price = 25000,
		look = { model = "PedestalSakura", color = rgb(248, 232, 238), material = M.Marble, light = rgb(255, 150, 200),
			sparkle = rgb(255, 209, 230), starDust = rgb(255, 170, 210), pulse = true, gems = rgb(255, 70, 160), petals = true, floatItems = true,
			aura = rgb(215, 70, 150) } },

	-- ===== Cashier skins (the shop's cash counter; model skins only) =====
	-- Common .. Legendary use one plain counter model (CashierClassic) that SkinModelController paints: `color` /
	-- `material` = the panels, `frame` (default: `color` darkened) = the body and frames, `top` (default: frame) = the
	-- slab, `trim` / `trimMaterial` (default: frame) = the stripe and bands. The register and props keep their colours.
	{ id = "CashierPine", name = "Painted Pine", kind = "Cashier", rarity = "Common", price = 250,
		look = { model = "CashierClassic", color = rgb(236, 226, 205), material = M.WoodPlanks, frame = rgb(196, 170, 130) } },
	{ id = "CashierMint", name = "Mint Paint", kind = "Cashier", rarity = "Common", price = 250,
		look = { model = "CashierClassic", color = rgb(150, 205, 180), material = M.WoodPlanks, frame = rgb(236, 226, 205),
			top = rgb(196, 170, 130) } },
	{ id = "CashierWalnut", name = "Walnut", kind = "Cashier", rarity = "Uncommon", price = 600,
		look = { model = "CashierClassic", color = rgb(112, 74, 46), material = M.Wood } },
	{ id = "CashierCoral", name = "Coral Lacquer", kind = "Cashier", rarity = "Uncommon", price = 600,
		look = { model = "CashierClassic", color = rgb(232, 120, 100), material = M.SmoothPlastic, reflectance = 0.05,
			frame = rgb(246, 236, 214), top = rgb(176, 122, 72) } },
	{ id = "CashierBrass", name = "Brass Trim", kind = "Cashier", rarity = "Rare", price = 1500,
		look = { model = "CashierClassic", color = rgb(120, 80, 50), material = M.Wood, trim = rgb(214, 168, 70), trimMaterial = M.Metal } },
	{ id = "CashierTeal", name = "Teal Cabinet", kind = "Cashier", rarity = "Epic", price = 4000,
		look = { model = "CashierClassic", color = rgb(31, 122, 122), material = M.SmoothPlastic, reflectance = 0.08,
			frame = rgb(240, 232, 214), top = rgb(240, 232, 214), trim = rgb(214, 168, 70), trimMaterial = M.Metal } },
	{ id = "CashierGilded", name = "Gilded Counter", kind = "Cashier", rarity = "Legendary", price = 10000,
		look = { model = "CashierClassic", color = rgb(58, 38, 28), material = M.Wood, trim = rgb(236, 190, 80), trimMaterial = M.Metal,
			top = rgb(246, 240, 228), topMaterial = M.Marble, light = rgb(255, 214, 150) } },
	-- Sean's designed counters (assets/skin-designs "Cashier skins (1-3)")
	{ id = "CashierCelestial", name = "Celestial Ascension", kind = "Cashier", rarity = "Legendary", price = 9700,
		look = { model = "CashierCelestial", color = rgb(242, 236, 225), material = M.Marble, light = rgb(255, 222, 160),
			aura = rgb(255, 196, 92), pulse = true } },
	{ id = "CashierRunic", name = "Runic Antique", kind = "Cashier", rarity = "Relic", price = 22000,
		look = { model = "CashierRunic", color = rgb(74, 69, 82), material = M.Slate, light = rgb(142, 108, 239), aura = rgb(46, 16, 88) } },
	{ id = "CashierCosmic", name = "Cosmic Harmony", kind = "Cashier", rarity = "Mythic", price = 39000,
		look = { model = "CashierCosmic", color = rgb(20, 24, 56), material = M.SmoothPlastic, light = rgb(190, 150, 255),
			sparkle = rgb(255, 242, 204), starDust = rgb(255, 242, 204), pulse = true,
			orbit = { rgb(255, 140, 220), rgb(140, 232, 232), rgb(255, 242, 204) },
			swirl = { rgb(176, 71, 159), rgb(110, 70, 200), rgb(50, 160, 210) } } },
	{ id = "CashierSakura", name = "Sakura Starlight", kind = "Cashier", rarity = "Mythic", price = 50000,
		look = { model = "CashierSakura", color = rgb(248, 232, 238), material = M.Marble, light = rgb(255, 150, 200),
			sparkle = rgb(255, 209, 230), starDust = rgb(255, 170, 210), pulse = true, gems = rgb(255, 70, 160), petals = true, floatItems = true,
			aura = rgb(215, 70, 150) } },
}

-- ===== Filipino-inspired families (Ace + Claude, 2026-11-25; docs/12 Stage 2) =====
-- Subtle: the material and the colour are the culture (rattan weave, narra hardwood, capiz shell, machuca cement tile).
-- One definition becomes a shelf, a pedestal AND a cashier skin, so a player can match the whole shop. Looks only.
-- `colorways` (Legendary and above): one skin per colour, all sharing `family`. Shared.Stock rolls ONE skin per kind and
-- rarity from the pool, so only one colourway of a family is in stock at a time: you wait for the colour you want.
-- Cashier looks need `model = "CashierClassic"` (see the Cashier note above); `frame` (default: `color` darkened) is the body.
local FAMILIES = {
	{ family = "Rattan", name = "Rattan Weave", rarity = "Common", price = 250,
		look = { color = rgb(222, 190, 130), material = M.WoodPlanks }, frame = rgb(186, 146, 90) },
	{ family = "Narra", name = "Narra Wood", rarity = "Rare", price = 1500,
		look = { color = rgb(122, 52, 38), material = M.Wood, trim = rgb(44, 24, 18), trimMaterial = M.Wood } },
	{ family = "Capiz", name = "Capiz Pearl", rarity = "Epic", price = 4000,
		look = { color = rgb(244, 240, 230), material = M.SmoothPlastic, reflectance = 0.18, trim = rgb(212, 196, 160),
			trimMaterial = M.Metal, light = rgb(255, 238, 205) }, frame = rgb(226, 214, 190) },
	{ family = "Machuca", name = "Machuca Tiles", rarity = "Legendary", price = 9000, colorways = {
		{ colorway = "Terracotta", look = { color = rgb(196, 98, 66), material = M.Concrete, reflectance = 0.08,
			trim = rgb(240, 228, 200), trimMaterial = M.SmoothPlastic, light = rgb(255, 206, 150) } },
		{ colorway = "Teal", look = { color = rgb(35, 120, 128), material = M.Concrete, reflectance = 0.08,
			trim = rgb(240, 228, 200), trimMaterial = M.SmoothPlastic, light = rgb(170, 240, 235) } },
		{ colorway = "Navy", look = { color = rgb(36, 56, 110), material = M.Concrete, reflectance = 0.08,
			trim = rgb(236, 190, 80), trimMaterial = M.Metal, light = rgb(170, 190, 255) } },
	} },
}

local function copyLook(look: { [string]: any }): { [string]: any }
	local out = {}
	for key, value in look do
		out[key] = value
	end
	return out
end

for _, fam in FAMILIES do
	local variants = fam.colorways or { { look = fam.look } }
	for _, variant in variants do
		for _, kind in { "Shelf", "Pedestal", "Cashier" } do
			local look = copyLook(variant.look)
			if kind == "Cashier" then
				look.model = "CashierClassic"
				look.frame = fam.frame or look.trim or look.color
				look.top = look.top or look.trim
			end
			local suffix = variant.colorway or ""
			table.insert(Skins.LIST, {
				id = kind .. fam.family .. suffix,
				name = fam.name .. (if variant.colorway then " (" .. variant.colorway .. ")" else ""),
				kind = kind,
				rarity = fam.rarity,
				price = fam.price,
				family = fam.family,
				colorway = variant.colorway,
				look = look,
			})
		end
	end
end

-- ===== Theme skins (Robux passes, docs/12 Stage 5) =====
-- `pass` = the pass id in Config.Monetization that grants the skin. They are NEVER in the stock roll (Shared.Stock skips them) and
-- never sold for cash: owning the pass puts them in your Owned tab. The price field is unused (kept so every skin has one).
local THEME_SKINS = {
	{ pass = "ThemeArcade", name = "Retro Arcade", shelf = { color = rgb(30, 26, 56), material = M.SmoothPlastic, reflectance = 0.1,
			trim = rgb(255, 70, 160), trimMaterial = M.Neon, light = rgb(255, 90, 170) },
		frame = rgb(54, 40, 96), id = "Arcade" },
	{ pass = "ThemeCabin", name = "Cozy Cabin", shelf = { color = rgb(150, 100, 62), material = M.Wood,
			trim = rgb(86, 54, 32), trimMaterial = M.Wood, light = rgb(255, 214, 150) },
		frame = rgb(112, 72, 44), id = "Cabin" },
}
for _, theme in THEME_SKINS do
	for _, kind in { "Shelf", "Pedestal", "Cashier" } do
		local look = copyLook(theme.shelf)
		if kind == "Cashier" then
			look.model = "CashierClassic"
			look.frame = theme.frame
			look.top = theme.shelf.trim
		end
		table.insert(Skins.LIST, {
			id = kind .. theme.id,
			name = theme.name,
			kind = kind,
			rarity = "Epic",
			price = 1,
			pass = theme.pass,
			look = look,
		})
	end
end

Skins.BY_ID = {}
for _, skin in Skins.LIST do
	Skins.BY_ID[skin.id] = skin
end

-- Cashier = the shop's cash counter (Plots.PlotN.ShopProps.CashCounter); added 2026-11-24 (Ace OK). Its skins are
-- model skins from Sean's designs (Runic first), drawn over the counter by SkinModelController.
-- KINDS order matters: Shared.Stock rolls kinds in this order, so a new kind goes at the END (the shelf / pedestal
-- stock stays the same as before).
Skins.KINDS = { "Shelf", "Pedestal", "Cashier" }

-- the save field (data.skins.<field>) that holds the skin in use for each kind
Skins.FIELD = { Shelf = "shelf", Pedestal = "pedestal", Cashier = "cashier" }

return Skins
