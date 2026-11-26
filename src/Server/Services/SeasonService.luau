-- SeasonService.luau (ServerScriptService.Server.Services.SeasonService)
-- Purpose: shows and hides seasonal shop decor (docs/12, Christmas "Pasko"). Each shop can carry a folder Facade.Decor_<Season>
-- (for example Decor_Pasko) of Models; a Model with the attribute RequiresPass = <pass id> only shows while the SHOP'S OWNER owns
-- that pass, a Model without it is free for everyone. Nothing shows outside the season (Config.Seasons). Looks only.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Seasons, MonetizationService (Has), Workspace.Plots (OwnerUserId attribute).
-- It only changes Transparency / Light.Enabled (the shown values are kept in attributes) and never touches collision: decor does not collide.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)

local SeasonService = {}
local DEBUG = true
local log = Log.new("SeasonService", DEBUG)

local REFRESH_EVERY = 5 -- seconds: cheap (six shops), and picks up a pass bought a moment ago

local MonetizationService = nil

-- Replaceable so tests can use fake owners / passes / a fixed season.
local ownerHasPass = function(plot: Instance, passId: string): boolean
	local userId = plot:GetAttribute("OwnerUserId")
	local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return owner ~= nil and MonetizationService ~= nil and MonetizationService.Has(owner, passId)
end
local activeSeasons = function(): { [string]: boolean }
	local override = if RunService:IsStudio() then workspace:GetAttribute("SeasonOverride") else nil
	return Seasons.activeNow(if type(override) == "string" then override else nil)
end

function SeasonService.SetLookups(hasPass: ((Instance, string) -> boolean)?, active: (() -> { [string]: boolean })?)
	ownerHasPass = hasPass or ownerHasPass
	activeSeasons = active or activeSeasons
end

local function setShown(part: BasePart, shown: boolean)
	if part:GetAttribute("SeasonShownTransparency") == nil then
		part:SetAttribute("SeasonShownTransparency", part.Transparency)
	end
	part.Transparency = if shown then part:GetAttribute("SeasonShownTransparency") else 1
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = shown
		end
	end
end

-- Draws one shop's seasonal decor for the current date and its owner's passes.
function SeasonService.Refresh(plot: Instance, active: { [string]: boolean }?)
	local facade = plot:FindFirstChild("Facade")
	if facade == nil then
		return
	end
	local on = active or activeSeasons()
	for seasonId, season in Seasons.LIST do
		local folder = facade:FindFirstChild("Decor_" .. seasonId)
		if folder then
			for _, model in folder:GetChildren() do
				local required = model:GetAttribute("RequiresPass")
				local shown = on[seasonId] == true and (required == nil or (type(required) == "string" and ownerHasPass(plot, required)))
				local parts = if model:IsA("BasePart") then { model } else model:GetDescendants()
				for _, part in parts do
					if part:IsA("BasePart") then
						setShown(part, shown)
					end
				end
			end
		end
	end
end

function SeasonService.RefreshAll()
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	local active = activeSeasons()
	for _, plot in plots:GetChildren() do
		SeasonService.Refresh(plot, active)
	end
end

function SeasonService.Init(services)
	MonetizationService = services.MonetizationService
	log.info("Init")
end

function SeasonService.Start()
	task.spawn(function()
		while true do
			SeasonService.RefreshAll()
			task.wait(REFRESH_EVERY)
		end
	end)
	log.info("Start")
end

return SeasonService
