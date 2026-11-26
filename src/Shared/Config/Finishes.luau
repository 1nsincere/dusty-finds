-- Finishes.luau (ReplicatedStorage.Shared.Config.Finishes)
-- Purpose: the premium surface finishes of the Robux Premium tab (docs/12): neutral textures (colour + relief) that a premium paint
-- puts on the shell's TEXTURED meshes (walls, trim, accents) instead of the plain plaster / wood grain. The paint's colour still tints them.
-- Owner: Dev 1 (Ace). The KEYS are what Config.Paints (`finish = "pearl"`) points at; PlotTargets clones the ready-made SurfaceAppearance from
-- ReplicatedStorage.ShellTextures.<key> (Studio-only folder, NOT in Git: rebuild it from ShopU_Finishes.glb with the ids below, plus plaster / woodgrain /
-- shingle cloned from the shell meshes). Game scripts cannot read or write SurfaceAppearance maps, so the ids here are for building those holders.
-- Made by tools/blender/finishes.py, carried in ShopU_Finishes.glb (model asset 90201813870632 in the group; the importer turned the embedded
-- pictures into the image assets below). `color` / `normal` = rbxassetid:// of the image; "" = none: the paint then falls back to its plain colour.

local Finishes = {}

Finishes.BY_KEY = {
	pearl = { name = "Capiz Pearl", color = "rbxassetid://83814642518062", normal = "rbxassetid://96882086703188" },
	velvet = { name = "Velvet", color = "rbxassetid://109149259239874", normal = "rbxassetid://71509866101197" },
	brass = { name = "Brushed Brass", color = "rbxassetid://117557370364341", normal = "rbxassetid://72821453677544" },
	goldleaf = { name = "Gold Leaf", color = "rbxassetid://103973573824396", normal = "rbxassetid://95607204064174" },
	marblewall = { name = "Marble", color = "rbxassetid://101089368215727", normal = "rbxassetid://120654504922511" },
}

return Finishes
