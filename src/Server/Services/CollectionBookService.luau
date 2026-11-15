-- CollectionBookService.luau
-- Purpose: the collection book (found / best stars / golden per item) and the shop rating (points -> 1-5 stars).
-- Owner: Dev 1 (Ace). Depends on: DataService, Shared.Config (Items, Rarities, Upgrades, Economy), Shared.Formulas.
-- Rating points = decor + expansions (from upgrade levels) + exhibited items (rarity points, Golden x2), docs/02 §6.
-- Page-completion rewards are NOT built yet (they need the Collection UI, Dev 3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local CollectionBookService = {}
local lastRating: { [any]: number } = {} -- [Player] = last stars sent
local DEBUG = true
local log = Log.new("CollectionBookService", DEBUG)

local DataService = nil

-- Marks an item as found. Returns true if this is the FIRST time the player found it (for the NEW! tag and the
-- first-find bonus), false if already known, nil if the item id or profile is invalid.
function CollectionBookService.RecordFound(player: Player, itemId: string, golden: boolean?): boolean?
	if not Validate.isConfigId(itemId, Items) then
		return nil
	end
	local path = "collection." .. itemId
	local entry = DataService.GetValue(player, path)
	if entry == nil then
		if DataService.GetValue(player, "collection") == nil then
			return nil -- profile not loaded
		end
		DataService.Set(player, path, { found = true, bestStars = 0, golden = golden == true })
		return true
	end
	if golden == true and entry.golden ~= true then
		DataService.Set(player, path .. ".golden", true)
	end
	return false
end

-- Called when an item is restored (Dev 2's RestorationService): keeps the best star rating, marks Golden.
function CollectionBookService.RecordRestored(player: Player, itemId: string, stars: number, golden: boolean?): boolean
	if not Validate.isConfigId(itemId, Items) or not Validate.isInteger(stars, 1, 3) then
		return false
	end
	local path = "collection." .. itemId
	local entry = DataService.GetValue(player, path)
	if entry == nil then
		if CollectionBookService.RecordFound(player, itemId, golden) == nil then
			return false
		end
		entry = DataService.GetValue(player, path)
	end
	if entry == nil then
		return false
	end
	if stars > (entry.bestStars or 0) then
		DataService.Set(player, path .. ".bestStars", stars)
	end
	if golden == true and entry.golden ~= true then
		DataService.Set(player, path .. ".golden", true)
	end
	return true
end

-- Upgrade effect.ratingPoints is a list (one value per level owned) for decor, or a single number for expansions.
local function upgradePoints(upgrades: { [string]: number }): number
	local total = 0
	for id, level in upgrades do
		local def = Upgrades[id]
		local points = def and def.effect.ratingPoints
		if level > 0 and points ~= nil then
			if type(points) == "table" then
				total += points[math.min(level, #points)] or 0
			elseif type(points) == "number" then
				total += points
			end
		end
	end
	return total
end

local function exhibitPoints(inventory: { [string]: any }): number
	local total = 0
	for _, item in inventory do
		if item.state == "Exhibited" then
			local def = Items[item.itemId]
			local rarity = def and Rarities[def.rarity]
			if rarity then
				total += rarity.exhibitPoints * (if item.golden then Economy.GoldenExhibitPointsMult else 1)
			end
		end
	end
	return total
end

function CollectionBookService.GetRatingPoints(player: Player): number
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	local inventory = DataService.GetValue(player, "inventory") or {}
	return upgradePoints(upgrades) + exhibitPoints(inventory)
end

function CollectionBookService.GetRatingStars(player: Player): number
	return Formulas.ratingStars(CollectionBookService.GetRatingPoints(player))
end

-- Tells the client its shop rating (stars) when it changed. Call after upgrades are bought or exhibits change.
function CollectionBookService.RefreshRating(player: Player)
	local stars = CollectionBookService.GetRatingStars(player)
	if lastRating[player] ~= stars then
		lastRating[player] = stars
		if DataService.Push then
			DataService.Push(player, "rating", stars)
		end
	end
end

function CollectionBookService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function CollectionBookService.Start()
	if DataService.AddSnapshotExtra then
		DataService.AddSnapshotExtra("rating", function(player)
			lastRating[player] = CollectionBookService.GetRatingStars(player)
			return lastRating[player]
		end)
	end
	DataService.OnPlayerReleasing(function(player)
		lastRating[player] = nil
	end)
	log.info("Start (no remotes: other services call this one)")
end

return CollectionBookService
