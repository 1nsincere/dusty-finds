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

	-- ===== Trim (window frames, pilasters, belt course, shutters' frames): mostly calm neutrals so the edges always read =====
	{ id = "TrimCapiz", name = "Capiz Trim", kind = "Trim", price = 150, color = rgb(240, 232, 214) },
	{ id = "TrimSampaguita", name = "Sampaguita Trim", kind = "Trim", price = 150, color = rgb(247, 244, 236) },
	{ id = "TrimBigas", name = "Bigas Cream", kind = "Trim", price = 150, color = rgb(232, 226, 205) },
	{ id = "TrimCoral", name = "Coral Limestone", kind = "Trim", price = 200, color = rgb(214, 208, 196) },
	{ id = "TrimBrass", name = "Brushed Brass", kind = "Trim", price = 250, color = rgb(176, 140, 70) },
	{ id = "TrimNarra", name = "Narra Brown", kind = "Trim", price = 250, color = rgb(122, 86, 60) },
	{ id = "TrimUling", name = "Uling Charcoal", kind = "Trim", price = 250, color = rgb(62, 64, 68) },
	{ id = "TrimKamagong", name = "Kamagong Dark", kind = "Trim", price = 300, color = rgb(70, 48, 36) },

	-- ===== Accent (door frame, sign frame, awnings, shutters): the bold, small touches =====
	{ id = "AccentPandan", name = "Pandan Accent", kind = "Accent", price = 200, color = rgb(96, 140, 104) },
	{ id = "AccentHoney", name = "Golden Honey", kind = "Accent", price = 200, color = rgb(212, 163, 74) },
	{ id = "AccentKalamansi", name = "Ripe Kalamansi", kind = "Accent", price = 250, color = rgb(217, 155, 38) },
	{ id = "AccentTerracotta", name = "Terracotta", kind = "Accent", price = 250, color = rgb(200, 109, 81) },
	{ id = "AccentSantan", name = "Santan Accent", kind = "Accent", price = 300, color = rgb(214, 106, 92) },
	{ id = "AccentBrick", name = "Brick Red", kind = "Accent", price = 300, color = rgb(168, 74, 58) },
	{ id = "AccentTeal", name = "Deep Teal", kind = "Accent", price = 350, color = rgb(47, 93, 98) },
	{ id = "AccentUbe", name = "Ube Jam", kind = "Accent", price = 350, color = rgb(126, 90, 140) },

	-- ===== Premium (Robux, docs/12 Premium tab): a finish (a texture on the shell's walls / trim / accents, see Config.Finishes) or a premium
	-- material (floors). Bought one by one for Robux (Config.Monetization product = `product`, price shown there) or in a set, never for cash
	-- (`premium = true`, price 1 is a placeholder). `earnTier` = also given for free when the player reaches that Collector tier (1 = Dusty ..
	-- 5 = Radiant), so nothing here is Robux-only for kids who play. Looks only. =====
	{ id = "WallPremPearl", name = "Capiz Pearl Wall", kind = "Wall", price = 1, color = rgb(238, 232, 238), finish = "pearl", premium = true, product = "PaintWallPremPearl" },
	{ id = "WallPremMarble", name = "Machuca Marble Wall", kind = "Wall", price = 1, color = rgb(250, 250, 250), finish = "marblewall", premium = true, product = "PaintWallPremMarble", earnTier = 5 },
	{ id = "WallPremVelvet", name = "Ube Velvet Wall", kind = "Wall", price = 1, color = rgb(140, 100, 170), finish = "velvet", premium = true, product = "PaintWallPremVelvet" },
	{ id = "FloorPremMarble", name = "Machuca Marble Floor", kind = "Floor", price = 1, color = rgb(240, 240, 236), material = M.Marble, premium = true, product = "PaintFloorPremMarble" },
	{ id = "FloorPremGranite", name = "Mayon Granite Floor", kind = "Floor", price = 1, color = rgb(104, 106, 112), material = M.Granite, premium = true, product = "PaintFloorPremGranite" },
	{ id = "TrimPremBrass", name = "Brushed Brass Trim", kind = "Trim", price = 1, color = rgb(214, 176, 96), finish = "brass", premium = true, product = "PaintTrimPremBrass" },
	{ id = "TrimPremGold", name = "Gold-Leaf Trim", kind = "Trim", price = 1, color = rgb(242, 204, 104), finish = "goldleaf", premium = true, product = "PaintTrimPremGold", earnTier = 4 },
	{ id = "AccentPremBrass", name = "Barako Brass Accent", kind = "Accent", price = 1, color = rgb(196, 150, 72), finish = "brass", premium = true, product = "PaintAccentPremBrass" },
	{ id = "AccentPremVelvet", name = "Ube Velvet Accent", kind = "Accent", price = 1, color = rgb(116, 74, 136), finish = "velvet", premium = true, product = "PaintAccentPremVelvet" },

	-- ===== Theme paints (Robux passes, docs/12 Stage 5): `pass` = the pass id in Config.Monetization that grants them. Never sold
	-- for cash and never shown in the Paint Bar shop; they appear in the Owned tab once the pass is owned. =====
	{ id = "WallArcade", name = "Arcade Midnight", kind = "Wall", price = 1, color = rgb(36, 30, 70), pass = "ThemeArcade" },
	{ id = "FloorArcade", name = "Arcade Carpet", kind = "Floor", price = 1, color = rgb(72, 42, 112), material = M.Concrete, pass = "ThemeArcade" },
	{ id = "WallCabin", name = "Cabin Honey", kind = "Wall", price = 1, color = rgb(184, 134, 88), pass = "ThemeCabin" },
	{ id = "FloorCabin", name = "Cabin Planks", kind = "Floor", price = 1, color = rgb(122, 80, 50), material = M.WoodPlanks, pass = "ThemeCabin" },
	{ id = "TrimArcade", name = "Arcade Lilac", kind = "Trim", price = 1, color = rgb(196, 176, 232), pass = "ThemeArcade" },
	{ id = "AccentArcade", name = "Arcade Pink", kind = "Accent", price = 1, color = rgb(232, 84, 160), pass = "ThemeArcade" },
	{ id = "TrimCabin", name = "Cabin Cream", kind = "Trim", price = 1, color = rgb(238, 222, 190), pass = "ThemeCabin" },
	{ id = "AccentCabin", name = "Cabin Pine", kind = "Accent", price = 1, color = rgb(74, 110, 80), pass = "ThemeCabin" },

	-- ===== Pasko (Christmas, docs/12): two looks in one pass. Parol Pasko = cream walls, deep red trim, gold accent; Noche Buena = pine
	-- green walls, cream trim, warm gold. Filipino Christmas: parol lanterns, red and gold, warm lights, no snow. =====
	{ id = "WallPasko", name = "Parol Cream", kind = "Wall", price = 1, color = rgb(241, 232, 216), pass = "ThemePasko" },
	{ id = "FloorPasko", name = "Pasko Planks", kind = "Floor", price = 1, color = rgb(107, 74, 54), material = M.WoodPlanks, pass = "ThemePasko" },
	{ id = "TrimPasko", name = "Parol Red", kind = "Trim", price = 1, color = rgb(143, 45, 43), pass = "ThemePasko" },
	{ id = "AccentPasko", name = "Parol Gold", kind = "Accent", price = 1, color = rgb(217, 164, 65), pass = "ThemePasko" },
	{ id = "WallNoche", name = "Noche Buena Green", kind = "Wall", price = 1, color = rgb(62, 107, 85), pass = "ThemePasko" },
	{ id = "FloorNoche", name = "Noche Buena Boards", kind = "Floor", price = 1, color = rgb(74, 56, 43), material = M.WoodPlanks, pass = "ThemePasko" },
	{ id = "TrimNoche", name = "Noche Buena Cream", kind = "Trim", price = 1, color = rgb(240, 230, 210), pass = "ThemePasko" },
	{ id = "AccentNoche", name = "Noche Buena Gold", kind = "Accent", price = 1, color = rgb(200, 150, 62), pass = "ThemePasko" },
}

Paints.BY_ID = {}
for _, paint in Paints.LIST do
	Paints.BY_ID[paint.id] = paint
end

-- The look every wall / floor has when the owner has NOT chosen a paint (and in shops nobody owns). ONE look for the main shop, the
-- second storey, the Back Room and the Showroom, so they always match. A floor default also retires the textured main-floor overlay
-- (see Shared.PlotTargets): all floors are the same planks. Change these two entries to restyle every shop's default at once.
Paints.DEFAULTS = {
	Wall = { color = rgb(234, 227, 213) }, -- Capiz Cream: warm plaster (the universal shop shell is plain grey, so this colour shows as is)
	Floor = { color = rgb(140, 102, 72), material = M.WoodPlanks }, -- Capiz Cream: narra planks
	Trim = { color = rgb(89, 62, 43) }, -- Capiz Cream: dark kamagong trim
	Accent = { color = rgb(201, 138, 75) }, -- Capiz Cream: warm brass accent
}

Paints.KINDS = { "Wall", "Floor", "Trim", "Accent" }
-- the save field (data.paints.<field>) that holds the paint in use for each kind
Paints.FIELD = { Wall = "wall", Floor = "floor", Trim = "trim", Accent = "accent" }
-- shown on the Paint Bar cards
Paints.KIND_LABEL = { Wall = "Wall paint", Floor = "Floor", Trim = "Trim paint", Accent = "Accent paint" }

-- How close (studs) a player must be to Workspace.PaintCounter to buy.
Paints.BuyMaxStuds = 20

return Paints
