-- VisitController.luau (StarterPlayerScripts.Client.Controllers.VisitController)
-- Purpose: the 👥 Visit window: one row per player on the server (you first, "Go home"); tapping Visit asks the
-- server (RequestVisit) to put you at that shop's door. Live while open: rows update as players join/leave.
-- Owner: Dev 3 (Sean). Depends on: Shared.Remotes (RequestVisit), UiTheme, Workspace.Plots (OwnerUserId attribute),
-- StarterGui.Visit (Window.{Title,CloseButton,List,Empty}, RowTemplate → Name, Info, VisitButton), HUD.TopRight.Visit,
-- and the other window controllers (Inventory/Shop/Settings/Collection close when Visit opens).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local VisitController = {}
local DEBUG = true

local LOCAL_PLAYER = Players.LocalPlayer
local TAP_COOLDOWN = 1.2 -- the server allows 1 visit per second; a bit more so a double tap never gets dropped

local others = nil
local visitGui: ScreenGui? = nil
local lastTap = 0

local function log(...)
	if DEBUG then
		print("[VisitController]", ...)
	end
end

local function plotNameOf(userId: number): string?
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == userId then
			return plot.Name
		end
	end
	return nil
end

local function requestVisit(userId: number)
	local now = os.clock()
	if now - lastTap < TAP_COOLDOWN then
		return
	end
	lastTap = now
	Remotes.RequestVisit:FireServer(userId)
	log("asked to visit", userId)
	VisitController.Close() -- you want to see where you landed; the server's toast confirms it
end

-- Rebuilds every row. Cheap: at most ~6 players per server (one per plot).
local function drawList()
	local gui = visitGui
	if gui == nil then
		return
	end
	local window = gui.Window
	local list = window.List
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		if a == LOCAL_PLAYER or b == LOCAL_PLAYER then
			return a == LOCAL_PLAYER -- you first
		end
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)

	local otherCount = 0
	for index, player in players do
		local isMe = player == LOCAL_PLAYER
		local plotName = plotNameOf(player.UserId)
		local row = gui.RowTemplate:Clone()
		row.Name = "Row_" .. player.UserId
		row.LayoutOrder = index
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		nameLabel.Text = if isMe then "🏠 Your shop" else player.DisplayName
		row.Info.Text = if plotName then (plotName:gsub("^Plot(%d+)$", "Plot %1")) else "Setting up shop…"
		local button = row.VisitButton
		button.Text = if isMe then "Go home" else "Visit"
		button.BackgroundColor3 = if isMe then UiTheme.Coral else UiTheme.Teal
		button.Active = plotName ~= nil
		button.AutoButtonColor = plotName ~= nil
		if plotName == nil then
			button.BackgroundColor3 = UiTheme.Disabled
		end
		button.Activated:Connect(function()
			if plotName ~= nil then
				requestVisit(player.UserId)
			end
		end)
		row.Visible = true
		row.Parent = list
		if not isMe then
			otherCount += 1
		end
	end
	window.Empty.Visible = otherCount == 0
end

function VisitController.IsOpen(): boolean
	return visitGui ~= nil and visitGui.Window.Visible
end

function VisitController.Close()
	if visitGui and visitGui.Window.Visible then
		visitGui.Window.Visible = false
		log("closed")
	end
end

function VisitController.Open()
	if visitGui == nil then
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return -- finish the reveal first
	end
	for _, name in { "InventoryController", "SettingsController", "CollectionController" } do
		local controller = others and others[name]
		if controller and controller.Close then
			controller.Close()
		end
	end
	local shop = others and others.ShopController
	if shop and shop.CloseAll then
		shop.CloseAll()
	end
	drawList()
	visitGui.Window.Visible = true
	log("opened")
end

-- One window at a time: if any other window opens, Visit steps aside (no changes needed in those controllers).
local function closeWhenOtherOpens(playerGui: Instance)
	local paths = {
		{ "Inventory", "Window" },
		{ "Supply", "Window" },
		{ "Upgrades", "Window" },
		{ "Settings", "Window" },
		{ "Collection", "Book" },
		{ "Discovery", "Card" },
	}
	for _, path in paths do
		local screen = playerGui:FindFirstChild(path[1])
		local window = screen and screen:FindFirstChild(path[2])
		if window and window:IsA("GuiObject") then
			window:GetPropertyChangedSignal("Visible"):Connect(function()
				if window.Visible then
					VisitController.Close()
				end
			end)
		end
	end
end

function VisitController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function VisitController.Start()
	log("Start")
	task.spawn(function()
		local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
		visitGui = playerGui:WaitForChild("Visit", 10) :: ScreenGui?
		if visitGui == nil then
			warn("[VisitController] PlayerGui.Visit not found: is StarterGui.Visit missing?")
			return
		end
		visitGui.Window.CloseButton.Activated:Connect(VisitController.Close)

		-- Live list while open: players joining/leaving and plots being assigned.
		local function redrawIfOpen()
			if VisitController.IsOpen() then
				drawList()
			end
		end
		Players.PlayerAdded:Connect(redrawIfOpen)
		Players.PlayerRemoving:Connect(function()
			task.defer(redrawIfOpen) -- after the player is really gone from GetPlayers()
		end)
		local plots = workspace:WaitForChild("Plots", 10)
		if plots then
			for _, plot in plots:GetChildren() do
				plot:GetAttributeChangedSignal("OwnerUserId"):Connect(redrawIfOpen)
			end
		end

		local hud = playerGui:WaitForChild("HUD", 10)
		local hudButton = hud and hud:FindFirstChild("TopRight") and hud.TopRight:FindFirstChild("Visit")
		if hudButton then
			hudButton.Activated:Connect(function()
				if VisitController.IsOpen() then
					VisitController.Close()
				else
					VisitController.Open()
				end
			end)
		else
			warn("[VisitController] HUD.TopRight.Visit not found")
		end
		closeWhenOtherOpens(playerGui)
		log("ready")
	end)
end

return VisitController
