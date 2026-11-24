-- CashierController.luau
-- Purpose: the cash register window. When the server opens the till (CashierUpdate "open") the camera moves behind MY
-- counter (looking at the customer) and the Register window opens: CHANGE NEEDED / CHANGE GIVEN at the top, a row of
-- money tiles ($50 $20 $10 $5 bills and a $1 coin, drawn from UI shapes: our own art, no real banknotes), and
-- Undo / Reset / Confirm. A gold bar under the totals shows the fast-bonus time. Confirm sends the amount
-- (RequestGiveChange); the server (CashierService) checks it and decides every dollar: right + fast = +25%,
-- right = +10%, right after a mistake = no bonus, 2 mistakes = the customer pays 10% less and leaves angry.
-- Owner: Dev 3 (Sean) since 2026-11-23; first version (till screen) by Dev 1 (Ace).
-- Depends on: Remotes (CashierUpdate, RequestGiveChange, RequestCloseCashier), Config.UiSkin (fonts, colours),
-- Config.Economy (Cashier*), SoundController (optional), ClientState (settings.reduceEffects), my plot's Counter and
-- CustomerPath.CounterSpot (camera), PlayerScripts.PlayerModule if present (movement off while serving).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local CashierController = {}
local DEBUG = true
local WALK_AWAY_STUDS = 20
local C = Skin.COLORS
local CAMERA_TWEEN = 0.45
local WINDOW_SIZE = Vector2.new(780, 440) -- px at UIScale 1; shrunk to fit phones

-- Register palette (presentation only): warm dark wood, so it reads as a shop till rather than a menu.
local WOOD = Color3.fromRGB(46, 34, 26)
local WOOD_EDGE = Color3.fromRGB(92, 68, 48)
local SLOT = Color3.fromRGB(28, 21, 16)
local TILE = Color3.fromRGB(58, 44, 33)
local TILE_EDGE = Color3.fromRGB(110, 84, 60)
local RED = Color3.fromRGB(214, 74, 62)
local GOLD = Color3.fromRGB(240, 184, 64)
local GREEN = Color3.fromRGB(76, 168, 92)
local GREEN_DIM = Color3.fromRGB(46, 84, 54)
local BAD = Color3.fromRGB(240, 96, 80)

-- Money art (presentation only; the VALUES come from the server, data.bills = Economy.CashierBills).
-- A value listed in COINS is drawn as a coin stack, everything else as a bill.
local MONEY_COLORS = {
	[50] = Color3.fromRGB(226, 104, 92),
	[20] = Color3.fromRGB(162, 118, 214),
	[10] = Color3.fromRGB(232, 178, 80),
	[5] = Color3.fromRGB(96, 156, 220),
	[1] = Color3.fromRGB(214, 218, 226),
}
local COINS = { [1] = true }
local FALLBACK_COLOR = Color3.fromRGB(110, 180, 120)

local function log(...)
	if DEBUG then
		print("[CashierController]", ...)
	end
end

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui
local window: Frame
local ui: { [string]: any } = {}
local tiles: { [number]: { button: TextButton, badge: TextLabel, scale: UIScale } } = {}
local current: { [string]: any }? = nil -- the server's till data while open
local openedAt = 0 -- os.clock() when "open" arrived (the on-screen timer; the server times it for real)
local picked: { number } = {} -- values given, oldest first (Undo removes the last)
local savedCameraType: Enum.CameraType? = nil
local hiddenGuis: { ScreenGui } = {}
local connections: { RBXScriptConnection } = {}
local closing = false
local resultShown = false

-- ===== Small helpers =====

local function sound(name: string)
	local s = others.SoundController
	if s then
		s.Play(name)
	end
end

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, px: number?)
	make("UICorner", { CornerRadius = UDim.new(0, px or 6) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	make("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, TextScaled = true, FontFace = Skin.FONT_NUMBER, TextColor3 = C.text, Text = "" }
	for k, v in props do
		base[k] = v
	end
	return make("TextLabel", base, parent)
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function given(): number
	local sum = 0
	for _, value in picked do
		sum += value
	end
	return sum
end

local function needed(): number
	return current and ((current.paid or 0) - (current.due or 0)) or 0
end

-- ===== Money art =====

-- A bill: coloured note with an inner border, a big value on the left, an emblem in the middle and the shop name.
local function drawBill(parent: Instance, value: number, color: Color3)
	local note = make("Frame", {
		Name = "Bill", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.86, 0.56),
		BackgroundColor3 = color, BorderSizePixel = 0,
	}, parent)
	corner(note, 5)
	stroke(note, darker(color, 0.45), 2)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(lighter(color, 0.25), darker(color, 0.12)) }, note)
	local inner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1,
	}, note)
	corner(inner, 3)
	stroke(inner, Color3.new(1, 1, 1), 1.5, 0.45)
	text(note, { -- big value, left
		Position = UDim2.fromScale(0.06, 0.12), Size = UDim2.fromScale(0.3, 0.76), Text = tostring(value),
		TextColor3 = darker(color, 0.55), TextXAlignment = Enum.TextXAlignment.Left,
	})
	local emblem = make("Frame", { -- round emblem (our own: a star seal)
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.5), Size = UDim2.fromScale(0.36, 0.72),
		BackgroundColor3 = lighter(color, 0.5), BorderSizePixel = 0,
	}, note)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, emblem)
	corner(emblem, 999)
	stroke(emblem, darker(color, 0.35), 1.5)
	text(emblem, { Size = UDim2.fromScale(1, 1), Text = "★", TextColor3 = darker(color, 0.4) })
	text(note, { -- shop name, tiny
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0.1, 0), Size = UDim2.fromScale(0.42, 0.16), Text = "DUSTY FINDS",
		FontFace = Skin.FONT_TEXT, TextColor3 = darker(color, 0.5), TextXAlignment = Enum.TextXAlignment.Right,
	})
	text(note, { -- small value, bottom right
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 0.9, 0), Size = UDim2.fromScale(0.22, 0.24), Text = tostring(value),
		TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right,
	})
end

-- A coin: a short stack of discs with a rim and the value on top.
local function drawCoin(parent: Instance, value: number, color: Color3)
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.62, 0.66), BackgroundTransparency = 1,
	}, parent)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, holder)
	for i = 3, 1, -1 do -- bottom discs first, so the top coin is drawn last
		local disc = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5 + (i - 1) * 0.07), Size = UDim2.fromScale(0.9, 0.9),
			BackgroundColor3 = darker(color, 0.15 + i * 0.08), BorderSizePixel = 0, ZIndex = 5 - i,
		}, holder)
		corner(disc, 999)
		stroke(disc, darker(color, 0.5), 2)
	end
	local top = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 6,
	}, holder)
	corner(top, 999)
	stroke(top, darker(color, 0.45), 2.5)
	make("UIGradient", { Rotation = 45, Color = ColorSequence.new(lighter(color, 0.45), darker(color, 0.15)) }, top)
	local rim = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.78),
		BackgroundTransparency = 1, ZIndex = 7,
	}, top)
	corner(rim, 999)
	stroke(rim, darker(color, 0.3), 1.5, 0.2)
	text(top, { Position = UDim2.fromScale(0.15, 0.14), Size = UDim2.fromScale(0.7, 0.52), Text = tostring(value), TextColor3 = darker(color, 0.6), ZIndex = 8 })
	text(top, { Position = UDim2.fromScale(0.2, 0.62), Size = UDim2.fromScale(0.6, 0.16), Text = "DOLLAR", FontFace = Skin.FONT_TEXT, TextColor3 = darker(color, 0.5), ZIndex = 8 })
end

-- ===== Window =====

local function totalBox(name: string, title: string, x: number): TextLabel
	local box = make("Frame", {
		Name = name, Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(0.5, -8, 1, 0), BackgroundColor3 = SLOT, BorderSizePixel = 0,
	}, ui.Totals)
	corner(box, 6)
	stroke(box, Color3.new(0, 0, 0), 2, 0.3)
	text(box, { Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.22), Text = title, FontFace = Skin.FONT_TEXT, TextColor3 = C.textDim })
	return text(box, { Name = "Amount", Position = UDim2.fromScale(0, 0.34), Size = UDim2.fromScale(1, 0.58), TextColor3 = C.text })
end

local function actionButton(name: string, label: string, color: Color3, x: number, w: number): TextButton
	local b = make("TextButton", {
		Name = name, Position = UDim2.new(x, 6, 0, 0), Size = UDim2.new(w, -12, 1, 0), BackgroundColor3 = color, AutoButtonColor = true,
		FontFace = Skin.FONT_TITLE, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = label,
	}, ui.Actions)
	corner(b, 6)
	stroke(b, darker(color, 0.45), 2)
	make("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0) }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)) }, b)
	return b
end

local function buildWindow()
	gui = make("ScreenGui", { Name = "Cashier", ResetOnSpawn = false, DisplayOrder = 6, IgnoreGuiInset = true, Enabled = false })
	window = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y), BackgroundColor3 = WOOD, BorderSizePixel = 0,
	}, gui)
	corner(window, 10)
	stroke(window, WOOD_EDGE, 3)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(lighter(WOOD, 0.08), darker(WOOD, 0.2)) }, window)
	make("UIScale", { Name = "FitScale" }, window)

	-- title bar
	text(window, { Name = "Title", Position = UDim2.fromOffset(22, 12), Size = UDim2.fromOffset(260, 34), Text = "Register", FontFace = Skin.FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Left })
	ui.Item = text(window, { Name = "Item", Position = UDim2.fromOffset(200, 18), Size = UDim2.new(1, -280, 0, 24), FontFace = Skin.FONT_TEXT, TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Right })
	ui.Close = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(42, 40),
		BackgroundColor3 = RED, FontFace = Skin.FONT_TITLE, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "X", -- the skin's font has no ✕ glyph
	}, window)
	corner(ui.Close, 8)
	stroke(ui.Close, darker(RED, 0.4), 2)
	make("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }, ui.Close)

	-- CHANGE NEEDED / CHANGE GIVEN
	ui.Totals = make("Frame", { Name = "Totals", Position = UDim2.fromOffset(20, 60), Size = UDim2.new(1, -40, 0, 104), BackgroundTransparency = 1 }, window)
	ui.Needed = totalBox("Needed", "CHANGE NEEDED", 0)
	ui.Needed.TextColor3 = GOLD
	ui.Given = totalBox("Given", "CHANGE GIVEN", 0.5)
	ui.Totals.Given.Position = UDim2.new(0.5, 8, 0, 0)

	-- fast-bonus timer + status line
	local bar = make("Frame", { Name = "FastBar", Position = UDim2.fromOffset(20, 174), Size = UDim2.new(0.34, 0, 0, 10), BackgroundColor3 = SLOT, BorderSizePixel = 0 }, window)
	corner(bar, 5)
	ui.FastFill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.money, BorderSizePixel = 0 }, bar)
	corner(ui.FastFill, 5)
	ui.Fast = text(window, { Name = "Fast", Position = UDim2.new(0.34, 32, 0, 168), Size = UDim2.new(0.3, 0, 0, 22), FontFace = Skin.FONT_TEXT, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Left })
	ui.Status = text(window, { Name = "Status", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 168), Size = UDim2.new(0.34, 0, 0, 22), FontFace = Skin.FONT_TEXT, TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Right })

	-- money tiles (built per till from the server's bill list)
	ui.Money = make("Frame", { Name = "Money", Position = UDim2.fromOffset(20, 198), Size = UDim2.new(1, -40, 0, 160), BackgroundTransparency = 1 }, window)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, ui.Money)

	-- Undo / Reset / Confirm
	ui.Actions = make("Frame", { Name = "Actions", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0.84, 0, 0, 56), BackgroundTransparency = 1 }, window)
	ui.Undo = actionButton("Undo", "Undo", GOLD, 0, 0.3)
	ui.Reset = actionButton("Reset", "Reset", RED, 0.3, 0.3)
	ui.Confirm = actionButton("Confirm", "Confirm", GREEN_DIM, 0.6, 0.4)

	-- result banner (shown over the money for a moment when the sale is done)
	ui.Result = make("TextLabel", {
		Name = "Result", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(WINDOW_SIZE.X / 2, 278), Size = UDim2.fromOffset(520, 76),
		BackgroundColor3 = SLOT, BackgroundTransparency = 0.05, FontFace = Skin.FONT_TITLE, TextScaled = true, TextColor3 = C.good, Text = "",
		Visible = false, ZIndex = 20,
	}, window)
	corner(ui.Result, 10)
	stroke(ui.Result, C.good, 3)
	make("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }, ui.Result)

	gui.Parent = player:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	local function fit()
		local vp = camera.ViewportSize
		window.FitScale.Scale = math.min(1, (vp.X - 24) / WINDOW_SIZE.X, (vp.Y - 16) / WINDOW_SIZE.Y)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end

local function refresh()
	if not current then
		return
	end
	local need, have = needed(), given()
	ui.Needed.Text = string.format("$%d", need)
	ui.Given.Text = string.format("$%d", have)
	ui.Item.Text = string.format("%s  •  Total $%d  •  Paid $%d", tostring(current.item or ""), current.due or 0, current.paid or 0)
	local exact = have == need
	ui.Given.TextColor3 = if exact then C.good elseif have > need then BAD else C.text
	if (current.attempts or 0) == 0 then
		ui.Status.Text = if exact then "✓ Exact! Confirm it" elseif have > need then string.format("Too much by $%d", have - need) else ""
		ui.Status.TextColor3 = if exact then C.good elseif have > need then BAD else C.textDim
	end
	-- Team decision 2026-11-23: Confirm works at ANY amount (a wrong hand-over costs the bonus); bright when exact.
	ui.Confirm.BackgroundColor3 = if exact then GREEN else GREEN_DIM
	ui.Confirm.TextColor3 = if have > 0 then Color3.new(1, 1, 1) else Color3.fromRGB(150, 170, 150)
	for value, tile in tiles do
		local n = 0
		for _, v in picked do
			if v == value then
				n += 1
			end
		end
		tile.badge.Text = "×" .. n
		tile.badge.Visible = n > 0
	end
end

local function press(tile: { [string]: any })
	if reduceEffects() then
		return
	end
	tile.scale.Scale = 0.92
	TweenService:Create(tile.scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function buildTiles(values: { number })
	for _, child in ui.Money:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	tiles = {}
	-- biggest first (like a till drawer); bills before coins
	local ordered = table.clone(values)
	table.sort(ordered, function(a, b)
		return a > b
	end)
	local width = 1 / #ordered
	for i, value in ordered do
		local button = make("TextButton", {
			Name = "Money" .. value, LayoutOrder = i, Size = UDim2.new(width, -10, 1, 0), BackgroundColor3 = TILE,
			AutoButtonColor = true, Text = "",
		}, ui.Money)
		corner(button, 6)
		stroke(button, TILE_EDGE, 2, 0.2)
		local scale = make("UIScale", {}, button)
		local color = MONEY_COLORS[value] or FALLBACK_COLOR
		if COINS[value] then
			drawCoin(button, value, color)
		else
			drawBill(button, value, color)
		end
		text(button, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromScale(0.8, 0.17), Text = "$" .. value })
		local badge = text(button, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(40, 26), BackgroundTransparency = 0,
			BackgroundColor3 = GOLD, TextColor3 = Color3.fromRGB(40, 28, 12), Visible = false, ZIndex = 10,
		})
		corner(badge, 13)
		local tile = { button = button, badge = badge, scale = scale }
		tiles[value] = tile
		button.Activated:Connect(function()
			if current and #picked < 30 then -- the change is always under $100: 30 coins/bills is plenty
				table.insert(picked, value)
				press(tile)
				sound("pick")
				refresh()
			end
		end)
	end
end

local function shake()
	if reduceEffects() then
		return
	end
	local start = window.Position
	for i = 1, 6 do
		window.Position = start + UDim2.fromOffset(if i % 2 == 0 then 10 else -10, 0)
		task.wait(0.04)
	end
	window.Position = start
end

-- ===== Camera, movement, other screens =====

-- Movement off while serving. Never yields: this game has no default PlayerModule, so if it is missing we stop the
-- character through its own Humanoid instead (local, our own character only).
local frozen: { humanoid: Humanoid, walkSpeed: number, jumpPower: number, jumpHeight: number }? = nil
local function setControls(enabled: boolean)
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module then
		local ok = pcall(function()
			local controls = require(module):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
		if ok then
			return
		end
	end
	if enabled then
		if frozen and frozen.humanoid.Parent then
			frozen.humanoid.WalkSpeed = frozen.walkSpeed
			frozen.humanoid.JumpPower = frozen.jumpPower
			frozen.humanoid.JumpHeight = frozen.jumpHeight
		end
		frozen = nil
	else
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and frozen == nil then
			frozen = { humanoid = humanoid, walkSpeed = humanoid.WalkSpeed, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end
end

-- Our own character stands where the camera is: hide it for us only while serving (others still see it).
local function hideCharacter(hide: boolean)
	local character = player.Character
	if character == nil then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = if hide then 1 else 0
		end
	end
end

local function hideOtherGuis(hide: boolean)
	if hide then
		local playerGui = player:FindFirstChild("PlayerGui")
		for _, name in { "HUD", "Tutorial" } do
			local other = playerGui and playerGui:FindFirstChild(name)
			if other and other:IsA("ScreenGui") and other.Enabled then
				other.Enabled = false
				table.insert(hiddenGuis, other)
			end
		end
	else
		for _, other in hiddenGuis do
			other.Enabled = true
		end
		hiddenGuis = {}
	end
end

local function myPlot(): Instance?
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in (plots and plots:GetChildren() or {}) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function myCounter(): BasePart?
	local plot = myPlot()
	local counter = plot and plot:FindFirstChild("Counter")
	return if counter and counter:IsA("BasePart") then counter else nil
end

-- Cashier's eyes: behind the counter, looking across it at the customer.
local function cashierCamera(): CFrame?
	local plot = myPlot()
	local counter = myCounter()
	if not (plot and counter) then
		return nil
	end
	local path = plot:FindFirstChild("CustomerPath")
	local spot = path and path:FindFirstChild("CounterSpot")
	local toCustomer = counter.CFrame.LookVector
	if spot and spot:IsA("BasePart") then
		local flat = Vector3.new(spot.Position.X - counter.Position.X, 0, spot.Position.Z - counter.Position.Z)
		if flat.Magnitude > 0.1 then
			toCustomer = flat.Unit
		end
	end
	local top = counter.Position + Vector3.new(0, counter.Size.Y / 2, 0)
	local eye = top - toCustomer * 4 + Vector3.new(0, 3.2, 0)
	return CFrame.lookAt(eye, top + toCustomer * 4 + Vector3.new(0, 1.6, 0))
end

-- ===== Open / close =====

local function close(tellServer: boolean)
	if closing then
		return
	end
	closing = true
	if current and tellServer then
		Remotes.RequestCloseCashier:FireServer()
	end
	current = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	picked = {}
	gui.Enabled = false
	ui.Result.Visible = false
	hideOtherGuis(false)
	hideCharacter(false)
	setControls(true)
	if savedCameraType then
		workspace.CurrentCamera.CameraType = savedCameraType
		savedCameraType = nil
	end
	closing = false
	log("till closed")
end

local function open(data: { [string]: any })
	if current then
		close(false) -- a fresh "open" replaces the old one
	end
	current = data
	openedAt = os.clock()
	picked = {}
	resultShown = false
	ui.Result.Visible = false
	ui.Status.Text = ""
	buildTiles(if type(data.bills) == "table" then data.bills else { 1, 5, 10, 20, 50 })
	gui.Enabled = true
	refresh()
	if not reduceEffects() then
		window.FitScale.Scale *= 0.9
		local target = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / WINDOW_SIZE.X, (workspace.CurrentCamera.ViewportSize.Y - 16) / WINDOW_SIZE.Y)
		TweenService:Create(window.FitScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end

	local view = cashierCamera()
	if view then
		local camera = workspace.CurrentCamera
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		if reduceEffects() then
			camera.CFrame = view
		else
			TweenService:Create(camera, TweenInfo.new(CAMERA_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = view }):Play()
		end
	end
	setControls(false)
	hideOtherGuis(true)
	hideCharacter(true)

	table.insert(connections, player.CharacterAdded:Connect(function()
		close(true)
	end))
	local fastSeconds = tonumber(data.fastSeconds) or Economy.CashierFastSeconds
	local fastPercent = tonumber(data.fastPercent) or math.floor(Economy.CashierFastBonusFraction * 100 + 0.5)
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if not current then
			return
		end
		local left = fastSeconds - (os.clock() - openedAt)
		local stillFast = left > 0 and (current.attempts or 0) == 0
		ui.FastFill.Size = UDim2.fromScale(if stillFast then math.clamp(left / fastSeconds, 0, 1) else 0, 1)
		ui.Fast.Text = if stillFast then string.format("⚡ +%d%% if right in %ds", fastPercent, math.ceil(left)) else ""
	end))
	log("till open:", data.item, "change", needed())
end

local function showResult(textValue: string, color: Color3)
	ui.Result.Text = textValue
	ui.Result.TextColor3 = color
	ui.Result.UIStroke.Color = color
	ui.Result.Visible = true
	resultShown = true
end

local function onUpdate(data: { [string]: any })
	if type(data) ~= "table" then
		return
	end
	if data.state == "open" then
		open(data)
	elseif data.state == "wrong" and current then
		current.attempts = data.attempts
		local left = math.max(0, (tonumber(data.maxMistakes) or Economy.CashierMaxMistakes) - (tonumber(data.attempts) or 1))
		ui.Status.Text = string.format("Not right! %d more mistake%s = angry", left, if left == 1 then "" else "s")
		ui.Status.TextColor3 = BAD
		sound("wrong")
		task.spawn(shake)
	elseif data.state == "done" then
		local percentText = if type(data.bonusPercent) == "number" then string.format("%+d%%", data.bonusPercent) else ""
		local results = {
			Delighted = { "⚡ Super fast!  " .. percentText, C.money },
			Happy = { "✓ Thank you!  " .. percentText, C.good },
			Upset = { "😐 Paid, no bonus", C.textDim },
			Angry = { "😡 Angry: paid " .. percentText, BAD },
		}
		local result = results[data.mood] or { "Thank you!", C.good }
		showResult(result[1], result[2])
		sound(if data.mood == "Angry" then "wrong" else "coins")
		task.delay(1.3, function()
			if current and resultShown then
				close(false)
			end
		end)
	elseif data.state == "closed" then
		close(false)
	end
end

function CashierController.Init(otherControllers)
	others = otherControllers
end

function CashierController.Start()
	buildWindow()
	ui.Undo.Activated:Connect(function()
		if current and #picked > 0 then
			table.remove(picked)
			refresh()
		end
	end)
	ui.Reset.Activated:Connect(function()
		if current then
			picked = {}
			refresh()
		end
	end)
	ui.Confirm.Activated:Connect(function()
		if current and #picked > 0 and not resultShown then
			Remotes.RequestGiveChange:FireServer(given())
		end
	end)
	ui.Close.Activated:Connect(function()
		close(true)
	end)
	Remotes.CashierUpdate.OnClientEvent:Connect(onUpdate)
	-- walking (or being teleported) away from the counter closes the till; movement is off while serving, so this is a safety net
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.5 or not current then
			return
		end
		since = 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local counter = myCounter()
		if root and counter and (root.Position - counter.Position).Magnitude > WALK_AWAY_STUDS then
			close(true)
		end
	end)
	log("ready")
end

return CashierController
