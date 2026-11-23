-- Economy.luau (ReplicatedStorage.Shared.Config.Economy)
-- Purpose: global economy numbers. Every value comes from docs/02_Economy.md (section noted per block).
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Services and UI read these numbers; never hardcode them elsewhere (CLAUDE.md §4 rule 3).

local Economy = {
	-- §1 Starting state
	StartingCash = 100,
	StartingInventoryCapacity = 8,
	StartingDisplaySlots = 3,
	StartingExhibitPedestals = 1,
	StartingWorkbenches = 1,
	FreeDeliveryIntervalSeconds = 180, -- 1 Tier-1 item every 3 minutes
	FreeDeliveryMaxWaiting = 1,
	FirstBoxItemId = "RubberDuck", -- guaranteed tutorial box at the door
	MaxWaitingBoxes = 3, -- docs/01 B1: at most 3 unopened boxes (one box = one crate purchase or one free delivery)
	InteractMaxStuds = 25, -- how close the character must be to a counter / delivery point for a request
	SupplyMaxStuds = 20, -- how close the character must be to the Warehouse supply counter to buy crates (RequestBuyCrate); the HUD box button and plot boards only point there

	-- §2 Rarity-related globals (per-rarity numbers live in Rarities.luau)
	GoldenChance = 0.02, -- 2% on any roll
	GoldenValueMult = 3,
	GoldenExhibitPointsMult = 2,
	Tier2XpMult = 2,

	-- §5 Selling prices: price = baseValue x qualityMult x variantMult x wishMult + tip
	QualityMult = { 0.8, 1.0, 1.3 }, -- index = stars (1, 2, 3)
	WishMult = 1.25,
	QuickSellFraction = 0.7, -- of baseValue x qualityMult x variantMult; no wish, no tip
	TipBaseChance = 0.05, -- chance = 5% + 5% x rating stars
	TipChancePerRatingStar = 0.05,
	TipMinFraction = 0.10, -- tip amount = 10-25% of price
	TipMaxFraction = 0.25,
	CheckoutBonusFraction = 0.10, -- +10% if the owner serves at the till and gives the right change first try
	AutoCheckoutSeconds = 20, -- an unserved customer pays by itself after this (exact money, no tip, no bonus)
	-- Cashier till: the customer pays with a rounder amount; the owner counts out the change with these bills.
	CashierPayRoundTo = { 5, 10, 20, 50, 100 }, -- the customer's payment = price rounded UP to one of these (always > price)
	CashierBills = { 1, 5, 10, 20, 50 }, -- the buttons in the till
	CashierMaxChange = 10000, -- validation cap for RequestGiveChange

	-- Special pulls (docs/02 §3b): two surprises on top of the normal odds.
	-- 1) LOST MASTERPIECE: chance per rolled item (by crate id) that the item is a Relic instead. Free Delivery never rolls one.
	--    About 1 in 500 Flea Market items (the Starter tier has no Relic); Relics are never Golden.
	RelicChance = { FleaMarket = 0.002 },
	-- 1b) MYTHIC and SECRET (2026-11-20): rarer still, checked before the Relic pull. Never Golden.
	--     About 1 in 1,250 (Mythic) and 1 in 5,000 (Secret) Flea Market items.
	MythicChance = { FleaMarket = 0.0008 },
	SecretChance = { FleaMarket = 0.0002 },
	-- 2) TIME CAPSULE: chance per BOUGHT crate that it holds a sealed capsule: extra bonus items with better odds.
	TimeCapsuleChance = { FleaMarket = 0.03, Starter = 0.015 },
	TimeCapsuleBonusItems = 2,
	TimeCapsuleOdds = { Rare = 60, Epic = 35, Legendary = 5 }, -- percentages, add up to 100

	-- §5 Customer flow
	CustomerSpawnBaseSeconds = 30,
	CustomerSpawnSignFactor = 0.9, -- interval x 0.9^(Shop Sign level)
	CustomerSpawnRatingMult = { 1.0, 0.9, 0.8, 0.7, 0.6 }, -- index = rating stars (1-5)
	CustomerSpawnMinSeconds = 10,
	MaxCustomers = 3,
	MaxCustomersShowroom = 5,

	-- §6 Shop rating: points -> stars. Index = stars, value = minimum points for that star.
	RatingStarMinPoints = { 0, 8, 20, 40, 65 },

	-- §7 XP and levels
	MaxLevel = 50, -- was 15 (2026-11-20)
	XpBase = 40, -- XP from level L to L+1 = round(XpBase x L^XpExponent)
	XpExponent = 1.6,
	LevelUpRewardPerLevel = 50, -- cash = 50 x new level

	-- §7 Likes (docs/02 §7, docs/01 E). 1 like per shop per visitor per UTC day; the owner's cash is capped per day.
	LikeReward = 25,
	LikeRewardMaxPerDay = 10,

	-- docs/01_GameDesign.md B8 Restoration quality (final = average of step scores + tool bonus, capped at 100)
	QualityThreeStarMin = 90, -- >= 90 -> 3 stars (Mint)
	QualityTwoStarMin = 70, -- >= 70 -> 2 stars (Good), else 1 star (Fair)
	MaxToolQualityBonus = 10,

	-- Item categories (docs/02 §4; used by customer wishes)
	Categories = { "Toys", "Kitchen", "Decor", "Music", "Electronics" },

	-- The six allowed recipe step types (docs/02 §4, docs/03 §7)
	StepTypes = { "Wipe", "Scrape", "Reassemble", "Replace", "Polish", "Test" },

	-- Minimum seconds per step type; faster reports are rejected (docs/03 §7)
	MinStepSeconds = { Wipe = 3, Scrape = 4, Reassemble = 3, Replace = 3, Polish = 4, Test = 1 },
}

return Economy
