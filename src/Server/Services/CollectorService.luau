-- CollectorService.luau (ServerScriptService.Server.Services.CollectorService)
-- Purpose: keeps each player's COLLECTOR SCORE and TIER up to date (docs/12 Stage 4) and publishes them as Player attributes
-- (DF_CollectorScore, DF_CollectorTier) so every client can draw the right aura (AuraController). Derived data only: nothing
-- is saved, nothing can be bought, no remote. Tells the player when they reach a new tier.
-- Owner: Dev 1 (Ace). Depends on: DataService, CollectionBookService (rating stars), Shared.Collector, Config.Collector.
-- Re-checks every few seconds instead of hooking every place the score can change (a restore, a find, an upgrade): cheap and
-- impossible to forget a place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Collector = require(ReplicatedStorage.Shared.Collector)

local CollectorService = {}
local DEBUG = true
local log = Log.new("CollectorService", DEBUG)

local CHECK_SECONDS = 5

local DataService, CollectionBookService = nil, nil
local lastTier: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Works out one player's score and tier and publishes them. `silent` = no "new tier" message (first check after loading).
-- Returns score, tier number (nil if the data isn't loaded).
function CollectorService.Refresh(player: any, silent: boolean?): (number?, number?)
	local collection = DataService.GetValue(player, "collection")
	if type(collection) ~= "table" then
		return nil, nil
	end
	local stars = CollectionBookService.GetRatingStars(player)
	local score = Collector.score(collection, stars)
	local tier, tierNumber = Collector.tier(score)
	if Validate.isPlayer(player) then
		if player:GetAttribute("DF_CollectorScore") ~= score then
			player:SetAttribute("DF_CollectorScore", score)
		end
		if player:GetAttribute("DF_CollectorTier") ~= tierNumber then
			player:SetAttribute("DF_CollectorTier", tierNumber)
		end
		local before = lastTier[player]
		lastTier[player] = tierNumber
		if not silent and before and tierNumber > before then
			Remotes.Notify:FireClient(player, "Info", `You are now a {tier.name}! Your aura grows.`)
			log.info(`{player.Name} reached {tier.id} (score {score})`)
		end
	end
	return score, tierNumber
end

function CollectorService.Init(services)
	DataService = services.DataService
	CollectionBookService = services.CollectionBookService
	log.info("Init")
end

function CollectorService.Start()
	if DataService.OnPlayerLoaded then
		DataService.OnPlayerLoaded(function(player)
			CollectorService.Refresh(player, true)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				pcall(CollectorService.Refresh, player, false)
			end
		end
	end)
end

return CollectorService
