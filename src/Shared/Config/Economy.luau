-- Economy.luau (ReplicatedStorage.Shared.Config.Economy)
-- Purpose: global economy numbers. Every value comes from docs/02_Economy.md (section noted per block).
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Services and UI read these numbers; never hardcode them elsewhere (CLAUDE.md §4 rule 3).

local Economy = {
	-- §1 Starting state
	StartingCash = 100,
	StartingInventoryCapacity = 8,
	StartingDisplaySlots = 3,
	StartingExhibitPedestals = 4, -- was 1 (Sean, 2026-11-24): all 4 downstairs pedestals usable; they move into the Back Room once it's bought
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
	-- Dispose (2026-11-25): throw away a Dirty (not yet restored) item to free storage. Pays DisposeFraction of its estimated
	-- value (the same "Est. value" the cards show = price at DisposeEstimateStars), rounded down, at least DisposeMinimum.
	DisposeFraction = 0.4,
	DisposeEstimateStars = 2,
	DisposeMinimum = 1,
	DisposeMaxPerRequest = 40, -- most items one RequestDisposeItems may carry (inventory is at most 40 anyway)
	-- Auto sell (Sean, Ace OK 2026-11-25): rarities a player MAY switch on in Settings. A new item of a switched-on rarity
	-- is sold the moment its box opens, at the Dispose price, and never takes a slot. Each one is a setting
	-- "autoSell<Rarity>" (default OFF). Legendary and up are left out on purpose, and Golden items are never auto-sold.
	AutoSellRarities = { "Common", "Uncommon", "Rare", "Epic" },
	TipBaseChance = 0.05, -- chance = 5% + 5% x rating stars
	TipChancePerRatingStar = 0.05,
	TipMinFraction = 0.10, -- tip amount = 10-25% of price
	TipMaxFraction = 0.25,
	CheckoutBonusFraction = 0.10, -- +10% if the owner serves at the till and gives the right change first try
	AutoCheckoutSeconds = 20, -- RETIRED 2026-11-25: customers no longer pay by themselves (see QueuePatienceSeconds); kept so old tools still read it
	-- Customers decide, they do not just buy (2026-11-25). At the shelf a customer looks at the item, then buys it, says "let me think
	-- about it" (and may come back), or passes with a critique. The chance of buying depends on the SHOP RATING (a better shop sells
	-- more), a little on the item's stars, and on whether it is what they wished for. At the counter they wait for the owner.
	BuyChanceByRating = { 0.72, 0.78, 0.84, 0.90, 0.95 }, -- index = shop rating stars (1-5): only a gentle factor, never a gate
	BuyChanceWish = 0.12, -- + if the item matches their wish
	BuyChanceItemStars = { -0.12, 0, 0.08 }, -- index = the item's restore stars (1-3)
	ThinkShare = 0.6, -- of the "no" rolls, this share says "let me think about it" (the rest pass with a critique)
	ThinkReturnChance = 0.5, -- a thinker comes back this often...
	ThinkReturnBonus = 0.25, -- ...and is then this much more likely to buy
	ThinkAwaySeconds = { 8, 20 }, -- how long a thinker wanders off
	QueuePatienceSeconds = 90, -- an unserved customer at the front of the counter leaves after this, without buying
	QueueHelloSeconds = { 30, 60 }, -- "Hello?" and "Excuse me!" bubbles while waiting
	-- Haggling (2026-11-25): some customers ask for a discount at the till. The owner taps Accept (sells at the lower price, no risk) or
	-- Decline: the customer leaves without buying with a chance of (discount x HaggleLeaveFactor), otherwise pays full price but never tips.
	-- Factor < 1 makes declining the slightly better bet, accepting the safe one. Customers.<type>.haggleChance / haggleDiscount set who asks.
	HaggleLeaveFactor = 0.8,
	HaggleStep = 0.05, -- discounts are rounded to steps of 5%
	HaggleRepeatSeconds = { 10, 18 }, -- the haggler repeats the ask this often while waiting for an answer
	-- Cashier till: the customer pays with a rounder amount; the owner counts out the change with these bills.
	CashierPayRoundTo = { 5, 10, 20, 50, 100 }, -- the customer's payment = price rounded UP to one of these (always > price)
	CashierBills = { 1, 5, 10, 20, 50 }, -- the buttons in the till
	CashierMaxChange = 10000, -- validation cap for RequestGiveChange
	-- Cashier speed and mistakes (Dev 3, team decision 2026-11-23). Fractions are of the price, like CheckoutBonusFraction.
	CashierFastSeconds = 8, -- right change this quickly after the till opens, first try = the fast bonus
	CashierFastBonusFraction = 0.25, -- +25% fast and right first time (right first time but slower = CheckoutBonusFraction)
	CashierMaxMistakes = 2, -- 1st wrong change: no bonus, the customer is upset. 2nd: they get angry, pay less and leave
	CashierAngryPenaltyFraction = -0.10, -- an angry customer pays 10% under the price

	-- Special pulls (docs/02 §3b): two surprises on top of the normal odds.
	-- 1) LOST MASTERPIECE: chance per rolled item (by crate id) that the item is a Relic instead. Free Delivery never rolls one.
	--    About 1 in 500 Flea Market items (the Starter tier has no Relic); Relics are never Golden.
	-- Antique Dealer + Estate Sale (2026-11-25): about 1 in 200 and 1 in 67 items are Relics.
	RelicChance = { FleaMarket = 0.002, AntiqueDealer = 0.005, EstateSale = 0.015 },
	-- 1b) MYTHIC and SECRET (2026-11-20): rarer still, checked before the Relic pull. Never Golden.
	--     About 1 in 1,250 (Mythic) and 1 in 5,000 (Secret) Flea Market items.
	MythicChance = { FleaMarket = 0.0008, AntiqueDealer = 0.0015, EstateSale = 0.004 },
	SecretChance = { FleaMarket = 0.0002, AntiqueDealer = 0.0004, EstateSale = 0.001 },
	-- 2) TIME CAPSULE: chance per BOUGHT crate that it holds a sealed capsule: extra bonus items with better odds.
	TimeCapsuleChance = { FleaMarket = 0.03, Starter = 0.015, YardSale = 0.02, AntiqueDealer = 0.04, EstateSale = 0.06 },
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
	-- Upgrade tabs switched off (Sean + Ace, 2026-11-24): decor will be sold in a decor shop once the edit mode exists.
	-- A closed tab is hidden in the Upgrades window, refused by UpgradeService, and its decor models stay hidden.
	-- Levels already bought stay saved and keep their rating points. Remove the entry to switch the tab back on.
	ClosedUpgradeTabs = {}, -- Decor opened 2026-11-26 (the Cozy Living set); the old greybox decor items are comingSoon in Config/Upgrades

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
