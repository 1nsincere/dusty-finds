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
	CheckoutBonusFraction = 0.10, -- +10% if the owner taps Checkout before auto-checkout
	AutoCheckoutSeconds = 8,

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
	MaxLevel = 15, -- MVP cap
	XpBase = 40, -- XP from level L to L+1 = round(XpBase x L^XpExponent)
	XpExponent = 1.6,
	LevelUpRewardPerLevel = 50, -- cash = 50 x new level

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
