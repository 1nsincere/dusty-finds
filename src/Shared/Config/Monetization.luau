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
		grants = { paints = { "WallArcade", "FloorArcade", "TrimArcade", "AccentArcade" }, skins = { "ShelfArcade", "PedestalArcade", "CashierArcade" } } },
	{ id = "ThemeCabin", kind = "Theme", name = "Theme: Cozy Cabin", price = 149, passId = 0,
		blurb = "Warm logs and honey wood: matching walls, floor, shelves, pedestals and counter.",
		grants = { paints = { "WallCabin", "FloorCabin", "TrimCabin", "AccentCabin" }, skins = { "ShelfCabin", "PedestalCabin", "CashierCabin" } } },
	-- Christmas (Filipino Pasko): two whole-shop looks (Parol Pasko and Noche Buena) plus the parol, wreath and belen for the front of the
	-- shop (Facade.Decor_Pasko, shown in December by SeasonService). The parol string lights are free for everyone in December.
	{ id = "ThemePasko", kind = "Theme", name = "Theme: Pasko Pack", price = 149, passId = 0,
		blurb = "Two Christmas looks: Parol Pasko (cream, deep red and gold) and Noche Buena (pine green and gold), plus a glowing parol, a wreath and a belen for your door.",
		grants = { paints = { "WallPasko", "FloorPasko", "TrimPasko", "AccentPasko", "WallNoche", "FloorNoche", "TrimNoche", "AccentNoche" }, skins = {} } },
	{ id = "GlowPack", kind = "Effect", name = "Restoration Glow Pack", price = 99, passId = 0,
		blurb = "Golden sparkles when you finish restoring and a shower of confetti when you open a box. Looks only: same speed, same score." },
	{ id = "SavedLayouts", kind = "Convenience", name = "Saved Layouts", price = 149, passId = 0, hidden = true, -- hidden while Edit mode is paused (2026-11-26); remove `hidden` when it returns
		blurb = "Save 3 shop layouts in Edit Mode and switch between them in one tap." },
	{ id = "Companion", kind = "Pet", name = "Shopkeeper's Companion", price = 199, passId = 0,
		blurb = "A little friend that follows you around the market and your shop. Everyone can see it." },
	{ id = "BigStorage", kind = "Convenience", name = "Big Storage Room", price = 149, passId = 0, storageSlots = 16,
		blurb = "+16 inventory slots. (You can also grow your storage with Storage Racks in the game.)" },
	{ id = "VIP", kind = "VIP", name = "VIP", price = 349, passId = 0,
		blurb = "Choose a pet, a title, an aura style and a nameplate colour. Looks only: never cash, XP, speed or odds." },
}

-- The tip jar (developer products, can be bought again and again): a thank-you toast, never a gameplay effect.
Monetization.PRODUCTS = {
	{ id = "TipSmall", name = "Tip the team", price = 25, productId = 0 },
	{ id = "TipMedium", name = "Big thanks!", price = 100, productId = 0 },
	{ id = "TipLarge", name = "You're amazing!", price = 250, productId = 0 },
}

-- ===== Premium paints and sets (Robux, docs/12 Premium tab): developer products that GIVE paints for good (the receipt handler saves them
-- before it confirms the purchase). Single paints 25-49 R$, sets 99-119 R$. Cosmetic only; every paint also has `earnTier` rules in Config.Paints
-- where it can be earned. productId 0 = not created on Roblox yet ("Coming soon"). Names and prices here are what Roblox should be set to. =====
local PREMIUM = {
	{ paint = "WallPremPearl", name = "Capiz Pearl Wall", price = 39, productId = 0 },
	{ paint = "WallPremMarble", name = "Machuca Marble Wall", price = 49, productId = 0 },
	{ paint = "WallPremVelvet", name = "Ube Velvet Wall", price = 39, productId = 0 },
	{ paint = "FloorPremMarble", name = "Machuca Marble Floor", price = 35, productId = 0 },
	{ paint = "FloorPremGranite", name = "Mayon Granite Floor", price = 29, productId = 0 },
	{ paint = "TrimPremBrass", name = "Brushed Brass Trim", price = 29, productId = 0 },
	{ paint = "TrimPremGold", name = "Gold-Leaf Trim", price = 35, productId = 0 },
	{ paint = "AccentPremBrass", name = "Barako Brass Accent", price = 25, productId = 0 },
	{ paint = "AccentPremVelvet", name = "Ube Velvet Accent", price = 25, productId = 0 },
}
for _, entry in PREMIUM do
	table.insert(Monetization.PRODUCTS, { id = "Paint" .. entry.paint, kind = "Paint", name = entry.name, price = entry.price, productId = entry.productId, paints = { entry.paint } })
end
table.insert(Monetization.PRODUCTS, { id = "SetPearl", kind = "PaintSet", name = "Capiz Pearl Set", price = 99, productId = 0,
	blurb = "Pearl walls, a marble floor, brass trim and a brass accent: one matching look.",
	paints = { "WallPremPearl", "FloorPremMarble", "TrimPremBrass", "AccentPremBrass" } })
table.insert(Monetization.PRODUCTS, { id = "SetVelvet", kind = "PaintSet", name = "Ube Velvet Set", price = 119, productId = 0,
	blurb = "Velvet walls, a granite floor, gold-leaf trim and a velvet accent: one matching look.",
	paints = { "WallPremVelvet", "FloorPremGranite", "TrimPremGold", "AccentPremVelvet" } })

-- ===== Skin vouchers (Robux, docs/12): "buy it now" for skins instead of waiting for the stock roll. A voucher is a developer product that
-- gives ONE voucher of its tier (saved in data.vouchers); at the skins stall you redeem it for ANY skin of that rarity (no randomness, you see
-- the skin first). Epic 49 R$, Legendary 99 R$. Theme / pass skins are not redeemable. Cosmetic only. productId 0 = "Coming soon". =====
Monetization.VOUCHER_TIERS = { "Epic", "Legendary" }
table.insert(Monetization.PRODUCTS, { id = "VoucherEpic", kind = "Voucher", tier = "Epic", name = "Epic Skin Voucher", price = 49, productId = 0,
	blurb = "Choose any Epic skin for your shop, right now, without waiting for the stock." })
table.insert(Monetization.PRODUCTS, { id = "VoucherLegendary", kind = "Voucher", tier = "Legendary", name = "Legendary Skin Voucher", price = 99, productId = 0,
	blurb = "Choose any Legendary skin for your shop, right now, without waiting for the stock." })

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
