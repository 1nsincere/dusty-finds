-- SettingsController.luau
-- Purpose: the ⚙️ Settings window: one ON/OFF switch per setting, saved on the server with RequestSaveSettings.
-- The switch shows the server's value (ClientState "settings"), so a refused save snaps back by itself.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Remotes (RequestSaveSettings),
-- StarterGui.Settings (Window.{Title,CloseButton,Toggles}, ToggleTemplate → Label, Switch), HUD.TopRight.Settings,
-- InventoryController / ShopController / DiscoveryController (one window open at a time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

local SettingsController = {}
local DEBUG = true

-- Keys must match what SettingsService accepts (and the data template). Order = order on screen.
local TOGGLES = {
	{ key = "announcements", label = "🔔 Show announcements" },
	{ key = "music", label = "🎵 Music" },
	{ key = "sfx", label = "🔊 Sound effects" },
	{ key = "reduceEffects", label = "✨ Reduce effects" },
}
-- Auto sell (Sean, Ace OK 2026-11-25): one chip per rarity in Economy.AutoSellRarities, key "autoSell<Rarity>", all OFF
-- until the player taps one. The server does the selling (ShipmentService) and reads the saved value, not this screen.
local AUTO_SELL_ROW_HEIGHT = 84
local AUTO_SELL = {}
for _, rarity in Economy.AutoSellRarities do
	table.insert(AUTO_SELL, { key = "autoSell" .. rarity, rarity = rarity })
end
local ALL_KEYS = {}
for _, toggle in TOGGLES do
	table.insert(ALL_KEYS, toggle.key)
end
for _, chip in AUTO_SELL do
	table.insert(ALL_KEYS, chip.key)
end
local DEFAULT_OFF = { reduceEffects = true }
for _, chip in AUTO_SELL do
	DEFAULT_OFF[chip.key] = true
end
-- The server allows 2 saves per second; a short wait per switch keeps fast tapping under that.
local SWITCH_COOLDOWN = 0.6
-- If the server doesn't confirm (refused or rate limited), show its real value again after this.
local CONFIRM_TIMEOUT = 2

local player = Players.LocalPlayer
local others = nil
local settingsGui: ScreenGui? = nil
local switches: { [string]: TextButton } = {}
local pending: { [string]: boolean } = {} -- value I asked for, until the server confirms
local cooldownUntil: { [string]: number } = {}

local function log(...)
	if DEBUG then
		print("[SettingsController]", ...)
	end
end

-- Missing keys count as ON, except the ones the template starts OFF (reduceEffects and every auto sell chip).
local function currentValue(key: string): boolean
	if pending[key] ~= nil then
		return pending[key]
	end
	local value = ClientState.Get("settings." .. key)
	if value == nil then
		return not DEFAULT_OFF[key]
	end
	return value == true
end

local function drawSwitch(key: string)
	local switch = switches[key]
	if switch == nil then
		return
	end
	local on = currentValue(key)
	local rarity = switch:GetAttribute("Rarity")
	if type(rarity) == "string" then
		-- an auto sell chip: the rarity's colour when ON, grey when OFF
		switch.Text = if on then `{rarity} ✓` else rarity
		switch.BackgroundColor3 = if on then UiTheme.rarityColor(rarity) else UiTheme.Disabled
		return
	end
	switch.Text = if on then "ON" else "OFF"
	switch.BackgroundColor3 = if on then UiTheme.Teal else UiTheme.Disabled
end

local function drawAll()
	for _, key in ALL_KEYS do
		drawSwitch(key)
	end
end

local function onSwitchTapped(key: string)
	if os.clock() < (cooldownUntil[key] or 0) then
		return
	end
	cooldownUntil[key] = os.clock() + SWITCH_COOLDOWN
	local newValue = not currentValue(key)
	pending[key] = newValue
	drawSwitch(key) -- feels instant; the server's answer decides what stays
	Remotes.RequestSaveSettings:FireServer({ [key] = newValue })
	log("asked to save", key, newValue)
	task.delay(CONFIRM_TIMEOUT, function()
		if pending[key] == newValue then
			pending[key] = nil
			drawSwitch(key)
			log("no confirmation for", key, "- showing the saved value")
		end
	end)
end

-- The "💰 Auto sell new finds" row: a label on top and one chip per rarity under it (chips are copies of the skinned switch).
local function buildAutoSellRow(template: Instance, parent: Instance, order: number)
	local row = template:Clone() :: Frame
	row.Name = "AutoSell"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, AUTO_SELL_ROW_HEIGHT)
	row.Visible = true
	local label = row:FindFirstChild("Label") :: TextLabel
	label.Text = "💰 Auto sell finds (~40%)"
	label.TextScaled = false -- a long label shrank to fit; the same 20 px as the other rows
	label.TextSize = 20
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(12, 6)
	label.Size = UDim2.new(1, -24, 0, 30)
	local switchTemplate = row:FindFirstChild("Switch") :: TextButton
	switchTemplate.Visible = false

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.new(0, 10, 0, 40)
	chips.Size = UDim2.new(1, -20, 0, 36)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = chips
	for index, chip in AUTO_SELL do
		local button = switchTemplate:Clone()
		button.Name = chip.key
		button.LayoutOrder = index
		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.new()
		button.Size = UDim2.new(1 / #AUTO_SELL, -6, 1, 0)
		button.TextScaled = true
		button.Visible = true
		button:SetAttribute("Rarity", chip.rarity)
		button.Parent = chips
		switches[chip.key] = button
		button.Activated:Connect(function()
			onSwitchTapped(chip.key)
		end)
	end
	chips.Parent = row
	row.Parent = parent
end

-- Phones: the window got taller with the auto sell row, so shrink it to fit a short screen (never grow it).
local function fitWindow(window: GuiObject)
	local scale = window:FindFirstChild("FitScale") :: UIScale?
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Name = "FitScale"
		scale.Parent = window
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local usable = camera.ViewportSize.Y - GuiService:GetGuiInset().Y - 16
	scale.Scale = math.clamp(usable / math.max(window.Size.Y.Offset, 1), 0.5, 1)
end

function SettingsController.IsOpen(): boolean
	return settingsGui ~= nil and settingsGui.Window.Visible
end

function SettingsController.Close()
	if settingsGui then
		settingsGui.Window.Visible = false
	end
end

function SettingsController.Open()
	if settingsGui == nil then
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return -- finish the reveal first
	end
	local inventory = others and others.InventoryController
	if inventory and inventory.Close then
		inventory.Close()
	end
	local shop = others and others.ShopController
	if shop and shop.CloseAll then
		shop.CloseAll()
	end
	drawAll()
	settingsGui.Window.Visible = true
	log("opened")
end

-- One window at a time: if any other window opens, Settings steps aside (no changes needed in those controllers).
local function closeWhenOtherOpens(playerGui: Instance)
	for _, path in { { "Inventory", "Window" }, { "Supply", "Window" }, { "Upgrades", "Window" }, { "Discovery", "Card" } } do
		local screen = playerGui:FindFirstChild(path[1])
		local window = screen and screen:FindFirstChild(path[2])
		if window and window:IsA("GuiObject") then
			window:GetPropertyChangedSignal("Visible"):Connect(function()
				if window.Visible then
					SettingsController.Close()
				end
			end)
		end
	end
end

function SettingsController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function SettingsController.Start()
	log("Start")
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		settingsGui = playerGui:WaitForChild("Settings", 10) :: ScreenGui?
		if settingsGui == nil then
			warn("[SettingsController] PlayerGui.Settings not found: is StarterGui.Settings missing?")
			return
		end
		local window = settingsGui.Window
		local template = settingsGui:FindFirstChild("ToggleTemplate")
		for index, toggle in TOGGLES do
			local row = template:Clone()
			row.Name = toggle.key
			row.LayoutOrder = index
			row.Label.Text = toggle.label
			row.Visible = true
			row.Parent = window.Toggles
			switches[toggle.key] = row.Switch
			row.Switch.Activated:Connect(function()
				onSwitchTapped(toggle.key)
			end)
		end
		buildAutoSellRow(template, window.Toggles, #TOGGLES + 1)
		-- room for the taller row (+ the list's padding), then shrink to fit short screens
		local listLayout = window.Toggles:FindFirstChildOfClass("UIListLayout")
		local gap = if listLayout then listLayout.Padding.Offset else 6
		window.Size = window.Size + UDim2.fromOffset(0, AUTO_SELL_ROW_HEIGHT + gap)
		fitWindow(window)
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				fitWindow(window)
			end)
		end
		drawAll()
		window.CloseButton.Activated:Connect(SettingsController.Close)

		-- The server confirms with StateChanged("settings.<key>") (or the whole "settings" table).
		ClientState.OnChanged("settings", function()
			for _, key in ALL_KEYS do
				local saved = ClientState.Get("settings." .. key)
				if pending[key] ~= nil and saved == pending[key] then
					pending[key] = nil
				end
			end
			drawAll()
		end)

		local hud = playerGui:WaitForChild("HUD", 10)
		local hudButton = hud and hud:FindFirstChild("TopRight") and hud.TopRight:FindFirstChild("Settings")
		if hudButton then
			hudButton.Activated:Connect(function()
				if SettingsController.IsOpen() then
					SettingsController.Close()
				else
					SettingsController.Open()
				end
			end)
		end
		closeWhenOtherOpens(playerGui)
		log(`ready: {#TOGGLES} switches + {#AUTO_SELL} auto sell chips`)
	end)
end

return SettingsController
