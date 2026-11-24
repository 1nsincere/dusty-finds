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
	{ id = "ShelfCelestial", name = "Celestial Ascension", kind = "Shelf", rarity = "Mythic", price = 30000,
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
	{ id = "PedestalCelestial", name = "Celestial Ascension", kind = "Pedestal", rarity = "Mythic", price = 32000,
		look = { model = "PedestalCelestial", color = rgb(242, 236, 225), material = M.Marble, light = rgb(255, 222, 160),
			aura = rgb(255, 196, 92), pulse = true } },
	{ id = "PedestalCosmic", name = "Cosmic Harmony", kind = "Pedestal", rarity = "Mythic", price = 37000,
		look = { model = "PedestalCosmic", color = rgb(20, 24, 56), material = M.SmoothPlastic, light = rgb(190, 150, 255),
			sparkle = rgb(255, 242, 204), starDust = rgb(255, 242, 204), pulse = true,
			orbit = { rgb(255, 140, 220), rgb(140, 232, 232), rgb(255, 242, 204) },
			swirl = { rgb(176, 71, 159), rgb(110, 70, 200), rgb(50, 160, 210) } } },
}

Skins.BY_ID = {}
for _, skin in Skins.LIST do
	Skins.BY_ID[skin.id] = skin
end

Skins.KINDS = { "Shelf", "Pedestal" }

return Skins
