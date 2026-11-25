-- Paints.luau (ReplicatedStorage.Shared.Config.Paints)
-- Purpose: wall and floor paints sold at the Paint Bar in the Warehouse Market (docs/12 Stage 2). Looks only: a paint never
-- changes slots, prices, customers or rating points. Cheap, ALWAYS in stock (no restock roll), bought once, owned forever.
-- Names are Filipino fruit and food colours (subtle, friendly): ube, pandan, kalamansi, dalandan, langka, santan...
-- Owner: Dev 1 (Ace). Read by: PaintService (server: buy, apply, draw), PaintShopController (the window).
--   Wall paints change the shop's wall colour (the material stays). Floor paints change colour AND material.
--   price in cash. `material` is optional.

local Paints = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

Paints.LIST = {
	-- ===== Walls =====
	{ id = "WallSampaguita", name = "Sampaguita White", kind = "Wall", price = 150, color = rgb(250, 248, 240) },
	{ id = "WallKalamansi", name = "Kalamansi Green", kind = "Wall", price = 200, color = rgb(172, 204, 112) },
	{ id = "WallPandan", name = "Pandan Green", kind = "Wall", price = 200, color = rgb(112, 164, 124) },
	{ id = "WallUbe", name = "Ube Violet", kind = "Wall", price = 250, color = rgb(152, 122, 192) },
	{ id = "WallDalandan", name = "Dalandan Orange", kind = "Wall", price = 250, color = rgb(240, 152, 72) },
	{ id = "WallLangka", name = "Langka Yellow", kind = "Wall", price = 250, color = rgb(240, 206, 112) },
	{ id = "WallSantan", name = "Santan Coral", kind = "Wall", price = 300, color = rgb(236, 124, 112) },
	{ id = "WallMayon", name = "Mayon Ash", kind = "Wall", price = 300, color = rgb(150, 152, 158) },
	{ id = "WallTsokolate", name = "Tsokolate Brown", kind = "Wall", price = 400, color = rgb(112, 74, 54) },
	{ id = "WallCanal", name = "Canal Teal", kind = "Wall", price = 400, color = rgb(62, 142, 142) },

	-- ===== Floors =====
	{ id = "FloorPine", name = "Pine Planks", kind = "Floor", price = 250, color = rgb(222, 196, 150), material = M.WoodPlanks },
	{ id = "FloorCement", name = "Cement Grey", kind = "Floor", price = 250, color = rgb(176, 174, 168), material = M.Concrete },
	{ id = "FloorNarra", name = "Narra Boards", kind = "Floor", price = 300, color = rgb(140, 86, 56), material = M.WoodPlanks },
	{ id = "FloorTerracotta", name = "Terracotta Tile", kind = "Floor", price = 350, color = rgb(196, 104, 72), material = M.Concrete },
	{ id = "FloorCapiz", name = "Capiz Cream", kind = "Floor", price = 600, color = rgb(240, 232, 214), material = M.Marble },
	{ id = "FloorMachuca", name = "Machuca Teal", kind = "Floor", price = 600, color = rgb(54, 124, 130), material = M.Concrete },

	-- ===== Theme paints (Robux passes, docs/12 Stage 5): `pass` = the pass id in Config.Monetization that grants them. Never sold
	-- for cash and never shown in the Paint Bar shop; they appear in the Owned tab once the pass is owned. =====
	{ id = "WallArcade", name = "Arcade Midnight", kind = "Wall", price = 1, color = rgb(36, 30, 70), pass = "ThemeArcade" },
	{ id = "FloorArcade", name = "Arcade Carpet", kind = "Floor", price = 1, color = rgb(72, 42, 112), material = M.Concrete, pass = "ThemeArcade" },
	{ id = "WallCabin", name = "Cabin Honey", kind = "Wall", price = 1, color = rgb(184, 134, 88), pass = "ThemeCabin" },
	{ id = "FloorCabin", name = "Cabin Planks", kind = "Floor", price = 1, color = rgb(122, 80, 50), material = M.WoodPlanks, pass = "ThemeCabin" },
}

Paints.BY_ID = {}
for _, paint in Paints.LIST do
	Paints.BY_ID[paint.id] = paint
end

-- The look every wall / floor has when the owner has NOT chosen a paint (and in shops nobody owns). ONE look for the main shop, the
-- second storey, the Back Room and the Showroom, so they always match. A floor default also retires the textured main-floor overlay
-- (see Shared.PlotTargets): all floors are the same planks. Change these two entries to restyle every shop's default at once.
Paints.DEFAULTS = {
	Wall = { color = rgb(236, 246, 238) }, -- the main walls' own tint (the wall texture shows through it)
	Floor = { color = rgb(255, 233, 176), material = M.WoodPlanks }, -- the main plank slab's classic look
}

Paints.KINDS = { "Wall", "Floor" }
-- the save field (data.paints.<field>) that holds the paint in use for each kind
Paints.FIELD = { Wall = "wall", Floor = "floor" }

-- How close (studs) a player must be to Workspace.PaintCounter to buy.
Paints.BuyMaxStuds = 20

return Paints
