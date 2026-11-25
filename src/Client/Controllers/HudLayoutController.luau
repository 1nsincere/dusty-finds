-- HudLayoutController.luau
-- Purpose: puts the HUD into the Figma "Main HUD — Final Proposal" layout and look, at runtime:
--   * status plate (cash, level, stars, XP) replaces MoneyPill / RatingPill / XPBar (those stay, hidden, so nothing breaks)
--   * left rail: Inventory + Menu; right rail: Travel + Visit; top-right: Passes + Settings; Sprint on phones
--   * Menu flyout with exactly four actions: Auto Run (a real on/off switch), Upgrades, Edit Mode, Collection
--   * top-center chips: Day / time and Invite a Friend; green "AUTO RUN" pill while Auto Run is on
--   * the notification dock (NotificationDock) in a second ScreenGui "HudTop"
-- Existing HUD buttons keep their parent and their click handlers (other controllers connect to them); this controller
-- only restyles and moves them. Upgrades / Collection / Edit Mode live in the Menu; Supply and My Shop are reached from
-- the Travel window (Warehouse / My Shop) so their old buttons are hidden, not deleted.
-- Placeholders (no game logic yet): Passes button (toast), Invite "boost" text. Day = in-game days since I joined.
-- Owner: Dev 1 (Ace). Depends on: HudKit, NotificationDock, AutoRunController, HudController (Notify), UiSkin, ClientState,
-- Shared.Config.DayNight, StarterGui.HUD (UI contract docs/03 section 8; new objects are listed there).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit"))
local NotificationDock = require(script.Parent.Parent:WaitForChild("NotificationDock"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local DayNight = require(Shared:WaitForChild("Config"):WaitForChild("DayNight"))
local Formulas = require(Shared:WaitForChild("Formulas"))

local HudLayoutController = {}
local DEBUG = true
local C = Skin.COLORS
local make = HudKit.make

local others: { [string]: any } = {}

-- ===== layout table (reference pixels; the HUD ScreenGui has a UIScale) =====
-- Tiles: existing button name -> where it goes and how it looks. Positions are inside the full-screen button containers.
local TILES = {
	Inventory = { art = "Inventory", label = "Inventory", tile = "Inventory", pos = UDim2.fromOffset(12, 84) },
	Travel = { art = "Travel", label = "Travel", tile = "Travel", pos = UDim2.new(1, -74, 0, 76) },
	Visit = { art = "Visit", label = "Visit Shops", tile = "Visit", pos = UDim2.new(1, -74, 0, 146) },
	Players = { art = "Invite", label = "Players", tile = "Menu", pos = UDim2.new(1, -74, 0, 216) }, -- PlayerListController's tile (our own player list)
	Settings = { art = "Settings", label = "Settings", tile = "Settings", pos = UDim2.new(1, -74, 0, 6) },
	Sprint = { art = "Sprint", label = "Sprint", tile = "Sprint", pos = UDim2.new(1, -172, 1, -76) },
}
-- Menu flyout cells: button name -> grid slot (col, row), label, icon, medallion colour.
local CELLS = {
	AutoRun = { slot = Vector2.new(0, 0), label = "Auto Run", art = "AutoRun", color = Color3.fromRGB(63, 167, 255), toggle = true },
	Upgrades = { slot = Vector2.new(1, 0), label = "Upgrades", art = "Upgrades", color = Color3.fromRGB(255, 138, 61) },
	EditShop = { slot = Vector2.new(0, 1), label = "Edit Mode", art = "EditMode", color = Color3.fromRGB(145, 104, 255) },
	Collection = { slot = Vector2.new(1, 1), label = "Collection", art = "Collection", color = Color3.fromRGB(31, 194, 165) },
}
-- Old buttons that now live elsewhere (Travel window: Warehouse + My Shop). Hidden, never destroyed.
local HIDDEN = { Supply = true, MyShop = true }

local PANEL_POS = Vector2.new(12, 154)
local PANEL_SIZE = Vector2.new(194, 162)
local CELL_GAP = 6

local hud: ScreenGui? = nil
local top: ScreenGui? = nil
local plateApi: { [string]: any }? = nil
local skinned: { [Instance]: boolean } = {}
local menuCells: { [string]: GuiButton } = {}
local menuButton: GuiButton? = nil
local menuPanel: Frame? = nil
local menuOpen = false
local autoRunPill: GuiButton? = nil
local chipsFrame: Frame? = nil

local function log(...)
	if DEBUG then
		print("[HudLayoutController]", ...)
	end
end

local function notify(kind: string, text: string)
	local hudController = others.HudController
	if hudController and hudController.Notify then
		hudController.Notify(kind, text)
	end
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ===== menu =====

local function setMenuOpen(open: boolean)
	menuOpen = open
	if menuPanel then
		menuPanel.Visible = open
	end
	for _, cell in menuCells do
		cell.Visible = open
	end
	local button = menuButton
	if button then
		local face = button:FindFirstChild("DfFace")
		local icon = face and face:FindFirstChild("DfIcon")
		local label = face and face:FindFirstChild("DfLabel")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Skin.Art(if open then "Close" else "Menu")
		end
		if label and label:IsA("TextLabel") then
			label.Text = if open then "Close" else "Menu"
		end
		HudKit.SetActive(button, open)
	end
end

local function cellPosition(slot: Vector2): UDim2
	local x = PANEL_POS.X + 10 + slot.X * (HudKit.CELL_W + CELL_GAP)
	local y = PANEL_POS.Y + 28 + slot.Y * (HudKit.CELL_H + CELL_GAP)
	return UDim2.fromOffset(x, y)
end

local function skinCellButton(button: GuiButton, name: string)
	local spec = CELLS[name]
	HudKit.SkinCell(button, { label = spec.label, art = spec.art, color = spec.color, toggle = spec.toggle })
	button.AnchorPoint = Vector2.zero
	button.Position = cellPosition(spec.slot)
	button.Visible = menuOpen
	button.ZIndex = 5
	menuCells[name] = button
	if name ~= "AutoRun" then
		button.Activated:Connect(function()
			setMenuOpen(false) -- picking an action closes the flyout (like the old drawer)
		end)
	end
end

local function buildMenu(left: Frame)
	local panel = make("Frame", {
		Name = "MenuPanel", BackgroundColor3 = C.walnut, BorderSizePixel = 0, Visible = false, ZIndex = 4,
		Position = UDim2.fromOffset(PANEL_POS.X, PANEL_POS.Y), Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
	}, left)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, panel)
	make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(112, 74, 52), Color3.fromRGB(46, 29, 20)) }, panel)
	HudKit.Label(panel, {
		Name = "Title", Text = "SHOP MENU", FontFace = Skin.FONT_TITLE, TextSize = 14, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(150, 18), ZIndex = 5,
	})
	menuPanel = panel

	-- the Menu tile itself (a new button; the old drawer button is gone)
	local button = make("ImageButton", { Name = "Menu", ZIndex = 3, Position = UDim2.fromOffset(80, 84) }, left)
	local colors = Skin.TILE.Menu
	HudKit.SkinTile(button, { label = "Menu", art = "Menu", face = colors.face, lip = colors.lip })
	button.Activated:Connect(function()
		setMenuOpen(not menuOpen)
	end)
	menuButton = button
	skinned[button] = true

	-- Auto Run: a new cell (no old button exists) wired to AutoRunController
	local autoRun = make("ImageButton", { Name = "AutoRun" }, left)
	skinCellButton(autoRun, "AutoRun")
	skinned[autoRun] = true
	autoRun.Activated:Connect(function()
		local controller = others.AutoRunController
		if controller then
			controller.Toggle()
		end
	end)
end

-- ===== existing buttons =====

local function placeButton(button: Instance)
	if not button:IsA("GuiButton") or skinned[button] then
		return
	end
	local name = button.Name
	local tile = TILES[name]
	if tile then
		skinned[button] = true
		local colors = Skin.TILE[tile.tile]
		HudKit.SkinTile(button, { label = tile.label, art = tile.art, face = colors.face, lip = colors.lip })
		button.AnchorPoint = Vector2.zero
		button.Position = tile.pos
		button.LayoutOrder = 0
		button.ZIndex = 3
		button.Visible = if name == "Sprint" then isPhone() else true
	elseif CELLS[name] then
		skinned[button] = true
		skinCellButton(button, name)
	elseif HIDDEN[name] then
		skinned[button] = true
		button.Visible = false
	end
end

local function prepareContainer(frame: Frame)
	for _, child in frame:GetChildren() do
		if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then
			child:Destroy() -- we position every button ourselves
		end
	end
	frame.AnchorPoint = Vector2.zero
	frame.Position = UDim2.fromOffset(0, 0)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.Active = false
end

-- ===== status plate =====

local function compactCash(amount: number): string
	if amount >= 1e9 then
		return string.format("$%.1fB", amount / 1e9)
	elseif amount >= 1e6 then
		return string.format("$%.1fM", amount / 1e6)
	elseif amount >= 100000 then
		return string.format("$%dK", math.floor(amount / 1000))
	end
	return UiTheme.formatCash(amount)
end

local function updatePlate()
	local api = plateApi
	if api == nil then
		return
	end
	local values: { [string]: any } = {}
	local cash = ClientState.Get("cash")
	if type(cash) == "number" then
		values.cash = compactCash(cash)
	end
	local level = ClientState.Get("level")
	local xp = ClientState.Get("xp")
	if type(level) == "number" and type(xp) == "number" then
		if level >= Economy.MaxLevel then
			values.level = `LEVEL {level} MAX`
			values.progress = 1
			values.xpText = "Shop XP MAX"
		else
			local needed = Formulas.xpToNext(level)
			values.level = `LEVEL {level}`
			values.progress = if needed > 0 then xp / needed else 0
			values.xpText = `Shop XP {xp} / {needed}`
		end
	end
	local rating = ClientState.Get("rating")
	if type(rating) == "number" then
		values.stars = math.clamp(math.floor(rating), 0, 5)
	end
	api.Update(values)
end

-- ===== top chips =====

local function formatClock(clock: number): string
	local hours = math.floor(clock) % 24
	local minutes = math.floor((clock - math.floor(clock)) * 60)
	local suffix = if hours >= 12 then "PM" else "AM"
	local h12 = hours % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, minutes, suffix)
end

local function cycleSeconds(): number
	local total = 0
	for _, segment in DayNight.SEGMENTS do
		total += segment.seconds
	end
	return math.max(total, 1)
end

local function requestInvite()
	local player = Players.LocalPlayer
	local okCheck, canSend = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if not okCheck or not canSend then
		notify("Info", "Invites aren't available right now")
		return
	end
	local okShow = pcall(SocialService.PromptGameInvite, SocialService, player)
	if not okShow then
		notify("Info", "Couldn't open the invite window")
	end
end

local function buildChips(gui: ScreenGui)
	local holder = make("Frame", {
		Name = "TopChips", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2,
	}, gui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, holder)
	chipsFrame = holder

	local day = HudKit.Chip(holder, { name = "DayChip", art = "Clock", sub = "DAY 1", title = "--:--" })
	local dayFrame: any = day.Frame
	dayFrame.LayoutOrder = 1

	local invite = HudKit.Chip(holder, {
		name = "InviteChip", art = "Invite", sub = "INVITE A FRIEND", title = "Boost: soon", color = Skin.TILE.GamePasses.face, clickable = true,
	})
	local inviteFrame: any = invite.Frame
	inviteFrame.LayoutOrder = 2
	inviteFrame.Activated:Connect(requestInvite)

	task.spawn(function()
		local cycle = cycleSeconds()
		-- "Day N" = how many in-game days I have played since I joined (Ace, 2026-11-25): Day 1 on joining, +1 every time the
		-- server clock passes a full day-night cycle. Per player, so a friend who joined later is on a lower day.
		local joinDay = math.floor(workspace.DistributedGameTime / cycle)
		while gui.Parent do
			local dayNumber = math.floor(workspace.DistributedGameTime / cycle) - joinDay + 1
			day.SetTexts(`DAY {dayNumber}`, formatClock(Lighting.ClockTime))
			task.wait(1)
		end
	end)
end

-- ===== Auto Run pill =====

local function buildAutoRunPill(gui: ScreenGui)
	local pill = make("ImageButton", {
		Name = "AutoRunPill", AutoButtonColor = false, Image = "", BackgroundColor3 = Color3.fromRGB(46, 158, 79), BorderSizePixel = 0, Visible = false, ZIndex = 6,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38),
	}, gui)
	if isPhone() then
		pill.AnchorPoint = Vector2.new(1, 1)
		pill.Position = UDim2.new(1, -86, 1, -84)
	else
		pill.AnchorPoint = Vector2.new(0, 1)
		pill.Position = UDim2.new(0, 12, 1, -16)
	end
	make("UICorner", { CornerRadius = UDim.new(0, 19) }, pill)
	make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 14) }, pill)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, pill)
	make("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = Skin.Art("AutoRun"), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(24, 24), LayoutOrder = 1 }, pill)
	local texts = make("Frame", { Name = "Texts", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2 }, pill)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, texts)
	local title = HudKit.Label(texts, {
		Name = "Title", Text = "AUTO RUN", FontFace = Skin.FONT_TITLE, TextSize = 14, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 16), LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
	HudKit.Label(texts, {
		Name = "Sub", Text = "ON · tap to stop", TextSize = 11, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 13), LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	pill.Activated:Connect(function()
		local controller = others.AutoRunController
		if controller then
			controller.Set(false)
		end
	end)
	autoRunPill = pill
end

local function onAutoRunChanged(isOn: boolean)
	if autoRunPill then
		autoRunPill.Visible = isOn
	end
	local cell = menuCells.AutoRun
	if cell then
		HudKit.SetToggle(cell, isOn)
	end
end

-- ===== screen shape (dock position, scale sync) =====

local function applyScreenShape()
	local camera = workspace.CurrentCamera
	local hudGui = hud
	local topGui = top
	if camera == nil or hudGui == nil or topGui == nil then
		return
	end
	local scaleObject = hudGui:FindFirstChildOfClass("UIScale")
	local scale = if scaleObject then scaleObject.Scale else 1
	local topScale = topGui:FindFirstChildOfClass("UIScale")
	if topScale then
		topScale.Scale = scale
	end
	local widthRef = camera.ViewportSize.X / scale
	if widthRef < 800 then
		-- phones: the dock sits between the status plate (ends x 312) and the top-right buttons
		local width = math.clamp(widthRef - 318 - 150, 170, 262)
		NotificationDock.SetLayout(UDim2.fromOffset(318, 56), Vector2.new(0, 0), width, if width < 200 then 2 else 3)
	else
		NotificationDock.SetLayout(UDim2.new(0.5, 0, 0, 56), Vector2.new(0.5, 0), 270, 3)
	end
end

-- ===== window focus: a soft blur of the world while any window is open (off with Reduce effects) =====

local WINDOW_PARTS = { { "Inventory", "Window" }, { "Supply", "Window" }, { "Upgrades", "Window" }, { "Settings", "Window" }, { "Collection", "Book" }, { "Visit", "Window" } }
local BLUR_SIZE = 6
local focusBlur: BlurEffect? = nil
local focusConnected: { [Instance]: boolean } = {}

local function anyWindowOpen(playerGui: Instance): boolean
	for _, part in WINDOW_PARTS do
		local screen = playerGui:FindFirstChild(part[1])
		local window = screen and screen:FindFirstChild(part[2])
		if window and window:IsA("GuiObject") and window.Visible then
			return true
		end
	end
	local travel = playerGui:FindFirstChild("Travel")
	return travel ~= nil and travel:IsA("ScreenGui") and travel.Enabled
end

local function refreshFocus(playerGui: Instance)
	if focusBlur == nil then
		focusBlur = make("BlurEffect", { Name = "DfWindowBlur", Size = 0 }, Lighting)
	end
	local want = anyWindowOpen(playerGui) and not HudKit.Reduced()
	TweenService:Create(focusBlur :: BlurEffect, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = if want then BLUR_SIZE else 0 }):Play()
end

local function setupWindowFocus(playerGui: Instance)
	local function hook()
		for _, part in WINDOW_PARTS do
			local screen = playerGui:FindFirstChild(part[1])
			local window = screen and screen:FindFirstChild(part[2])
			if window and window:IsA("GuiObject") and not focusConnected[window] then
				focusConnected[window] = true
				window:GetPropertyChangedSignal("Visible"):Connect(function()
					refreshFocus(playerGui)
				end)
			end
		end
		local travel = playerGui:FindFirstChild("Travel")
		if travel and travel:IsA("ScreenGui") and not focusConnected[travel] then
			focusConnected[travel] = true
			travel:GetPropertyChangedSignal("Enabled"):Connect(function()
				refreshFocus(playerGui)
			end)
		end
	end
	hook()
	playerGui.ChildAdded:Connect(function()
		task.defer(hook)
	end)
	ClientState.OnChanged("settings", function()
		refreshFocus(playerGui)
	end)
end

-- ===== lifecycle =====

function HudLayoutController.Init(controllers)
	others = controllers
end

function HudLayoutController.Start()
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local foundHud = playerGui:WaitForChild("HUD", 15)
		if foundHud == nil then
			warn("[HudLayoutController] PlayerGui.HUD not found: layout skipped")
			return
		end
		hud = foundHud :: ScreenGui
		local left = hud:WaitForChild("LeftButtons", 15) :: Frame?
		local topRight = hud:WaitForChild("TopRight", 15) :: Frame?
		if left == nil or topRight == nil then
			warn("[HudLayoutController] HUD.LeftButtons / HUD.TopRight missing: layout skipped")
			return
		end

		-- second ScreenGui that ignores the Roblox top bar inset (chips + notifications live in the top band)
		top = make("ScreenGui", { Name = "HudTop", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
		make("UIScale", {}, top)

		prepareContainer(left)
		prepareContainer(topRight)

		-- status plate replaces the three old pills
		for _, name in { "MoneyPill", "RatingPill", "XPBar" } do
			local old = hud:FindFirstChild(name)
			if old and old:IsA("GuiObject") then
				old.Visible = false
			end
		end
		plateApi = HudKit.Plate(hud)
		updatePlate()
		for _, key in { "cash", "level", "xp", "rating" } do
			ClientState.OnChanged(key, updatePlate)
		end

		buildMenu(left)
		for _, container in { left, topRight } do
			for _, child in container:GetChildren() do
				placeButton(child)
			end
			container.ChildAdded:Connect(function(child)
				task.defer(placeButton, child)
			end)
		end

		-- Passes: new placeholder button (no Game Pass window exists yet)
		local passes = make("ImageButton", { Name = "GamePasses", ZIndex = 3 }, topRight)
		local passColors = Skin.TILE.GamePasses
		HudKit.SkinTile(passes, { label = "Passes", art = "GamePasses", face = passColors.face, lip = passColors.lip })
		passes.Position = UDim2.new(1, -142, 0, 6)
		passes.Activated:Connect(function()
			notify("Info", "Game Passes are coming soon!")
		end)
		skinned[passes] = true

		buildChips(top)
		buildAutoRunPill(top)
		NotificationDock.Init(top)
		NotificationDock.OnPriority(function(active)
			if chipsFrame then
				chipsFrame.Visible = not active
			end
		end)

		local autoRun = others.AutoRunController
		if autoRun then
			autoRun.OnChanged(onAutoRunChanged)
			onAutoRunChanged(autoRun.IsOn())
		end

		local scaleObject = hud:FindFirstChildOfClass("UIScale")
		if scaleObject then
			scaleObject:GetPropertyChangedSignal("Scale"):Connect(applyScreenShape)
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScreenShape)
		end
		applyScreenShape()
		setupWindowFocus(playerGui)
		log("layout applied")
	end)
end

return HudLayoutController
