-- UpgradeService.luau
-- Purpose: buys shop upgrades (tools, shelves, storage, sign, decor, expansions) through RequestBuyUpgrade.
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, PlotService, Shared.Config.Upgrades.
-- Validation order (docs/STATUS.md "Implementation requirements"): id -> next level exists -> player level ->
-- `requires` owned -> afford. Expansion MODELS (Back Room / Showroom from ServerStorage) are not cloned here yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local DecorStock = require(ReplicatedStorage.Shared.DecorStock)
local DecorRooms = require(ReplicatedStorage.Shared.Config.DecorRooms)
local Hours = require(ReplicatedStorage.Shared.Hours)
local CollectionService = game:GetService("CollectionService")


-- Decor is bought at its room's counter in the Warehouse Market (parts tagged DecorStall, attribute Room), while the market is open.
local function isNearDecorStall(player: Player, room: any): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	for _, part in CollectionService:GetTagged(DecorRooms.TAG) do
		if part:IsA("BasePart") and part:GetAttribute("Room") == room and (part.Position - root.Position).Magnitude <= DecorRooms.BuyMaxStuds then
			return true
		end
	end
	return false
end
local UpgradeService = {}
local DEBUG = true
local log = Log.new("UpgradeService", DEBUG)

local DataService, EconomyService, PlotService, CollectionBookService = nil, nil, nil, nil

local function notify(player: any, kind: string, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, kind, text)
	end
end

-- Returns ok, reason ("unknown", "closed", "outOfStock", "maxed", "level", "requires", "cash", "saveFailed"), newLevel.
function UpgradeService.BuyUpgrade(player: Player, upgradeId: string): (boolean, string?, number?)
	-- 1. exists in Config
	if not Validate.isConfigId(upgradeId, Upgrades) then
		return false, "unknown", nil
	end
	local def = Upgrades[upgradeId]
	-- 1b. its tab is switched off (Economy.ClosedUpgradeTabs: decor waits for the decor shop); the client hides it,
	-- but a hand-made request must be refused here too
	if (Economy.ClosedUpgradeTabs or {})[def.tab] then
		return false, "closed", nil
	end
	-- 1c. one upgrade switched off (comingSoon = true: the Showroom and Upper Back Room wait for the decor shop)
	if def.comingSoon then
		return false, "closed", nil
	end
	-- 1d. a decor piece is only sold while it is in the decor stock (the nicer the piece, the rarer: Shared/DecorStock)
	if DecorStock.isStocked(def) and not DecorStock.inStock(DecorStock.restockIndex(os.time()), upgradeId) then
		return false, "outOfStock", nil
	end
	local data = DataService.Get(player)
	if data == nil then
		return false, "noData", nil
	end

	-- 2. the next level exists
	local owned = data.upgrades[upgradeId] or 0
	local nextLevel = owned + 1
	if nextLevel > def.maxLevel then
		return false, "maxed", nil
	end

	-- 3. player level
	if data.level < def.requiredLevel[nextLevel] then
		return false, "level", nil
	end

	-- 4. `requires`: requiredLevel alone is not enough (all decor is level 1)
	if def.requires and (data.upgrades[def.requires] or 0) < 1 then
		return false, "requires", nil
	end

	-- 5. afford + pay (Spend checks again and can't be raced), then save the new level; refund if saving fails
	local cost = def.costs[nextLevel]
	if not EconomyService.Spend(player, cost, "Shop", upgradeId) then
		return false, "cash", nil
	end
	if not DataService.Set(player, "upgrades." .. upgradeId, nextLevel) then
		EconomyService.AddCash(player, cost, "Refund")
		return false, "saveFailed", nil
	end
	Analytics.Step(player, Analytics.STEP.BoughtUpgrade)

	PlotService.RefreshSlots(player) -- shelves / showroom change which slots are enabled
	CollectionBookService.RefreshRating(player)
	notify(player, "Upgrade", `{def.name} level {nextLevel}`)
	log.info(`bought {upgradeId} level {nextLevel} for ${cost}`)
	return true, nil, nextLevel
end

function UpgradeService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	PlotService = services.PlotService
	CollectionBookService = services.CollectionBookService
	log.info("Init")
end

function UpgradeService.Start()
	Remotes.RequestBuyUpgrade.OnServerEvent:Connect(function(player, upgradeId)
		if not Validate.rateLimit(player, "RequestBuyUpgrade", 3) then
			return
		end
		if type(upgradeId) ~= "string" then
			return
		end
		-- decor is only sold at its room's counter in the market (and only while the market is open): the Decor tab is not in the normal window
		local def = Upgrades[upgradeId]
		if def and def.tab == DecorRooms.TAB then
			if not Hours.marketOpen() then
				Remotes.Notify:FireClient(player, "Info", "The Warehouse Market is closed. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
				return
			end
			if not isNearDecorStall(player, def.room) then
				Remotes.Notify:FireClient(player, "Info", "Buy decor at its room's counter in the Warehouse Market, upstairs.")
				return
			end
		end
		local _, reason = UpgradeService.BuyUpgrade(player, upgradeId)
		if reason == "outOfStock" then
			Remotes.Notify:FireClient(player, "Info", "That decor is out of stock right now. New stock arrives every few minutes.")
		end
	end)
	log.info("Start")
end

return UpgradeService
