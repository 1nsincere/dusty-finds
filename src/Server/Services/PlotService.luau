-- PlotService.luau
-- Purpose: gives each player a free shop plot when their data loads, teleports them to it, shows their name on the
-- sign, enables the display/exhibit slots they own, and resets the plot when they leave (docs/01 multiplayer section, docs/03 §2).
-- Owner: Dev 1 (Ace). Depends on: DataService, Shared.Config (Economy, Upgrades), Workspace.Plots (Sean's greybox).
-- Server only. No remotes. Decor is shown from upgrade levels; expansion rooms (Back Room, Showroom) are cloned from ServerStorage.Expansions when owned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

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
	-- the big fascia signs on the building front (Facade) show the same name; optional, art only
	local facade = plot:FindFirstChild("Facade")
	if facade then
		for _, descendant in facade:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant.Name == "OwnerName" then
				descendant.Text = text
			end
		end
	end
end

-- Slots are Parts with attributes SlotIndex and Enabled; slot N is on when N <= count.
-- A slot with the attribute HideWhenLocked (Sean, 2026-11-24: the Showroom pedestals upstairs) is invisible and not
-- solid while locked, so it doesn't float in the air in shops without the second floor.
local function setSlots(folder: Instance?, count: number)
	if folder == nil then
		return
	end
	for _, slot in folder:GetChildren() do
		local index = slot:GetAttribute("SlotIndex")
		if type(index) == "number" then
			local enabled = index <= count
			slot:SetAttribute("Enabled", enabled)
			if slot:IsA("BasePart") and slot:GetAttribute("HideWhenLocked") == true then
				slot.Transparency = if enabled then 0 else 1
				slot.CanCollide = enabled
			end
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

-- Shows or hides one decor model. Hidden = Transparency 1 and no collision (what Sean's greybox starts as).
-- A part can opt in to its own look when shown with attributes: VisibleTransparency (default 0) and
-- VisibleCanCollide (default false, so decor never traps a player).
local function setDecorVisible(slot: Instance, visible: boolean)
	for _, part in slot:GetDescendants() do
		if part:IsA("BasePart") then
			if visible then
				part.Transparency = part:GetAttribute("VisibleTransparency") or 0
				part.CanCollide = part:GetAttribute("VisibleCanCollide") == true
			else
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
	slot:SetAttribute("Visible", visible)
end

-- Decor comes from Config: an upgrade's `decorSlots` lists the DecorSlots models, slot i shows at level >= i.
local function applyDecor(plot: Model, upgrades: { [string]: number }?)
	local folder = plot:FindFirstChild("DecorSlots")
	if folder == nil then
		return
	end
	local owned = upgrades or {}
	local closed = Economy.ClosedUpgradeTabs or {} -- a switched-off tab (decor until the decor shop) shows nothing
	for _, def in Upgrades do
		if def.decorSlots then
			local level = if closed[def.tab] then 0 else (owned[def.id] or 0)
			for index, slotName in def.decorSlots do
				local slot = folder:FindFirstChild(slotName)
				if slot then
					setDecorVisible(slot, level >= index)
				end
			end
		end
	end
end

-- ===== Expansion rooms (Back Room, Showroom) =====
-- Rooms are built in Studio under ServerStorage.Expansions/<name> in PLOT-LOCAL coordinates (plot Floor centre = origin) and cloned
-- into the plot when the upgrade (Config effect.expansion) is owned. A room may carry Benches/<Bench2> and DecorSlots/<model>
-- children: those are moved into the plot's own Benches / DecorSlots folders so the rest of the game finds them by name.
-- Everything created is marked with the attribute ExpansionOf = <name> so it can be removed again (release, refund, resetProfile).
local function removeExpansion(plot: Model, name: string)
	local doomed = {}
	for _, descendant in plot:GetDescendants() do
		if descendant:GetAttribute("ExpansionOf") == name then
			table.insert(doomed, descendant)
		end
	end
	for _, instance in doomed do
		instance:Destroy()
	end
end

local function buildExpansion(plot: Model, template: Instance, name: string)
	local floor = plot:FindFirstChild("Floor")
	if floor == nil or not floor:IsA("BasePart") or not template:IsA("Model") then
		log.warn(plot.Name, "can't build expansion", name)
		return
	end
	local clone = template:Clone()
	clone.Name = "Expansion_" .. name
	clone:SetAttribute("ExpansionOf", name)
	clone:PivotTo(floor.CFrame)
	-- a shop can be scaled (a 56 stud shop is 1.4x the 40 stud original): the template room is authored at 1x, so scale it with the plot
	local scale = floor.Size.X / 40
	if math.abs(scale - 1) > 0.001 then
		clone:ScaleTo(scale)
	end
	for _, folderName in { "Benches", "DecorSlots" } do
		local source = clone:FindFirstChild(folderName)
		local target = plot:FindFirstChild(folderName)
		if source and target then
			for _, child in source:GetChildren() do
				child:SetAttribute("ExpansionOf", name)
				child.Parent = target
			end
			source:Destroy()
		end
	end
	clone.Parent = plot
end

-- Art that has to make room for an expansion (Sean, 2026-11-24: the jar shelf and clock on the right wall, where the
-- Showroom stairs go): any model or part with the attribute HideWithExpansion = <expansion name> is invisible while that
-- room is owned. Only Transparency changes (the original is kept in the attribute ShownTransparency).
local function applyHiddenArt(plot: Model, ownedRooms: { [string]: boolean })
	for _, tagged in plot:GetDescendants() do
		local room = tagged:GetAttribute("HideWithExpansion")
		if type(room) == "string" then
			local hide = ownedRooms[room] == true
			local parts = if tagged:IsA("BasePart") then { tagged } else tagged:GetDescendants()
			for _, part in parts do
				if part:IsA("BasePart") then
					if part:GetAttribute("ShownTransparency") == nil then
						part:SetAttribute("ShownTransparency", part.Transparency)
					end
					part.Transparency = if hide then 1 else part:GetAttribute("ShownTransparency")
				end
			end
		end
	end
end

-- Adds or removes each room from the upgrades, and opens the back wall while a room behind the shop exists.
-- Only templates with the attribute OpensBackWall = true count (the Back Room; the Showroom is the second floor inside
-- the building since 2026-11-24 and must not open the wall onto nothing).
-- The plot's BackWall is only restyled (Transparency / CanCollide), never resized or moved.
local function applyExpansions(plot: Model, upgrades: { [string]: number }?)
	local storage = ServerStorage:FindFirstChild("Expansions")
	local owned = upgrades or {}
	local ownedCount = 0 -- owned rooms that open the back wall
	local ownedRooms: { [string]: boolean } = {}
	for _, def in Upgrades do
		local name = def.effect and def.effect.expansion
		if name then
			local has = (owned[def.id] or 0) > 0
			ownedRooms[name] = has
			local built = plot:FindFirstChild("Expansion_" .. name) ~= nil
			local template = storage and storage:FindFirstChild(name)
			if has and template and template:GetAttribute("OpensBackWall") == true then
				ownedCount += 1
			end
			if has and not built then
				if template then
					buildExpansion(plot, template, name)
				else
					log.warn("no ServerStorage.Expansions." .. name .. " model: the room is bought but invisible")
				end
			elseif not has and built then
				removeExpansion(plot, name)
			end
		end
	end
	applyHiddenArt(plot, ownedRooms)
	local walls = plot:FindFirstChild("Walls")
	local backWall = walls and walls:FindFirstChild("BackWall")
	if backWall and backWall:IsA("BasePart") then
		local open = ownedCount > 0
		backWall.Transparency = if open then 1 else 0
		backWall.CanCollide = not open
	end
	if ownedCount >= 2 then
		-- both rooms exist: the plaster fills that closed the other half of the opening are no longer needed
		local fills = {}
		for _, descendant in plot:GetDescendants() do
			if descendant.Name == "WallFill" then
				table.insert(fills, descendant)
			end
		end
		for _, fill in fills do
			fill:Destroy()
		end
	end
end

-- Rebuilds everything a plot shows from the owner's upgrades (nil = the empty "For Sale" look).
local function applySlots(plot: Model, upgrades: { [string]: number }?)
	local displayCount, exhibitCount = slotCounts(upgrades)
	setSlots(plot:FindFirstChild("DisplaySlots"), displayCount)
	setSlots(plot:FindFirstChild("ExhibitSlots"), exhibitCount)
	applyExpansions(plot, upgrades) -- rooms first: they bring their own Bench2 and decor models
	applyDecor(plot, upgrades)
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
	-- Shelves show their item through attributes (DisplayService.SyncSlots): clear them for the next owner.
	for _, folderName in { "DisplaySlots", "ExhibitSlots" } do
		local folder = plot:FindFirstChild(folderName)
		if folder then
			for _, slot in folder:GetChildren() do
				slot:SetAttribute("ItemId", nil)
				slot:SetAttribute("Golden", nil)
				slot:SetAttribute("Stars", nil)
			end
		end
	end
	setSign(plot, SIGN_FOR_SALE)
	applySlots(plot, nil)
	log.info(player.Name, "left", plot.Name)
end

-- ===== Public API for other services =====

function PlotService.GetPlot(player: Player): Model?
	return plotOf[player]
end

-- Call after a purchase changes what the plot shows: slot counts and decor (UpgradeService does this after a buy).
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
