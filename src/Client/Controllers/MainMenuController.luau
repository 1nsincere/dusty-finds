-- MainMenuController.luau (StarterPlayerScripts.Client.Controllers.MainMenuController)
-- Purpose: the title menu after the loading screen. Look: the Figma "Main Menu — Proposal" title design (golden hour):
-- the magnifier emblem, a big gold DUSTY FINDS title with a RESTORE & SELL plaque, a chunky 3D PLAY button, a Continue
-- chip (level + cash), Settings / Updates / Credits tiles bottom-left, a pinned "What's New" card, the player chip and
-- the version label, over a warm-tinted camera fly-over of your shop with drifting bokeh and sun rays.
-- Behaviour (Sean): every other screen is hidden and your character can't move until PLAY; then the camera swoops to you
-- and the screens come back exactly as they were. Hover = grow / tilt / brighten + soft tick, press = squash + click,
-- all sounds through SoundController (they follow the sound-effects setting). Shown once per join.
-- Built at the design size (1280 x 720) in pixels; a UIScale fits it to the screen (corner groups stay in the corners).
-- Owner: Dev 3 (Sean). Depends on: Shared.Config.MainMenu (version, updates, credits), Shared.Config.UiSkin (icons),
-- ClientState (level, cash), UiTheme.formatCash, SoundController.Play, SettingsController.Open, the PlayerModule
-- (controls), Workspace.Plots (OwnerUserId), the team's Roblox group (Credits roles). Must start LAST in Main.local.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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

-- ===== look (Figma title design) =====
local FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_TEXT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local INK = Color3.fromRGB(43, 26, 16) -- outlines
local CREAM = Color3.fromRGB(255, 243, 220)
local DIM = Color3.fromRGB(214, 190, 160)
local GOLD_TOP, GOLD_BOTTOM = Color3.fromRGB(255, 232, 140), Color3.fromRGB(246, 166, 35)
local LIP = Color3.fromRGB(196, 98, 31) -- the PLAY button's 3D bottom edge
local WOOD, WOOD_DARK = Color3.fromRGB(92, 58, 38), Color3.fromRGB(58, 36, 24)
local PANEL_TOP, PANEL_BOTTOM = Color3.fromRGB(94, 61, 41), Color3.fromRGB(62, 39, 26)
local PANEL_EDGE = Color3.fromRGB(200, 145, 63)
local PAPER = Color3.fromRGB(251, 243, 226)
local PLUM = Color3.fromRGB(122, 46, 90)
local RED = Color3.fromRGB(232, 85, 62)
local DESIGN = Vector2.new(1280, 720)
local IMG = {
	emblem = "rbxassetid://100622808127569", -- magnifier logo emblem (Figma)
	news = "rbxassetid://132825925023293", -- newspaper icon (Figma)
	heart = "rbxassetid://71092970737679", -- heart icon (Figma)
}
local SKIP_SCREENS = { MainMenu = true, LoadingScreen = true, Freecam = true }
local ORBIT_RADIUS, ORBIT_HEIGHT = 135, 80 -- the menu camera's circle round your shop (studs)
local GROUP_ID = 165295576 -- the team's Roblox group: Credits shows each dev's role in it
local BADGE_COLORS = { Color3.fromRGB(255, 196, 46), Color3.fromRGB(38, 186, 160), Color3.fromRGB(130, 96, 240) }

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

local function corner(parent: Instance, px: number)
	return new("UICorner", { CornerRadius = UDim.new(0, px) }, parent)
end

local function stroke(parent: Instance, thickness: number, color: Color3?, transparency: number?)
	return new("UIStroke", {
		Color = color or INK,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function gradient(parent: Instance, top: Color3, bottom: Color3)
	return new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

-- design-pixel text (the UIScale on the group scales it with everything else)
local function text(parent: Instance, value: string, x: number, y: number, w: number, h: number, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		FontFace = FONT_TEXT,
		Text = value,
		TextSize = h,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	return l
end

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	return f
end

-- ===== hover / press feel =====

-- grow + tilt + brighten (a soft gold glow ring) with a tick; squash while pressed
local function hoverable(button: GuiButton, tilt: number?, glow: UIStroke?)
	-- its own UIScale ("Hover"): the entrance animation uses the other one and used to fight with this
	local scale = button:FindFirstChild("Hover") or new("UIScale", { Name = "Hover" }, button)
	local hovered = false
	local lastTick = 0
	local function settle()
		-- no overshoot: growing past the edge of the button under a still cursor made it flicker in and out
		tween(scale, 0.14, { Scale = if hovered then 1.06 else 1 })
		tween(button, 0.14, { Rotation = if hovered then (tilt or -2) else 0 })
		if glow then
			tween(glow, 0.14, { Transparency = if hovered then 0.15 else 1 })
		end
	end
	local function pointerInside(): boolean
		local p = UserInputService:GetMouseLocation() -- includes the top-bar inset, like an IgnoreGuiInset screen
		local a, s = button.AbsolutePosition, button.AbsoluteSize
		return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
	end
	local function enter()
		if hovered then
			return
		end
		hovered = true
		if os.clock() - lastTick > 0.2 then -- one tick per real hover, not per flicker
			lastTick = os.clock()
			sfx("hover")
		end
		settle()
	end
	local function leave()
		-- the button moves and tilts under the cursor, which fires a false "leave": check the cursor again a moment later
		task.delay(0.05, function()
			if hovered and not pointerInside() then
				hovered = false
				settle()
			end
		end)
	end
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
	button.SelectionGained:Connect(enter) -- gamepad
	button.SelectionLost:Connect(function()
		hovered = false
		settle()
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.08, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.12, { Scale = if hovered then 1.06 else 1 })
	end)
end

local function glowRing(parent: GuiObject, thickness: number): UIStroke
	return new("UIStroke", {
		Name = "Glow",
		Color = Color3.fromRGB(255, 214, 92),
		Thickness = thickness,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- ===== state =====

local gui: ScreenGui? = nil
local root: Frame? = nil
local center: Frame? = nil -- the 1280 x 720 design group (title, PLAY)
local windowLayer: Frame? = nil -- the windows (What's New, Credits), above everything else
local hidden: { [ScreenGui]: boolean } = {} -- screens we switched off, to switch back on at PLAY
local watcher: RBXScriptConnection? = nil
local flyover: RBXScriptConnection? = nil
local ambience: RBXScriptConnection? = nil
local open = false
local controls: any = nil
local continueLevel: TextLabel? = nil
local continueCash: TextLabel? = nil
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

-- ===== camera: a slow, wide orbit over my shop =====

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
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil
end

local function startFlyover()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	flyover = RunService.RenderStepped:Connect(function()
		local c = myShopCenter()
		if not c then
			return
		end
		local angle = (os.clock() - started) * 0.04 + 0.6
		local eye = c + Vector3.new(math.cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, math.sin(angle) * ORBIT_RADIUS)
		cam.CFrame = CFrame.lookAt(eye, c + Vector3.new(0, 4, 0))
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
		local swoop = TweenService:Create(cam, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
		swoop:Play()
		swoop.Completed:Wait()
	end
	cam.CameraType = Enum.CameraType.Custom
	onDone()
end

-- ===== windows (What's New, Credits): dark wood panel, gold title, red close =====

local function closeWindows()
	for _, w in windows do
		w.Visible = false
	end
end

local function makeWindow(name: string, title: string, icon: string): (Frame, ScrollingFrame)
	local w = box(windowLayer :: Frame, name, 248, 133, 784, 455, Color3.new(1, 1, 1), { Visible = false, ZIndex = 30 })
	gradient(w, PANEL_TOP, PANEL_BOTTOM)
	corner(w, 22)
	stroke(w, 6, INK)
	local rim = box(w, "Rim", 6, 6, 772, 443, Color3.new(1, 1, 1), { BackgroundTransparency = 1, ZIndex = 30 })
	corner(rim, 18)
	stroke(rim, 2, PANEL_EDGE)
	new("ImageLabel", {
		Name = "Icon",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(50, 50),
		BackgroundTransparency = 1,
		Image = icon,
		ZIndex = 31,
	}, w)
	local t = text(w, title, 76, 16, 500, 42, { FontFace = FONT_TITLE, TextColor3 = Color3.new(1, 1, 1), ZIndex = 31 })
	gradient(t, GOLD_TOP, GOLD_BOTTOM)
	new("UIStroke", { Color = INK, Thickness = 3 }, t)
	local close = new("ImageButton", {
		Name = "Close",
		Position = UDim2.fromOffset(714, 10),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = RED,
		Image = UiSkin.Art("Close"),
		AutoButtonColor = false,
		ZIndex = 32,
	}, w)
	corner(close, 12)
	stroke(close, 3, INK)
	hoverable(close, 0)
	close.Activated:Connect(function()
		sfx("click")
		w.Visible = false
	end)
	local list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.fromOffset(752, 362),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = PANEL_EDGE,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 31,
	}, w)
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2) }, list)
	windows[name] = w
	return w, list
end

-- a dark card inside a window list
local function rowCard(list: ScrollingFrame, order: number, height: number): Frame
	local r = new("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = WOOD_DARK,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 31,
	}, list)
	corner(r, 14)
	stroke(r, 3, INK)
	return r
end

local function buildUpdates()
	local _, list = makeWindow("Updates", "WHAT'S NEW", IMG.news)
	for i, u in MenuConfig.UPDATES do
		local lines = #u.lines
		local r = rowCard(list, i, 58 + lines * 30)
		text(r, u.title, 16, 8, 420, 30, { FontFace = FONT_TITLE, ZIndex = 32 })
		if i == 1 then
			local badge = box(r, "New", 230, 12, 46, 24, RED, { ZIndex = 32 })
			corner(badge, 6)
			stroke(badge, 2, INK)
			text(badge, "NEW", 0, 2, 46, 18, { FontFace = FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 33 })
		end
		local date = box(r, "Date", 640, 12, 64, 26, Color3.fromRGB(36, 22, 14), { ZIndex = 32 })
		corner(date, 8)
		text(date, u.date, 0, 4, 64, 17, { TextColor3 = GOLD_BOTTOM, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 33 })
		for k, line in u.lines do
			text(r, "▪ " .. line, 16, 44 + (k - 1) * 30, 690, 19, { TextWrapped = true, TextColor3 = CREAM, ZIndex = 32 })
		end
	end
end

local function buildCredits()
	local _, list = makeWindow("Credits", "CREDITS", IMG.heart)
	for i, c in MenuConfig.CREDITS do
		local r = rowCard(list, i, 64)
		local colour = BADGE_COLORS[(i - 1) % #BADGE_COLORS + 1]
		local badge = box(r, "Badge", 12, 10, 44, 44, colour, { ZIndex = 32 })
		corner(badge, 999)
		stroke(badge, 3, INK)
		local letter = text(badge, string.upper(string.sub(c.name, 1, 1)), 0, 6, 44, 30, {
			FontFace = FONT_TITLE,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 33,
		})
		new("UIStroke", { Color = INK, Thickness = 2 }, letter)
		local nameLabel = text(r, c.name, 70, 4, 500, 28, { FontFace = FONT_TITLE, ZIndex = 32 })
		local pill = box(r, "Role", 68, 34, 0, 26, colour, { AutomaticSize = Enum.AutomaticSize.X, ZIndex = 32 })
		corner(pill, 8)
		stroke(pill, 2, INK)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, pill)
		local roleLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = FONT_TEXT,
			Text = c.role,
			TextSize = 16,
			TextColor3 = INK,
			ZIndex = 33,
		}, pill)
		task.spawn(function() -- the dev's current Roblox username (names can change)
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(c.userId)
			end)
			if ok and type(name) == "string" then
				nameLabel.Text = name
				letter.Text = string.upper(string.sub(name, 1, 1))
			end
		end)
		task.spawn(function() -- their role in the team's Roblox group, live (falls back to the config role)
			local ok, groups = pcall(function()
				return GroupService:GetGroupsAsync(c.userId)
			end)
			if ok and type(groups) == "table" then
				for _, g in groups do
					if g.Id == GROUP_ID and type(g.Role) == "string" and g.Role ~= "" then
						-- everyone on the team develops: "Founder" -> "Founder / Dev" ("Developer" stays as it is)
						roleLabel.Text = if g.Role:lower():find("dev") then g.Role else g.Role .. " / Dev"
						break
					end
				end
			end
		end)
	end
	local foot = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, LayoutOrder = 100, ZIndex = 31 }, list)
	text(foot, `Thanks for playing!  ·  Dusty Finds {MenuConfig.VERSION}`, 0, 8, 752, 20, { TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 32 })
	text(foot, "Made with care by a team of three", 0, 32, 752, 17, { TextColor3 = Color3.fromRGB(170, 140, 110), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 32 })
end

local function openWindow(name: string)
	if not open then -- PLAY was pressed: the menu is on its way out
		return
	end
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
	if not open then
		return
	end
	closeWindows()
	local settings = others.SettingsController
	local screen = player.PlayerGui:FindFirstChild("Settings")
	if not (settings and settings.Open and screen and screen:IsA("ScreenGui")) then
		return
	end
	local wasOrder = screen.DisplayOrder
	local wasInsets = screen.ScreenInsets
	local wasHidden = hidden[screen] == true -- the menu switched it off: switch it off again when Settings closes
	hidden[screen] = nil
	settingsUp = screen
	-- same full-screen area as the menu, so it is not inset on notch phones (put back when it closes)
	screen.Enabled, screen.DisplayOrder, screen.ScreenInsets = true, 950, Enum.ScreenInsets.None
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
				screen.ScreenInsets = wasInsets
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
	if continueLevel and continueCash then
		continueLevel.Text = `Lv {ClientState.Get("level") or 1}`
		continueCash.Text = UiTheme.formatCash(ClientState.Get("cash") or 0)
	end
end

-- a group laid out in design pixels, pinned to a point of the screen and scaled to fit it
local function designGroup(parent: Instance, name: string, anchor: Vector2, size: Vector2, zindex: number): Frame
	local f = new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = zindex,
	}, parent)
	new("UIScale", { Name = "Fit" }, f)
	return f
end

local function build()
	local screen = new("ScreenGui", {
		Name = "MainMenu",
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None, -- on phones the default safe-area inset cropped the golden wash to a box (Ace, 2026-11-25)
		ResetOnSpawn = false,
		DisplayOrder = 900, -- under the loading screen (1000), over everything else
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	-- a plain Frame, not a CanvasGroup: a CanvasGroup draws everything into one texture first, which made the whole menu
	-- (text, icons, edges) look soft/blurry (Ace, 2026-11-25). PLAY fades the pieces one by one instead.
	local canvas = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)
	root = canvas

	-- golden-hour wash over the live town: warm at the top, dark brown at the bottom, sun rays, drifting bokeh
	local wash = new("Frame", { Name = "Wash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1 }, canvas)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 80)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(150, 85, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 22, 12)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.62),
			NumberSequenceKeypoint.new(0.55, 0.72),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
	}, wash)
	local rays = new("Frame", { Name = "Rays", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, ClipsDescendants = true }, canvas)
	for i = 0, 4 do
		local r = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.9 - i * 0.05, 0.25 + i * 0.08),
			Size = UDim2.new(0, 46 + i * 10, 1.4, 0),
			Rotation = 38,
			BackgroundColor3 = Color3.fromRGB(255, 236, 190),
			BorderSizePixel = 0,
			ZIndex = 1,
		}, rays)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) }),
		}, r)
	end
	local bokeh = {}
	for i = 1, 22 do
		local big = i <= 6
		local size = if big then math.random(50, 110) else math.random(4, 9)
		local b = new("Frame", {
			Name = "Bokeh",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), math.random() * 0.8),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if big then Color3.fromRGB(255, 230, 190) else Color3.fromRGB(255, 196, 92),
			BackgroundTransparency = if big then 0.88 else 0.35,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, canvas)
		corner(b, 999)
		table.insert(bokeh, { frame = b, speed = 0.004 + math.random() * 0.006, sway = math.random() * 6.28, x = b.Position.X.Scale })
	end
	ambience = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for _, p in bokeh do
			local y = p.frame.Position.Y.Scale - p.speed * dt * 4
			if y < -0.1 then
				y = 1.05
			end
			p.frame.Position = UDim2.fromScale(p.x + math.sin(t * 0.4 + p.sway) * 0.008, y)
		end
	end)

	-- the groups: centre (design 1280 x 720) and the three screen corners
	local mid = designGroup(canvas, "Center", Vector2.new(0.5, 0.5), DESIGN, 5)
	center = mid
	local topLeft = designGroup(canvas, "TopLeft", Vector2.new(0, 0), Vector2.new(200, 70), 5)
	local topRight = designGroup(canvas, "TopRight", Vector2.new(1, 0), Vector2.new(220, 90), 5)
	local bottomLeft = designGroup(canvas, "BottomLeft", Vector2.new(0, 1), Vector2.new(340, 112), 5)
	local cardGroup = designGroup(canvas, "Card", Vector2.new(1, 0.5), Vector2.new(348, 300), 5)
	-- the windows get their own top layer, so the tiles and the card never draw over them
	local windowsGroup = designGroup(canvas, "Windows", Vector2.new(0.5, 0.5), DESIGN, 20)
	windowLayer = windowsGroup
	local function fit()
		local view = canvas.AbsoluteSize
		local s = math.min(view.X / DESIGN.X, view.Y / DESIGN.Y)
		for _, g in { mid, topLeft, topRight, bottomLeft, cardGroup, windowsGroup } do
			(g:FindFirstChild("Fit") :: UIScale).Scale = s
		end
		-- phones: the What's New card is too small to read there (the phone design leaves it out)
		cardGroup.Visible = view.Y >= 470
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	-- version + player chip
	text(topLeft, MenuConfig.VERSION, 28, 24, 80, 18, { TextColor3 = DIM })
	local chip = box(topRight, "PlayerChip", 0, 20, 60, 46, Color3.fromRGB(43, 27, 20), { BackgroundTransparency = 0.1, AutomaticSize = Enum.AutomaticSize.X })
	corner(chip, 23)
	stroke(chip, 3, Color3.fromRGB(90, 59, 40))
	local avatar = new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.fromOffset(8, 7),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Color3.fromRGB(64, 152, 232),
		BorderSizePixel = 0,
	}, chip)
	corner(avatar, 999)
	text(chip, player.Name, 48, 12, 0, 20, { AutomaticSize = Enum.AutomaticSize.X })
	new("UIPadding", { PaddingRight = UDim.new(0, 16) }, chip)
	chip.AnchorPoint = Vector2.new(1, 0) -- hugs the top-right corner, grows to the left with a long name
	chip.Position = UDim2.new(1, -24, 0, 20)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok then
			avatar.Image = img
		end
	end)

	-- emblem, title, plaque
	local emblem = new("ImageLabel", {
		Name = "Emblem",
		Position = UDim2.fromOffset(590, 28),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
		Image = IMG.emblem,
		ZIndex = 7,
	}, mid)
	local titleShadow = text(mid, "DUSTY FINDS", 290, 158, 700, 132, {
		TextScaled = true,
		FontFace = FONT_TITLE,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
	})
	local title = text(mid, "DUSTY FINDS", 290, 146, 700, 132, {
		TextScaled = true,
		FontFace = FONT_TITLE,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
	})
	gradient(title, GOLD_TOP, GOLD_BOTTOM)
	new("UIStroke", { Color = INK, Thickness = 7 }, title)
	new("UIStroke", { Color = INK, Thickness = 7 }, titleShadow)
	local plaque = box(mid, "Plaque", 458, 296, 364, 70, Color3.new(1, 1, 1), { ZIndex = 6 })
	gradient(plaque, WOOD, WOOD_DARK)
	corner(plaque, 8)
	stroke(plaque, 5, INK)
	local plaqueRim = box(plaque, "Rim", 6, 6, 352, 58, Color3.new(1, 1, 1), { BackgroundTransparency = 1, ZIndex = 6 })
	corner(plaqueRim, 5)
	stroke(plaqueRim, 2, Color3.fromRGB(140, 96, 62))
	text(plaque, "R E S T O R E   &   S E L L", 14, 17, 336, 34, {
		TextScaled = true,
		FontFace = FONT_TITLE,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
	})

	-- PLAY: a chunky 3D gold pill (lip underneath), a ▶ mark, cream text
	local playWrap = box(mid, "PlayWrap", 450, 420, 380, 105, Color3.new(1, 1, 1), { BackgroundTransparency = 1, ZIndex = 8 })
	local lip = box(playWrap, "Lip", 0, 10, 380, 95, LIP, { ZIndex = 8 })
	corner(lip, 30)
	stroke(lip, 5, INK)
	local play = new("TextButton", {
		Name = "Play",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(380, 92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 9,
	}, playWrap)
	gradient(play, GOLD_TOP, GOLD_BOTTOM)
	corner(play, 30)
	stroke(play, 5, INK)
	local playGlow = glowRing(play, 12)
	local shine = box(play, "Shine", 18, 8, 344, 28, Color3.new(1, 1, 1), { BackgroundTransparency = 0.55, ZIndex = 10 })
	corner(shine, 14)
	local playText = text(play, "PLAY", 150, 8, 200, 76, { FontFace = FONT_TITLE, TextColor3 = CREAM, TextScaled = true, ZIndex = 11 })
	new("UIStroke", { Color = INK, Thickness = 5 }, playText)
	local arrow = text(play, "▶", 100, 24, 44, 40, { TextColor3 = CREAM, ZIndex = 11 })
	new("UIStroke", { Color = INK, Thickness = 4 }, arrow)
	hoverable(play, -1.5, playGlow)
	-- pressed: the face sinks onto its lip
	play.MouseButton1Down:Connect(function()
		tween(play, 0.07, { Position = UDim2.fromOffset(0, 8) })
	end)
	play.MouseButton1Up:Connect(function()
		tween(play, 0.12, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	end)
	play.MouseLeave:Connect(function()
		tween(play, 0.12, { Position = UDim2.fromOffset(0, 0) })
	end)

	-- Continue chip: coin, CONTINUE, level, cash
	local cont = box(mid, "Continue", 500, 538, 280, 44, Color3.fromRGB(43, 27, 20), { BackgroundTransparency = 0.08, ZIndex = 8 })
	corner(cont, 22)
	stroke(cont, 3, Color3.fromRGB(90, 59, 40))
	new("ImageLabel", { Position = UDim2.fromOffset(14, 9), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Image = UiSkin.Art("Cash"), ZIndex = 9 }, cont)
	text(cont, "CONTINUE", 52, 14, 80, 14, { TextColor3 = GOLD_BOTTOM, ZIndex = 9 })
	box(cont, "Divider", 128, 10, 2, 24, Color3.fromRGB(110, 80, 60), { ZIndex = 9 })
	continueLevel = text(cont, "", 140, 9, 60, 26, { FontFace = FONT_TITLE, ZIndex = 9 })
	continueCash = text(cont, "", 192, 9, 90, 26, { FontFace = FONT_TITLE, TextColor3 = GOLD_BOTTOM, ZIndex = 9 })
	updateContinue()

	-- Settings / Updates / Credits tiles (bottom-left)
	local tiles = {
		{ name = "Settings", label = "Settings", icon = UiSkin.Art("Settings"), top = Color3.fromRGB(176, 198, 212), bottom = Color3.fromRGB(110, 138, 156), tilt = -3 },
		{ name = "Updates", label = "Updates", icon = IMG.news, top = Color3.fromRGB(116, 190, 245), bottom = Color3.fromRGB(46, 128, 214), tilt = -2 },
		{ name = "Credits", label = "Credits", icon = IMG.heart, top = Color3.fromRGB(255, 160, 184), bottom = Color3.fromRGB(226, 92, 130), tilt = 3 },
	}
	local buttons = { Play = play }
	for i, t in tiles do
		local b = new("ImageButton", {
			Name = t.name,
			Position = UDim2.fromOffset(36 + (i - 1) * 100, 8),
			Size = UDim2.fromOffset(86, 86),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Image = "",
			AutoButtonColor = false,
			ZIndex = 6,
		}, bottomLeft)
		gradient(b, t.top, t.bottom)
		corner(b, 16)
		stroke(b, 4, INK)
		local g = glowRing(b, 8)
		local inner = box(b, "Inner", 5, 5, 76, 76, Color3.new(1, 1, 1), { BackgroundTransparency = 1, ZIndex = 6 })
		corner(inner, 12)
		stroke(inner, 2, Color3.new(1, 1, 1), 0.45)
		new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(17, 8), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1, Image = t.icon, ZIndex = 7 }, b)
		local l = text(b, t.label, 0, 60, 86, 19, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.new(1, 1, 1), ZIndex = 8 })
		new("UIStroke", { Color = INK, Thickness = 2.5 }, l)
		hoverable(b, t.tilt, g)
		buttons[t.name] = b
	end

	-- What's New card (right): tilted paper with tape, NEW badge, newest update, "See all updates"
	local newest = MenuConfig.UPDATES[1]
	local card = new("TextButton", {
		Name = "WhatsNew",
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.fromOffset(300, 240),
		Rotation = 0, -- was 3: Roblox draws rotated text without proper smoothing, so the card read as blurry (Ace, 2026-11-25)
		BackgroundColor3 = PAPER,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 6,
	}, cardGroup)
	corner(card, 6)
	stroke(card, 4, INK)
	local cardGlow = glowRing(card, 8)
	box(card, "Tape", 104, -12, 100, 24, Color3.fromRGB(232, 210, 160), { BackgroundTransparency = 0.25, Rotation = -2, ZIndex = 7 })
	text(card, "WHAT'S NEW", 22, 26, 200, 26, { FontFace = FONT_TITLE, TextColor3 = INK, ZIndex = 7 })
	local nb = box(card, "New", 232, 28, 50, 26, RED, { ZIndex = 7 })
	corner(nb, 6)
	stroke(nb, 2.5, INK)
	text(nb, "NEW", 0, 4, 50, 17, { FontFace = FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 })
	if newest then
		text(card, newest.title, 22, 62, 260, 24, { FontFace = FONT_TITLE, TextColor3 = PLUM, ZIndex = 7 })
		text(card, newest.date, 22, 88, 120, 14, { TextColor3 = Color3.fromRGB(140, 110, 90), ZIndex = 7 })
		for k, line in newest.lines do
			if k <= 3 then
				text(card, "• " .. line, 22, 106 + (k - 1) * 34, 262, 17, { TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = INK, ZIndex = 7 })
			end
		end
	end
	for d = 0, 2 do
		local dot = box(card, "Dot", 22 + d * 14, 214, 8, 8, if d == 0 then PLUM else Color3.fromRGB(200, 185, 165), { ZIndex = 7 })
		corner(dot, 999)
	end
	text(card, "See all updates ›", 168, 208, 120, 16, { TextColor3 = PLUM, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7 })
	hoverable(card, 0, cardGlow)
	buttons.Card = card

	-- the windows sit in the centre group
	buildUpdates()
	buildCredits()

	gui = screen
	fit()
	return buttons, { emblem = emblem, title = title, titleShadow = titleShadow, plaque = plaque, playWrap = playWrap, cont = cont, tiles = bottomLeft, card = card }
end

-- ===== show / play =====

-- The start poses are set the moment the menu is built (prepareEntrance), not when the entrance plays: the menu sits
-- under the fading loading screen, and setting them late made the title and tiles visibly jump (found in the sweep).
local homes: { [GuiObject]: UDim2 } = {}

local function prepareEntrance(parts: { [string]: GuiObject })
	for _, key in { "title", "titleShadow" } do
		local o = parts[key]
		homes[o] = o.Position
		o.Position = o.Position - UDim2.fromOffset(0, 220)
	end
	for _, key in { "emblem", "plaque", "playWrap", "cont" } do
		local o = parts[key]
		local s = o:FindFirstChild("Entrance") or new("UIScale", { Name = "Entrance" }, o)
		s.Scale = 0
	end
	homes[parts.tiles] = parts.tiles.Position
	parts.tiles.Position = parts.tiles.Position + UDim2.fromOffset(0, 160)
	parts.card.Rotation = 18
end

local function entrance(parts: { [string]: GuiObject })
	-- the title drops in, the emblem pops, PLAY bounces up, the tiles rise, the card swings in
	for _, key in { "title", "titleShadow" } do
		local o = parts[key]
		tween(o, 0.75, { Position = homes[o] }, Enum.EasingStyle.Bounce)
	end
	local pops = { { "emblem", 0.35 }, { "plaque", 0.25 }, { "playWrap", 0.45 }, { "cont", 0.55 } }
	for _, p in pops do
		local s = (parts[p[1]] :: GuiObject):FindFirstChild("Entrance") :: UIScale
		task.delay(p[2], function()
			tween(s, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	local tiles = parts.tiles
	task.delay(0.5, function()
		tween(tiles, 0.45, { Position = homes[tiles] }, Enum.EasingStyle.Back)
	end)
	local card = parts.card
	task.delay(0.6, function()
		tween(card, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	end)
	task.delay(0.3, sfx, "snap")
end

local function play()
	if not open then
		return
	end
	open = false
	closeWindows()
	sfx("reveal") -- a rising whoosh for PLAY; was "levelUp" (a church-bell chime, Ace 2026-11-25)
	local canvas = root :: Frame
	for _, o in canvas:GetDescendants() do
		if o:IsA("TextLabel") or o:IsA("TextButton") then
			tween(o, 0.45, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
			tween(o, 0.45, { ImageTransparency = 1, BackgroundTransparency = 1 })
		elseif o:IsA("Frame") then
			tween(o, 0.45, { BackgroundTransparency = 1 })
		elseif o:IsA("UIStroke") then
			tween(o, 0.45, { Transparency = 1 })
		end
	end
	task.spawn(function()
		endFlyover(function()
			restoreScreens()
			setControls(true)
			if ambience then
				ambience:Disconnect()
				ambience = nil
			end
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
	prepareEntrance(parts)
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
	buttons.Card.Activated:Connect(function()
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
		local loading
		for _, c in player.PlayerGui:GetChildren() do
			if c.Name == "LoadingScreen" and c:IsA("ScreenGui") then
				loading = c
			end
		end
		if loading then
			loading.AncestryChanged:Wait()
		end
		entrance(parts)
	end)
	log("ready: menu up, waiting for PLAY")
end

return MainMenuController
