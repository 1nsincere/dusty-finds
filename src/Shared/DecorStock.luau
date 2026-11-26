-- DecorStock.luau (ReplicatedStorage.Shared.DecorStock)
-- Purpose: which decor pieces are in stock right now. Decor upgrades with a `rarity` (Config/Upgrades, tab "Decor") are only sold while they
-- are in stock; the nicer the piece, the rarer it is and the lower its chance of being in stock (the chances are Config/Stock.RarityChance,
-- the same table as the skins stall). Like the skins stall, the stock is a pure function of the restock number (time / RestockSeconds) and
-- the seed, so every server and client agrees without sending anything; UpgradeService checks every purchase against it.
-- Owner: Dev 1 (Ace). Depends on: Config.Stock, Config.Upgrades. Time: server os.time(); client workspace:GetServerTimeNow().

local Config = script.Parent:WaitForChild("Config")
local StockConfig = require(Config:WaitForChild("Stock"))
local Upgrades = require(Config:WaitForChild("Upgrades"))

local DecorStock = {}

DecorStock.SEED_OFFSET = 1013 -- so decor restocks are not the same dice as the skins stall

function DecorStock.restockIndex(now: number): number
	return math.floor(now / StockConfig.RestockSeconds)
end

function DecorStock.secondsLeft(now: number): number
	return StockConfig.RestockSeconds - (now % StockConfig.RestockSeconds)
end

-- Is this upgrade sold through the decor stock? (a Decor upgrade that has a rarity)
function DecorStock.isStocked(def: any): boolean
	return def ~= nil and def.tab == "Decor" and type(def.rarity) == "string"
end

local function idNumber(id: string): number
	local n = 7
	for i = 1, #id do
		n = (n * 31 + string.byte(id, i)) % 1000003
	end
	return n
end

-- In stock in this restock? Each piece is rolled on its own with its rarity's chance (Common 100%, Uncommon 70%, Rare 40%, Epic 18% ...).
function DecorStock.inStock(index: number, upgradeId: string): boolean
	local def = Upgrades[upgradeId]
	if not DecorStock.isStocked(def) then
		return true -- not a stocked piece: always for sale
	end
	local chance = StockConfig.RarityChance[def.rarity] or 0
	local rng = Random.new(index * 7919 + StockConfig.Seed + DecorStock.SEED_OFFSET + idNumber(upgradeId))
	return rng:NextNumber() < chance
end

return DecorStock
