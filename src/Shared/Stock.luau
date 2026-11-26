-- Stock.luau (ReplicatedStorage.Shared.Stock)
-- Purpose: what the skins stall has in stock right now. The stock is a pure function of the restock number
-- (time / RestockSeconds) and Config.Stock.Seed, so every server and every client gets the SAME list without sending it
-- over the network; the server still checks every purchase against it (SkinService), so a client can't invent stock.
-- Owner: Dev 3 (Sean). Depends on: Shared.Config (Stock, Skins, Rarities).
-- Time: the server passes os.time(); a client passes workspace:GetServerTimeNow() (the server's clock).

local Config = script.Parent:WaitForChild("Config")
local StockConfig = require(Config:WaitForChild("Stock"))
local Skins = require(Config:WaitForChild("Skins"))
local Rarities = require(Config:WaitForChild("Rarities"))

local Stock = {}

-- Which restock we are in (an integer that goes up by 1 every RestockSeconds).
function Stock.restockIndex(now: number): number
	return math.floor(now / StockConfig.RestockSeconds)
end

-- Seconds until the next restock.
function Stock.secondsLeft(now: number): number
	return StockConfig.RestockSeconds - (now % StockConfig.RestockSeconds)
end

-- Skins grouped by kind and rarity, in a fixed order (sorted ids) so the roll is the same everywhere.
local pools: { [string]: { [string]: { string } } } = {}
for _, skin in Skins.LIST do
	if skin.pass == nil then -- pass-only theme skins (Config.Monetization) are never in stock
		pools[skin.kind] = pools[skin.kind] or {}
		pools[skin.kind][skin.rarity] = pools[skin.kind][skin.rarity] or {}
		table.insert(pools[skin.kind][skin.rarity], skin.id)
	end
end
for _, byRarity in pools do
	for _, ids in byRarity do
		table.sort(ids)
	end
end

local function raritiesInOrder(): { string }
	local list = {}
	for name in StockConfig.RarityChance do
		table.insert(list, name)
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities[a], Rarities[b]
		return (ra and ra.index or 99) < (rb and rb.index or 99)
	end)
	return list
end
local RARITY_ORDER = raritiesInOrder()
Stock.RARITY_ORDER = RARITY_ORDER -- commonest first; the window shows one card per kind and rarity in this order

-- The skin ids in stock for a restock number: per kind, each rarity is rolled once; a hit puts one skin of that
-- rarity in stock. Returned in display order (shelves first, commonest first).
function Stock.roll(index: number): { string }
	local rng = Random.new(index * 7919 + StockConfig.Seed)
	local out = {}
	for _, kind in Skins.KINDS do
		for _, rarity in RARITY_ORDER do
			local chance = StockConfig.RarityChance[rarity] or 0
			local pool = pools[kind] and pools[kind][rarity]
			-- roll every rarity even when its pool is empty, so adding a skin later doesn't reshuffle the others
			local hit = rng:NextNumber() < chance
			local pick = rng:NextInteger(1, 1000)
			if hit and pool and #pool > 0 then
				table.insert(out, pool[(pick - 1) % #pool + 1])
			end
		end
	end
	return out
end

-- Is this skin in stock in this restock?
function Stock.isInStock(index: number, skinId: string): boolean
	return table.find(Stock.roll(index), skinId) ~= nil
end

return Stock
