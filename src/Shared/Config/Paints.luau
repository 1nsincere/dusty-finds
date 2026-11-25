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
}

Paints.BY_ID = {}
for _, paint in Paints.LIST do
	Paints.BY_ID[paint.id] = paint
end

Paints.KINDS = { "Wall", "Floor" }
-- the save field (data.paints.<field>) that holds the paint in use for each kind
Paints.FIELD = { Wall = "wall", Floor = "floor" }

-- How close (studs) a player must be to Workspace.PaintCounter to buy.
Paints.BuyMaxStuds = 20

return Paints
