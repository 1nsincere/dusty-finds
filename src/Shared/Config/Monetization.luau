-- Monetization.luau (ReplicatedStorage.Shared.Config.Monetization)
-- Purpose: every Robux product in one place (docs/11, docs/12 Stage 5, approved by Ace 2026-11-25): game passes (permanent) and
-- developer products (the tip jar). DATA ONLY: prices and ids can be changed without touching code.
-- Owner: Dev 1 (Ace). Read by: MonetizationService (server: prompt, check, grant), the Collector's Corner window, the effects.
--
-- RULES THAT NEVER CHANGE (docs/11 section 2 and 11): nothing here gives cash, XP, speed or better odds; nothing is random;
-- every cosmetic can also be earned in the game where one exists (themes are the exception: they are whole-shop looks sold as
-- passes); prices are shown in Robux up front with a Preview. Passes can't be deleted once created on Roblox, so keep them off sale
-- until the Creator Dashboard setup is done.
--
-- `passId` / `productId` = the Roblox id from the Creator Dashboard. 0 = NOT CREATED YET: the stall shows "Coming soon" and the
-- server refuses to prompt it. Fill the ids in after the passes exist. `price` is the Robux price shown in the window and must
-- match the price set on Roblox (Roblox charges the dashboard price, not this one).

local Monetization = {}

Monetization.PASSES = {
	{ id = "ThemeArcade", kind = "Theme", name = "Theme: Retro Arcade", price = 149, passId = 0,
		blurb = "Neon pink and midnight blue: matching walls, floor, shelves, pedestals and counter for your whole shop.",
		grants = { paints = { "WallArcade", "FloorArcade" }, skins = { "ShelfArcade", "PedestalArcade", "CashierArcade" } } },
	{ id = "ThemeCabin", kind = "Theme", name = "Theme: Cozy Cabin", price = 149, passId = 0,
		blurb = "Warm logs and honey wood: matching walls, floor, shelves, pedestals and counter.",
		grants = { paints = { "WallCabin", "FloorCabin" }, skins = { "ShelfCabin", "PedestalCabin", "CashierCabin" } } },
	{ id = "GlowPack", kind = "Effect", name = "Restoration Glow Pack", price = 99, passId = 0,
		blurb = "Golden sparkles when you finish restoring and a shower of confetti when you open a box. Looks only: same speed, same score." },
	{ id = "SavedLayouts", kind = "Convenience", name = "Saved Layouts", price = 149, passId = 0,
		blurb = "Save 3 shop layouts in Edit Mode and switch between them in one tap." },
	{ id = "Companion", kind = "Pet", name = "Shopkeeper's Companion", price = 199, passId = 0,
		blurb = "A little friend that follows you around the market and your shop. Everyone can see it." },
	{ id = "BigStorage", kind = "Convenience", name = "Big Storage Room", price = 149, passId = 0, storageSlots = 16,
		blurb = "+16 inventory slots. (You can also grow your storage with Storage Racks in the game.)" },
	{ id = "VIP", kind = "VIP", name = "VIP", price = 349, passId = 0,
		blurb = "Choose a pet, a title, an aura style and a nameplate colour, plus 1 extra saved layout and the VIP corner. Looks only: never cash, XP, speed or odds." },
}

-- The tip jar (developer products, can be bought again and again): a thank-you toast, never a gameplay effect.
Monetization.PRODUCTS = {
	{ id = "TipSmall", name = "Tip the team", price = 25, productId = 0 },
	{ id = "TipMedium", name = "Big thanks!", price = 100, productId = 0 },
	{ id = "TipLarge", name = "You're amazing!", price = 250, productId = 0 },
}

-- ===== VIP choices (cosmetic only) =====
-- The server checks every choice against these lists (and filters a custom title with Roblox's text filter).
Monetization.VIP = {
	Pets = {
		{ id = "Cat", name = "Cat", color = Color3.fromRGB(240, 170, 90) },
		{ id = "Bunny", name = "Bunny", color = Color3.fromRGB(245, 240, 236) },
		{ id = "Pup", name = "Pup", color = Color3.fromRGB(190, 140, 96) },
	},
	PetColors = {
		{ id = "Default", name = "Natural", color = nil },
		{ id = "Pink", name = "Pink", color = Color3.fromRGB(255, 170, 205) },
		{ id = "Sky", name = "Sky", color = Color3.fromRGB(150, 200, 255) },
		{ id = "Mint", name = "Mint", color = Color3.fromRGB(160, 230, 190) },
		{ id = "Gold", name = "Gold", color = Color3.fromRGB(245, 205, 90) },
	},
	-- aura STYLES recolour the sparkles; the tier (earned) still decides how strong the aura is
	AuraStyles = {
		{ id = "Gold", name = "Gold Dust", color = Color3.fromRGB(255, 208, 92) },
		{ id = "Sakura", name = "Sakura Petals", color = Color3.fromRGB(255, 170, 205) },
		{ id = "Parol", name = "Parol Glow", color = Color3.fromRGB(255, 120, 80) },
		{ id = "Ube", name = "Ube Violet", color = Color3.fromRGB(176, 140, 235) },
		{ id = "Pandan", name = "Pandan Green", color = Color3.fromRGB(130, 210, 140) },
	},
	TitleMaxLength = 20,
	-- preset titles that need no text filtering
	Titles = { "Treasure Hunter", "Dust Whisperer", "Master Restorer", "Antique Lover", "Shop Keeper", "Collector" },
}

-- ===== Saved layouts (Edit Mode) =====
Monetization.SavedLayoutSlots = 3 -- the Saved Layouts pass
Monetization.VipExtraSlots = 1 -- VIP adds one more (on top of the pass if you have both)

-- How many layout slots a player has (0 = none). `entitlements` = data.entitlements. One copy for the server and the UI.
function Monetization.layoutSlots(entitlements: any): number
	if type(entitlements) ~= "table" then
		return 0
	end
	local n = 0
	if entitlements.SavedLayouts == true then
		n += Monetization.SavedLayoutSlots
	end
	if entitlements.VIP == true then
		n += Monetization.VipExtraSlots
	end
	return n
end

Monetization.BY_PASS = {}
for _, pass in Monetization.PASSES do
	Monetization.BY_PASS[pass.id] = pass
end
Monetization.BY_PRODUCT = {}
for _, product in Monetization.PRODUCTS do
	Monetization.BY_PRODUCT[product.id] = product
end

return Monetization
