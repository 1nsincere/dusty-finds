-- Stock.luau (ReplicatedStorage.Shared.Config.Stock)
-- Purpose: the restock rules of the skins stall (docs/10_Stock_Shop_And_Skins.md): how often new stock arrives and how
-- likely each rarity is to be in it. Data only; the rolling is done by Shared.Stock.
-- Owner: Dev 1 (Ace) for the numbers (tune freely); Dev 3 (Sean) wrote the first version. Depends on: nothing.

local Stock = {
	RestockSeconds = 300, -- new stock every 5 minutes, the same moment on every server
	Seed = 20261124, -- changing it reshuffles every future restock

	-- Chance (0..1) that ONE skin of this rarity is in stock, rolled separately for shelves and for pedestals.
	-- About how often (5-minute restocks, per kind): Rare ~every 12 min, Epic ~28 min, Legendary ~70 min,
	-- Relic ~2.8 h, Mythic ~5.5 h.
	RarityChance = {
		Common = 1.0,
		Uncommon = 0.7,
		Rare = 0.4,
		Epic = 0.18,
		Legendary = 0.07,
		Relic = 0.03,
		Mythic = 0.015,
	},

	-- Rarities that get a server-wide "in stock!" message when they show up.
	AnnounceRarities = { Legendary = true, Relic = true, Mythic = true },

	-- How close (studs) a player must be to the stall to buy (the window can be opened from the stall only).
	BuyMaxStuds = 20,
}

return Stock
