-- PlotService.luau
-- Purpose: gives each player a free shop plot when their data loads, teleports them to it, shows their name on the
-- sign, enables the display/exhibit slots they own, and resets the plot when they leave (docs/01 multiplayer section, docs/03 §2).
-- Owner: Dev 1 (Ace). Depends on: DataService, Shared.Config (Economy, Upgrades), Workspace.Plots (Sean's greybox).
-- Server only. No remotes. Decor and expansions are NOT rebuilt here yet (they come with UpgradeService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local PlotService = {}
local DEBUG = true
local log = Log.new("PlotService", DEBUG)

local SIGN_FOR_SALE = "For Sale" -- the default text Sean put on every sign
local SPAWN_LIFT = Vector3.new(0, 3, 0) -- stand above the Spawn part instead of inside it

local DataService = nil
local plots: { Model } = {} -- sorted Plot1, Plot2, ...
local plotOf: { [Player]: Model } = {}
local ownerOf: { [Model]: Player } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function setSign(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChild("OwnerName")
	if label and label:IsA("TextLabel") then
		label.Text = text
	else
		log.warn(plot.Name, "has no Sign.SurfaceGui.OwnerName TextLabel")
	end
end

-- Slots are Parts with attributes SlotIndex and Enabled; slot N is on when N <= count.
local function setSlots(folder: Instance?, count: number)
	if folder == nil then
		return
	end
	for _, slot in folder:GetChildren() do
		local index = slot:GetAttribute("SlotIndex")
		if type(index) == "number" then
			slot:SetAttribute("Enabled", index <= count)
		end
	end
end

-- How many display slots and exhibit pedestals this upgrade table gives (all numbers come from Config).
local function slotCounts(upgrades: { [string]: number }?)
	local owned = upgrades or {}
	local displayCount = Economy.StartingDisplaySlots
	local shelfLevel = owned.DisplayShelves or 0
	if shelfLevel > 0 then
		displayCount = Upgrades.DisplayShelves.effect.displaySlots[shelfLevel] or displayCount
	end

	local exhibitCount = Economy.StartingExhibitPedestals
	if (owned.Showroom or 0) > 0 then
		exhibitCount = exhibitCount + Upgrades.Showroom.effect.exhibitPedestals
	end
	return displayCount, exhibitCount
end

local function applySlots(plot: Model, upgrades: { [string]: number }?)
	local displayCount, exhibitCount = slotCounts(upgrades)
	setSlots(plot:FindFirstChild("DisplaySlots"), displayCount)
	setSlots(plot:FindFirstChild("ExhibitSlots"), exhibitCount)
end

local function teleportToPlot(player: Player, plot: Model)
	local character = player.Character
	local spawnPart = plot:FindFirstChild("Spawn")
	if character == nil or spawnPart == nil or not spawnPart:IsA("BasePart") then
		return
	end
	-- The character may still be loading; give the root part a moment instead of failing silently.
	if character:WaitForChild("HumanoidRootPart", 5) == nil then
		return
	end
	if plotOf[player] ~= plot then
		return -- player left or was reassigned while we waited
	end
	character:PivotTo(spawnPart.CFrame + SPAWN_LIFT)
end

local function freePlot(): Model?
	for _, plot in plots do
		if ownerOf[plot] == nil then
			return plot
		end
	end
	return nil
end

-- Gives the player the first free plot (does nothing if they already have one). Returns the plot or nil if full.
local function assignPlot(player: Player): Model?
	if plotOf[player] then
		return plotOf[player]
	end
	local plot = freePlot()
	if plot == nil then
		log.warn("no free plot for", player.Name, "- the server has more players than plots")
		return nil
	end

	plotOf[player] = plot
	ownerOf[plot] = player
	plot:SetAttribute("OwnerUserId", player.UserId)
	setSign(plot, player.DisplayName)
	applySlots(plot, DataService.GetValue(player, "upgrades"))

	task.spawn(teleportToPlot, player, plot) -- own thread: it may wait for the character, and DataService calls us inline
	characterConnections[player] = player.CharacterAdded:Connect(function()
		teleportToPlot(player, plot) -- every respawn starts at the shop
	end)

	log.info(player.Name, "->", plot.Name)
	return plot
end

-- Resets the plot for the next owner.
local function releasePlot(player: Player)
	local plot = plotOf[player]
	if plot == nil then
		return
	end
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
		characterConnections[player] = nil
	end
	plotOf[player] = nil
	ownerOf[plot] = nil
	plot:SetAttribute("OwnerUserId", nil)
	setSign(plot, SIGN_FOR_SALE)
	applySlots(plot, nil)
	log.info(player.Name, "left", plot.Name)
end

-- ===== Public API for other services =====

function PlotService.GetPlot(player: Player): Model?
	return plotOf[player]
end

-- Call after a purchase changes slot counts (e.g. UpgradeService buys Display Shelves).
function PlotService.RefreshSlots(player: Player)
	local plot = plotOf[player]
	if plot then
		applySlots(plot, DataService.GetValue(player, "upgrades"))
	end
end

function PlotService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function PlotService.Start()
	local folder = workspace:FindFirstChild("Plots")
	if folder == nil then
		log.warn("Workspace.Plots is missing: nobody will get a plot")
	else
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				table.insert(plots, child)
			end
		end
		-- Plot1, Plot2, ... Plot10 would sort wrong as text, so compare the number part.
		table.sort(plots, function(a, b)
			return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
		end)
		for _, plot in plots do
			setSign(plot, SIGN_FOR_SALE)
			applySlots(plot, nil)
		end
	end

	DataService.OnPlayerLoaded(assignPlot)
	DataService.OnPlayerReleasing(releasePlot)
	-- Safety net: a player can leave between data loading and release callbacks.
	Players.PlayerRemoving:Connect(releasePlot)

	log.info(`Start, {#plots} plots found`)
end

return PlotService
