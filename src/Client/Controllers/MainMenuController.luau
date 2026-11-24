-- MainMenuController.luau (StarterPlayerScripts.Client.Controllers.MainMenuController)
-- Purpose: the title menu after the loading screen (Sean's mockup, assets/loading/Log in Menu): a hanging wooden sign
-- with the logo, a big PLAY button with your shop's level and cash, Settings / Updates / Credits, and a pinned
-- "What's New" note, over a slow camera fly-over of your shop. Every other screen is hidden and your character can't
-- move until PLAY; then the camera swoops down to you and the game screens come back exactly as they were.
-- Buttons grow, tilt and brighten on hover (soft tick), squash on press (click); sounds go through SoundController,
-- so they follow the Settings sound-effects switch. Shown once per join.
-- Owner: Dev 3 (Sean). Depends on: Shared.Config.MainMenu (version, updates, credits), ClientState (level, cash),
-- SoundController.Play, SettingsController.Open, UiSkin.ICONS, UiTheme.formatCash, the PlayerModule (controls),
-- Workspace.Plots (OwnerUserId). Must start LAST in Main.local (it hides the screens the others made).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuConfig = require(Shared:WaitForChild("Config"):WaitForChild("MainMenu"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local MainMenuController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}

local function log(...)
	if DEBUG then
		print("[MainMenuController]", ...)
	end
end

-- ===== look (from the mockup) =====
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
local INK = Color3.fromRGB(59, 42, 30)
local CREAM = Color3.fromRGB(246, 236, 216)
local PAPER = Color3.fromRGB(250, 244, 230)
local WOOD, WOOD_LIGHT, WOOD_DARK = Color3.fromRGB(156, 106, 58), Color3.fromRGB(190, 138, 84), Color3.fromRGB(112, 72, 38)
local GOLD, GOLD_LIGHT = Color3.fromRGB(255, 176, 46), Color3.fromRGB(255, 214, 92)
local BROWN_ICON = Color3.fromRGB(150, 92, 52)
local SKIP_SCREENS = { MainMenu = true, LoadingScreen = true, Freecam = true }

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

local function tween(o: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(o, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function sfx(name: string)
	local sound = others.SoundController
	if sound and sound.Play then
		sound.Play(name)
	end
end

local function outline(parent: Instance, thickness: number, color: Color3?)
	return new("UIStroke", { Color = color or INK, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function corner(parent: Instance, px: number)
	return new("UICorner", { CornerRadius = UDim.new(0, px) }, parent)
end

local function label(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = text,
		TextScaled = true,
		TextColor3 = INK,
	}, parent)
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

-- a wooden board: warm gradient, dark outline, faint plank seams
local function wood(parent: Instance, name: string, props: { [string]: any }, planks: number?): Frame
	local f = new("Frame", { Name = name, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
	for k, v in props do
		(f :: any)[k] = v
	end
	new("UIGradient", { Color = ColorSequence.new(WOOD_LIGHT, WOOD), Rotation = 90 }, f)
	corner(f, 10)
	outline(f, 4)
	for i = 1, (planks or 0) - 1 do
		new("Frame", {
			Name = "Seam",
			Position = UDim2.new(0.04, 0, i / (planks :: number), 0),
			Size = UDim2.new(0.92, 0, 0, 2),
			BackgroundColor3 = WOOD_DARK,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
		}, f)
	end
	return f
end

-- ===== hover / press feel for every button =====

local function hoverable(button: GuiButton, base: Color3, tilt: number?)
	local scale = button:FindFirstChildOfClass("UIScale") or new("UIScale", {}, button)
	local hovered = false
	local function settle()
		tween(scale, 0.18, { Scale = if hovered then 1.07 else 1 }, Enum.EasingStyle.Back)
		tween(button, 0.18, {
			Rotation = if hovered then (tilt or -2) else 0,
			BackgroundColor3 = if hovered then base:Lerp(Color3.new(1, 1, 1), 0.35) else base,
		})
	end
	local function enter()
		if not hovered then
			hovered = true
			sfx("pick")
			settle()
		end
	end
	local function leave()
		hovered = false
		settle()
	end
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
	button.SelectionGained:Connect(enter) -- gamepad
	button.SelectionLost:Connect(leave)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.16, { Scale = if hovered then 1.07 else 1 }, Enum.EasingStyle.Back)
	end)
end

-- ===== state =====

local gui: ScreenGui? = nil
local root: CanvasGroup? = nil
local hidden: { [ScreenGui]: boolean } = {} -- screens we switched off, to switch back on at PLAY
local watcher: RBXScriptConnection? = nil
local flyover: RBXScriptConnection? = nil
local open = false
local controls: any = nil
local continueLabel: TextLabel? = nil
local windows: { [string]: Frame } = {}

local guards: { RBXScriptConnection } = {}
local settingsUp: ScreenGui? = nil -- the Settings screen while the menu has it open on top

local function hideOtherScreens()
	local playerGui = player:WaitForChild("PlayerGui")
	local function hide(g: Instance)
		if not g:IsA("ScreenGui") or SKIP_SCREENS[g.Name] then
			return
		end
		if g.Enabled then
			hidden[g] = true
			g.Enabled = false
		end
		-- a controller switching it back on while the menu is up: off again (shown at PLAY)
		table.insert(guards, g:GetPropertyChangedSignal("Enabled"):Connect(function()
			if open and g.Enabled and g ~= settingsUp then
				hidden[g] = true
				g.Enabled = false
			end
		end))
	end
	for _, g in playerGui:GetChildren() do
		hide(g)
	end
	-- screens made or switched on while the menu is up (late controllers, toasts) wait for PLAY too
	watcher = playerGui.ChildAdded:Connect(function(g)
		task.defer(hide, g)
	end)
end

local function restoreScreens()
	if watcher then
		watcher:Disconnect()
		watcher = nil
	end
	for _, c in guards do
		c:Disconnect()
	end
	table.clear(guards)
	for g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
end

local function setControls(enabled: boolean)
	if controls == nil then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)):GetControls()
		end)
		controls = if ok then module else false
	end
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

-- ===== camera: a slow orbit over my shop =====

local function myShopCenter(): Vector3?
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			if plot:IsA("Model") then
				return plot:GetPivot().Position
			end
			local counter = plot:FindFirstChild("Counter")
			if counter and counter:IsA("BasePart") then
				return counter.Position
			end
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function startFlyover()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	flyover = RunService.RenderStepped:Connect(function()
		local center = myShopCenter()
		if not center then
			return
		end
		local angle = (os.clock() - started) * 0.05 + 0.6
		local eye = center + Vector3.new(math.cos(angle) * 70, 38, math.sin(angle) * 70)
		cam.CFrame = CFrame.lookAt(eye, center + Vector3.new(0, 6, 0))
	end)
end

local function endFlyover(onDone: () -> ())
	if flyover then
		flyover:Disconnect()
		flyover = nil
	end
	local cam = workspace.CurrentCamera
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		-- swoop down to just behind the character, then hand the camera back to the player
		local target = CFrame.lookAt((rootPart.CFrame * CFrame.new(0, 5, 13)).Position, rootPart.Position + Vector3.new(0, 2, 0))
		local swoop = TweenService:Create(cam, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
		swoop:Play()
		swoop.Completed:Wait()
	end
	cam.CameraType = Enum.CameraType.Custom
	onDone()
end

-- ===== small windows (Updates, Credits) =====

local function closeWindows()
	for _, w in windows do
		w.Visible = false
	end
end

local function makeWindow(name: string, title: string): (Frame, ScrollingFrame)
	local w = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.42, 0.62),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
	}, root)
	corner(w, 14)
	outline(w, 4)
	local header = wood(w, "Header", { Size = UDim2.new(1, 0, 0.16, 0), ZIndex = 21 }, 2)
	label(header, title, {
		Position = UDim2.fromScale(0.05, 0.12),
		Size = UDim2.fromScale(0.75, 0.76),
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	})
	local close = new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.97, 0, 0.5, 0),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundColor3 = CREAM,
		FontFace = FONT,
		Text = "X",
		TextScaled = true,
		TextColor3 = INK,
		AutoButtonColor = false,
		ZIndex = 23,
	}, header)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, close)
	corner(close, 8)
	outline(close, 3)
	hoverable(close, CREAM, 0)
	close.Activated:Connect(function()
		sfx("click")
		w.Visible = false
	end)
	local list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.06, 0.2),
		Size = UDim2.fromScale(0.88, 0.76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = WOOD,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 21,
	}, w)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	windows[name] = w
	return w, list
end

local function listText(list: ScrollingFrame, text: string, order: number, big: boolean?, color: Color3?)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		FontFace = FONT,
		Text = text,
		TextSize = if big then 26 else 19,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or INK,
		LayoutOrder = order,
		ZIndex = 21,
	}, list)
end

local function openWindow(name: string)
	closeWindows()
	local w = windows[name]
	if not w then
		return
	end
	sfx("reveal")
	w.Visible = true
	local scale = w:FindFirstChildOfClass("UIScale") or new("UIScale", {}, w)
	scale.Scale = 0.85
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Settings: the game's own Settings window, lifted above the menu while it is open
local function openSettings()
	closeWindows()
	local settings = others.SettingsController
	local screen = player.PlayerGui:FindFirstChild("Settings")
	if not (settings and settings.Open and screen and screen:IsA("ScreenGui")) then
		return
	end
	local wasOrder = screen.DisplayOrder
	local wasHidden = hidden[screen] == true -- the menu switched it off: switch it off again when Settings closes
	hidden[screen] = nil
	settingsUp = screen
	screen.Enabled, screen.DisplayOrder = true, 950
	sfx("reveal")
	settings.Open()
	local window = screen:FindFirstChild("Window")
	if window and window:IsA("GuiObject") then
		local conn
		conn = window:GetPropertyChangedSignal("Visible"):Connect(function()
			if not window.Visible then
				conn:Disconnect()
				settingsUp = nil
				screen.DisplayOrder = wasOrder
				if open and wasHidden then
					screen.Enabled = false
					hidden[screen] = true
				end
			end
		end)
	end
end

-- ===== building the menu =====

local function updateContinue()
	if continueLabel then
		local level = ClientState.Get("level") or 1
		local cash = ClientState.Get("cash") or 0
		continueLabel.Text = `Continue: Lv {level} - {UiTheme.formatCash(cash)}`
	end
end

local function build()
	local screen = new("ScreenGui", {
		Name = "MainMenu",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 900, -- under the loading screen (1000), over everything else
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local canvas = new("CanvasGroup", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)

	-- soft vignette round the edges (the town shows through in the middle)
	for _, side in { { 0, 0.8, 0 }, { 180, 0.8, 0 }, { 90, 0.75, 1 }, { 270, 0.75, 1 } } do
		local v = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 1 }, canvas)
		new("UIGradient", {
			Rotation = side[1],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.22, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, v)
	end

	-- the layout keeps the mockup's 16:9 shape on any screen
	local stage = new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, canvas)
	new("UIAspectRatioConstraint", { AspectRatio = 16 / 9 }, stage)

	-- hanging sign: a beam across the top, two ropes, the logo board
	local beam = wood(stage, "Beam", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, -0.02), Size = UDim2.fromScale(0.4, 0.07), ZIndex = 3 }, 2)
	for _, x in { 0.43, 0.57 } do
		new("Frame", {
			Name = "Rope",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0.04),
			Size = UDim2.new(0, 5, 0.08, 0),
			BackgroundColor3 = Color3.fromRGB(196, 160, 110),
			BorderSizePixel = 0,
			ZIndex = 3,
		}, stage)
	end
	local sign = wood(stage, "Sign", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.11), Size = UDim2.fromScale(0.25, 0.25), ZIndex = 4 }, 3)
	local function signText(text: string, y: number, h: number, color: Color3)
		local l = label(sign, text, { Position = UDim2.fromScale(0.05, y), Size = UDim2.fromScale(0.9, h), TextColor3 = color, ZIndex = 5 })
		new("UIStroke", { Color = INK, Thickness = 3 }, l)
		return l
	end
	signText("DUSTY", 0.06, 0.34, CREAM)
	signText("FINDS", 0.38, 0.34, Color3.fromRGB(232, 190, 120))
	signText("RESTORE & SELL", 0.74, 0.18, CREAM)

	-- PLAY
	local play = new("TextButton", {
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.25, 0.18),
		BackgroundColor3 = CREAM,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
	}, stage)
	corner(play, 14)
	outline(play, 5)
	local playText = label(play, "PLAY", { Position = UDim2.fromScale(0.08, 0.12), Size = UDim2.fromScale(0.84, 0.76), TextColor3 = Color3.new(1, 1, 1), ZIndex = 6 })
	new("UIGradient", { Color = ColorSequence.new(GOLD_LIGHT, GOLD), Rotation = 90 }, playText)
	new("UIStroke", { Color = INK, Thickness = 4 }, playText)
	hoverable(play, CREAM, -2)
	local tag = new("Frame", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.605),
		Size = UDim2.fromScale(0.2, 0.045),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, stage)
	corner(tag, 6)
	continueLabel = label(tag, "", { Position = UDim2.fromScale(0.04, 0.12), Size = UDim2.fromScale(0.92, 0.76), TextColor3 = CREAM, ZIndex = 6 })
	updateContinue()

	-- Settings / Updates / Credits
	local small = {
		{ name = "Settings", text = "SETTINGS", icon = UiSkin.ICONS.Settings, x = 0.393, color = BROWN_ICON },
		{ name = "Updates", text = "UPDATES", icon = UiSkin.ICONS.Bell, x = 0.5, color = BROWN_ICON },
		{ name = "Credits", text = "CREDITS", icon = UiSkin.ICONS.Star, x = 0.607, color = GOLD },
	}
	local buttons = { Play = play }
	for i, b in small do
		local btn = new("TextButton", {
			Name = b.name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(b.x, 0.7),
			Size = UDim2.fromScale(0.093, 0.17),
			BackgroundColor3 = CREAM,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 5,
		}, stage)
		corner(btn, 10)
		outline(btn, 4)
		new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.52, 0.52),
			BackgroundTransparency = 1,
			Image = b.icon or "",
			ImageColor3 = b.color,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 6,
		}, btn)
		local t = label(btn, b.text, { Position = UDim2.fromScale(0.06, 0.66), Size = UDim2.fromScale(0.88, 0.24), TextColor3 = BROWN_ICON, ZIndex = 6 })
		new("UIStroke", { Color = CREAM, Thickness = 1.5 }, t)
		hoverable(btn, CREAM, if i == 1 then -3 elseif i == 3 then 3 else -2)
		buttons[b.name] = btn
	end

	-- "What's New": a board on the right with a pinned paper note (opens Updates)
	local board = wood(stage, "NewsBoard", { Position = UDim2.fromScale(0.765, 0.38), Size = UDim2.fromScale(0.26, 0.26), ZIndex = 3 }, 3)
	local note = new("TextButton", {
		Name = "Note",
		Position = UDim2.fromScale(0.81, 0.385),
		Size = UDim2.fromScale(0.13, 0.225),
		Rotation = 3,
		BackgroundColor3 = PAPER,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 6,
	}, stage)
	outline(note, 2, Color3.fromRGB(190, 170, 140))
	local pin = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.82, 0.04),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.fromRGB(200, 70, 60),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, note)
	corner(pin, 999)
	label(note, "What's New", { Position = UDim2.fromScale(0.08, 0.1), Size = UDim2.fromScale(0.84, 0.17), ZIndex = 7 })
	new("Frame", { Position = UDim2.fromScale(0.12, 0.3), Size = UDim2.new(0.76, 0, 0, 2), BackgroundColor3 = INK, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 7 }, note)
	local newest = MenuConfig.UPDATES[1]
	label(note, if newest then newest.lines[1] else "", { Position = UDim2.fromScale(0.1, 0.38), Size = UDim2.fromScale(0.8, 0.5), TextWrapped = true, ZIndex = 7 })
	hoverable(note, PAPER, 6)
	buttons.Note = note

	-- version label
	label(stage, MenuConfig.VERSION, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.01, 0.985),
		Size = UDim2.fromScale(0.05, 0.035),
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})

	-- Updates and Credits windows
	root = canvas
	local _, updates = makeWindow("Updates", "What's New")
	for i, u in MenuConfig.UPDATES do
		listText(updates, `{u.title}  ({u.date})`, i * 10, true, WOOD_DARK)
		for k, line in u.lines do
			listText(updates, "• " .. line, i * 10 + k)
		end
	end
	local _, credits = makeWindow("Credits", "Credits")
	listText(credits, "Made by a team of three:", 0)
	for i, c in MenuConfig.CREDITS do
		local nameLabel = listText(credits, c.name, i * 10, true, WOOD_DARK)
		listText(credits, c.role, i * 10 + 1)
		task.spawn(function() -- the dev's current Roblox username (names can change)
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(c.userId)
			end)
			if ok and type(name) == "string" then
				nameLabel.Text = name
			end
		end)
	end
	listText(credits, "Thanks for playing Dusty Finds!", 100, false, BROWN_ICON)

	gui = screen
	return buttons, { beam = beam, sign = sign, play = play, tag = tag, board = board, note = note }
end

-- ===== show / play =====

local function entrance(parts: { [string]: GuiObject })
	-- the sign drops in on its ropes, the buttons pop up one after another
	local sign = parts.sign
	local home = sign.Position
	sign.Position = home - UDim2.fromScale(0, 0.35)
	tween(sign, 0.7, { Position = home }, Enum.EasingStyle.Bounce)
	for i, key in { "play", "tag", "note" } do
		local o = parts[key]
		local s = o:FindFirstChildOfClass("UIScale") or new("UIScale", {}, o)
		s.Scale = 0.6
		task.delay(0.15 + i * 0.08, function()
			tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	task.delay(0.35, sfx, "snap")
end

local function play()
	if not open then
		return
	end
	open = false
	closeWindows()
	sfx("levelUp")
	local canvas = root :: CanvasGroup
	tween(canvas, 0.45, { GroupTransparency = 1 })
	task.spawn(function()
		endFlyover(function()
			restoreScreens()
			setControls(true)
			if gui then
				gui:Destroy()
				gui = nil
			end
			log("PLAY: back to the game")
		end)
	end)
end

function MainMenuController.IsOpen(): boolean
	return open
end

function MainMenuController.Init(controllers)
	others = controllers
end

function MainMenuController.Start()
	open = true
	hideOtherScreens()
	setControls(false)
	startFlyover()
	local buttons, parts = build()
	buttons.Play.Activated:Connect(function()
		sfx("click")
		play()
	end)
	buttons.Settings.Activated:Connect(function()
		sfx("click")
		openSettings()
	end)
	buttons.Updates.Activated:Connect(function()
		sfx("click")
		openWindow("Updates")
	end)
	buttons.Note.Activated:Connect(function()
		sfx("click")
		openWindow("Updates")
	end)
	buttons.Credits.Activated:Connect(function()
		sfx("click")
		openWindow("Credits")
	end)
	ClientState.OnChanged("cash", updateContinue)
	ClientState.OnChanged("level", updateContinue)
	-- the entrance plays as the loading screen fades away (or straight away if there is none)
	task.spawn(function()
		local loading = player.PlayerGui:FindFirstChild("LoadingScreen")
		if loading then
			loading.AncestryChanged:Wait()
		end
		entrance(parts)
	end)
	log("ready: menu up, waiting for PLAY")
end

return MainMenuController
