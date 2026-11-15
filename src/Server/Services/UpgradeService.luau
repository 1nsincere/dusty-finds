-- UpgradeService.luau
-- Purpose: buys shop upgrades (tools, shelves, storage, sign, decor, expansions) through RequestBuyUpgrade.
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, PlotService, Shared.Config.Upgrades.
-- Validation order (docs/STATUS.md "Implementation requirements"): id -> next level exists -> player level ->
-- `requires` owned -> afford. Expansion MODELS (Back Room / Showroom from ServerStorage) are not cloned here yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local UpgradeService = {}
local DEBUG = true
local log = Log.new("UpgradeService", DEBUG)

local DataService, EconomyService, PlotService = nil, nil, nil

local function notify(player: any, kind: string, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, kind, text)
	end
end

-- Returns ok, reason ("unknown", "maxed", "level", "requires", "cash", "saveFailed"), newLevel.
function UpgradeService.BuyUpgrade(player: Player, upgradeId: string): (boolean, string?, number?)
	-- 1. exists in Config
	if not Validate.isConfigId(upgradeId, Upgrades) then
		return false, "unknown", nil
	end
	local def = Upgrades[upgradeId]
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
	if not EconomyService.Spend(player, cost) then
		return false, "cash", nil
	end
	if not DataService.Set(player, "upgrades." .. upgradeId, nextLevel) then
		EconomyService.AddCash(player, cost, "Refund")
		return false, "saveFailed", nil
	end

	PlotService.RefreshSlots(player) -- shelves / showroom change which slots are enabled
	notify(player, "Upgrade", `{def.name} level {nextLevel}`)
	log.info(`bought {upgradeId} level {nextLevel} for ${cost}`)
	return true, nil, nextLevel
end

function UpgradeService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	PlotService = services.PlotService
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
		UpgradeService.BuyUpgrade(player, upgradeId)
	end)
	log.info("Start")
end

return UpgradeService
