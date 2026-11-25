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
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local TweenService = game:GetService("TweenService")

local SettingsController = {}
local DEBUG = true

-- Keys must match what SettingsService accepts (and the data template). Order = order on screen.
local TOGGLES = {
	{ key = "music", icon = "🎵", title = "Music", desc = "Background tunes in the shop and town", color = Color3.fromRGB(145, 104, 255), section = "SOUND" },
	{ key = "sfx", icon = "🔊", title = "Sound effects", desc = "Clicks, coins and restoring sounds", color = Color3.fromRGB(63, 167, 255), section = "SOUND" },
	{ key = "reduceEffects", icon = "✨", title = "Reduce effects", desc = "Calmer visuals, fewer sparkles", color = Color3.fromRGB(255, 138, 61), section = "COMFORT" },
	{ key = "announcements", icon = "🔔", title = "Announcements", desc = "Pop-ups for new stock and events", color = Color3.fromRGB(255, 107, 142), section = "COMFORT" },
}
local ROW_HEIGHT, SECTION_HEIGHT, ROW_GAP = 58, 24, 6
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
	-- a sliding pill: a teal track with the knob on the right when ON, a grey one with the knob on the left when OFF
	switch.Text = ""
	switch.BackgroundColor3 = if on then UiTheme.Teal else UiTheme.Disabled
	local knob = switch:FindFirstChild("Knob") :: Frame?
	if knob then
		TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = if on then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end
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

-- A section title ("SOUND", "COMFORT", ...) in gold above its rows.
local function buildSection(parent: Instance, order: number, title: string)
	local label = Instance.new("TextLabel")
	label.Name = "Section_" .. title
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, SECTION_HEIGHT)
	label.FontFace = Skin.FONT_TITLE
	label.TextSize = 15
	label.TextColor3 = Skin.COLORS.accent
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = title
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = label
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.new(0, 0, 1, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Skin.COLORS.accentDim
	line.BackgroundTransparency = 0.55
	line.BorderSizePixel = 0
	line.Parent = label
	label.Parent = parent
end

-- One setting: a coloured icon badge, the name, a one-line explanation and a sliding switch.
local function buildToggleRow(template: Instance, parent: Instance, order: number, toggle)
	local row = template:Clone() :: Frame
	row.Name = toggle.key
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.Visible = true
	local label = row:FindFirstChild("Label") :: TextLabel
	label.Text = toggle.title
	label.TextScaled = false
	label.TextSize = 18
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(58, 8)
	label.Size = UDim2.new(1, -150, 0, 22)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(58, 31)
	desc.Size = UDim2.new(1, -150, 0, 18)
	desc.FontFace = Skin.FONT_BODY
	desc.TextSize = 13
	desc.TextColor3 = Skin.COLORS.textDim
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.Text = toggle.desc
	desc.Parent = row
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(12, (ROW_HEIGHT - 36) / 2)
	badge.Size = UDim2.fromOffset(36, 36)
	badge.BackgroundColor3 = toggle.color
	badge.TextSize = 19
	badge.Text = toggle.icon
	badge.Parent = row
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Skin.COLORS.ink
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badge
	local switch = row:FindFirstChild("Switch") :: TextButton
	switch.Size = UDim2.fromOffset(62, 32)
	switch.Position = UDim2.new(1, -12, 0.5, 0)
	switch.Text = ""
	local switchCorner = switch:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	switchCorner.CornerRadius = UDim.new(1, 0)
	switchCorner.Parent = switch
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 3, 0.5, 0)
	knob.Size = UDim2.fromOffset(26, 26)
	knob.BackgroundColor3 = Skin.COLORS.cream
	knob.BorderSizePixel = 0
	knob.ZIndex = switch.ZIndex + 2
	knob.Parent = switch
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	row.Parent = parent
	return row
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
			-- SOUND / COMFORT sections of switches, then the auto sell chips (a titled section of its own)
			local order, lastSection = 0, nil
			local contentHeight = 0
			for _, toggle in TOGGLES do
				if toggle.section ~= lastSection then
					lastSection = toggle.section
					order += 1
					buildSection(window.Toggles, order, toggle.section)
					contentHeight += SECTION_HEIGHT + ROW_GAP
				end
				order += 1
				local row = buildToggleRow(template, window.Toggles, order, toggle)
				contentHeight += ROW_HEIGHT + ROW_GAP
				switches[toggle.key] = row.Switch
				row.Switch.Activated:Connect(function()
					onSwitchTapped(toggle.key)
				end)
			end
			order += 1
			buildSection(window.Toggles, order, "AUTO-SELL NEW FINDS")
			order += 1
			buildAutoSellRow(template, window.Toggles, order)
			contentHeight += SECTION_HEIGHT + ROW_GAP + AUTO_SELL_ROW_HEIGHT
			local listLayout = window.Toggles:FindFirstChildOfClass("UIListLayout")
			if listLayout then
				listLayout.Padding = UDim.new(0, ROW_GAP)
			end
			-- the window is exactly as tall as its content (title bar 58 + content + a little air), then shrinks on short screens
			window.Size = UDim2.fromOffset(420, 58 + contentHeight + 22)
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
