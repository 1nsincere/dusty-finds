-- SettingsController.luau
-- Purpose: the ⚙️ Settings window: one ON/OFF switch per setting, saved on the server with RequestSaveSettings.
-- The switch shows the server's value (ClientState "settings"), so a refused save snaps back by itself.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Remotes (RequestSaveSettings),
-- StarterGui.Settings (Window.{Title,CloseButton,Toggles}, ToggleTemplate → Label, Switch), HUD.TopRight.Settings,
-- InventoryController / ShopController / DiscoveryController (one window open at a time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local SettingsController = {}
local DEBUG = true

-- Keys must match what SettingsService accepts (and the data template). Order = order on screen.
local TOGGLES = {
	{ key = "announcements", label = "🔔 Show announcements" },
	{ key = "music", label = "🎵 Music" },
	{ key = "sfx", label = "🔊 Sound effects" },
	{ key = "reduceEffects", label = "✨ Reduce effects" },
}
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

-- Missing keys count as ON (the template's defaults are all true except reduceEffects).
local function currentValue(key: string): boolean
	if pending[key] ~= nil then
		return pending[key]
	end
	local value = ClientState.Get("settings." .. key)
	if value == nil then
		return key ~= "reduceEffects"
	end
	return value == true
end

local function drawSwitch(key: string)
	local switch = switches[key]
	if switch == nil then
		return
	end
	local on = currentValue(key)
	switch.Text = if on then "ON" else "OFF"
	switch.BackgroundColor3 = if on then UiTheme.Teal else UiTheme.Disabled
end

local function drawAll()
	for _, toggle in TOGGLES do
		drawSwitch(toggle.key)
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
		drawAll()
		window.CloseButton.Activated:Connect(SettingsController.Close)

		-- The server confirms with StateChanged("settings.<key>") (or the whole "settings" table).
		ClientState.OnChanged("settings", function()
			for _, toggle in TOGGLES do
				local saved = ClientState.Get("settings." .. toggle.key)
				if pending[toggle.key] ~= nil and saved == pending[toggle.key] then
					pending[toggle.key] = nil
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
		log(`ready: {#TOGGLES} switches`)
	end)
end

return SettingsController
