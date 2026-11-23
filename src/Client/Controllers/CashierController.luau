-- CashierController.luau
-- Purpose: the till screen. When the server opens the till (CashierUpdate "open") it shows, in big letters, the change
-- the player has to give (paid - total), then the player taps bills until the amount is exact and presses Give.
-- "Still need $X" / "Too much by $X" guide them; Give only lights up when the amount is exact. The server still checks
-- the amount (RequestGiveChange) and decides the money.
-- Owner: Dev 1 (Ace). Depends on: Remotes (CashierUpdate, RequestGiveChange, RequestCloseCashier), Config.UiSkin,
-- HudSkinController (optional, panel/button style), SoundController (optional), Workspace.Plots.<mine>.Counter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))

local CashierController = {}
local DEBUG = true
local WALK_AWAY_STUDS = 20
local C = Skin.COLORS
local BILL = Color3.fromRGB(86, 168, 96)
local BILL_EDGE = Color3.fromRGB(40, 92, 48)

local function log(...)
	if DEBUG then
		print("[CashierController]", ...)
	end
end

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui
local panel: Frame
local ui: { [string]: any } = {}
local picked: { number } = {}
local current: { [string]: any }? = nil

local function sound(name: string)
	local s = others.SoundController
	if s then
		s.Play(name)
	end
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
	make("UICorner", { CornerRadius = UDim.new(0, px or Skin.CORNER) }, parent)
end

local function label(name: string, parent: Instance, pos: UDim2, size: UDim2, font: Font, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local l = make("TextLabel", {
		Name = name, BackgroundTransparency = 1, Position = pos, Size = size, FontFace = font, TextColor3 = color,
		TextScaled = true, TextXAlignment = align or Enum.TextXAlignment.Center, Text = "",
	}, parent)
	ui[name] = l
	return l
end

local function given(): number
	local sum = 0
	for _, v in picked do
		sum += v
	end
	return sum
end

local function needed(): number
	return current and ((current.paid or 0) - (current.due or 0)) or 0
end

local function refresh()
	if not current then
		return
	end
	local need, have = needed(), given()
	ui.Big.Text = string.format("$%d", need)
	ui.Sub.Text = string.format("Total $%d  •  Customer paid $%d", current.due or 0, current.paid or 0)
	ui.Item.Text = string.upper(tostring(current.item or ""))
	ui.Given.Text = string.format("GIVEN  $%d", have)
	local fill = if need > 0 then math.clamp(have / need, 0, 1) else 1
	TweenService:Create(ui.Fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fill, 1) }):Play()
	local exact = have == need
	if exact then
		ui.Status.Text = "✓ EXACT — GIVE IT!"
		ui.Status.TextColor3 = C.good
		ui.Fill.BackgroundColor3 = C.good
	elseif have < need then
		ui.Status.Text = string.format("STILL NEED  $%d", need - have)
		ui.Status.TextColor3 = C.accent
		ui.Fill.BackgroundColor3 = C.accent
	else
		ui.Status.Text = string.format("TOO MUCH BY  $%d", have - need)
		ui.Status.TextColor3 = Color3.fromRGB(240, 96, 80)
		ui.Fill.BackgroundColor3 = Color3.fromRGB(240, 96, 80)
	end
	local give = ui.Give :: TextButton
	give.Active = exact
	give.AutoButtonColor = exact
	give.BackgroundColor3 = if exact then C.good else C.panelTop
	give.TextColor3 = if exact then Color3.new(1, 1, 1) else C.textDim
	-- the tray: one chip per bill picked, newest last
	for _, c in ui.Tray:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i, v in picked do
		local chip = make("TextLabel", {
			Name = "Chip", LayoutOrder = i, Size = UDim2.fromOffset(38, 24), BackgroundColor3 = BILL, FontFace = Skin.FONT_NUMBER,
			Text = "$" .. v, TextColor3 = Color3.new(1, 1, 1), TextScaled = true,
		}, ui.Tray)
		corner(chip, 3)
	end
end

local function close(tellServer: boolean)
	if current and tellServer then
		Remotes.RequestCloseCashier:FireServer()
	end
	current = nil
	picked = {}
	gui.Enabled = false
end

local function shake()
	local start = panel.Position
	for i = 1, 6 do
		panel.Position = start + UDim2.fromOffset(if i % 2 == 0 then 10 else -10, 0)
		task.wait(0.04)
	end
	panel.Position = start
end

local function buildBills(bills: { number })
	for _, child in ui.Bills:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, bill in bills do
		local b = make("TextButton", {
			Name = "Bill" .. bill, LayoutOrder = i, Size = UDim2.new(1 / #bills, -6, 1, 0), BackgroundColor3 = BILL,
			FontFace = Skin.FONT_NUMBER, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "$" .. bill, AutoButtonColor = true,
		}, ui.Bills)
		corner(b, 5)
		make("UIStroke", { Color = BILL_EDGE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0) }, b)
		b.Activated:Connect(function()
			if current then
				table.insert(picked, bill)
				sound("pick")
				refresh()
			end
		end)
	end
end

local function build()
	local skin = others.HudSkinController
	gui = make("ScreenGui", { Name = "Cashier", ResetOnSpawn = false, DisplayOrder = 6, IgnoreGuiInset = true, Enabled = false })
	panel = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(520, 330),
		BackgroundColor3 = C.panelBottom,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(320, 260), MaxSize = Vector2.new(560, 360) }, panel)
	make("UIScale", { Name = "FitScale" }, panel)
	if skin then
		skin.Panel(panel, true)
	else
		corner(panel)
	end
	-- header
	label("Title", panel, UDim2.fromOffset(18, 10), UDim2.new(0.5, 0, 0, 26), Skin.FONT_TITLE, C.accent, Enum.TextXAlignment.Left).Text = "CASHIER"
	label("Item", panel, UDim2.new(0.35, 0, 0, 14), UDim2.new(0.65, -64, 0, 20), Skin.FONT_TEXT, C.textDim, Enum.TextXAlignment.Right)
	-- the one thing that matters: how much change to give
	label("Ask", panel, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 0, 20), Skin.FONT_TEXT, C.textDim).Text = "GIVE THE CUSTOMER THIS CHANGE"
	label("Big", panel, UDim2.fromOffset(0, 64), UDim2.new(1, 0, 0, 62), Skin.FONT_NUMBER, C.money)
	label("Sub", panel, UDim2.fromOffset(0, 126), UDim2.new(1, 0, 0, 18), Skin.FONT_TEXT, C.textDim)
	-- progress: given vs needed
	local bar = make("Frame", { Name = "Bar", Position = UDim2.new(0, 18, 0, 156), Size = UDim2.new(1, -36, 0, 10), BackgroundColor3 = C.panelTop, BorderSizePixel = 0 }, panel)
	corner(bar, 5)
	ui.Fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0 }, bar)
	corner(ui.Fill, 5)
	label("Given", panel, UDim2.new(0, 18, 0, 170), UDim2.new(0.4, 0, 0, 20), Skin.FONT_NUMBER, C.text, Enum.TextXAlignment.Left)
	label("Status", panel, UDim2.new(0.4, 0, 0, 170), UDim2.new(0.6, -18, 0, 20), Skin.FONT_NUMBER, C.accent, Enum.TextXAlignment.Right)
	-- tray of picked bills
	ui.Tray = make("Frame", { Name = "Tray", BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 196), Size = UDim2.new(1, -36, 0, 24), ClipsDescendants = true }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ui.Tray)
	-- bills
	ui.Bills = make("Frame", { Name = "Bills", BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 228), Size = UDim2.new(1, -36, 0, 46) }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, ui.Bills)
	-- actions
	local function action(name: string, text: string, x: number, w: number): TextButton
		local b = make("TextButton", {
			Name = name, Position = UDim2.new(x, if x == 0 then 18 else 6, 1, -50), Size = UDim2.new(w, -18, 0, 38),
			BackgroundColor3 = C.panelTop, FontFace = Skin.FONT_TITLE, TextScaled = true, TextColor3 = C.text, Text = text,
		}, panel)
		corner(b)
		make("UIStroke", { Color = C.edge, Transparency = C.edgeTransparency, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0) }, b)
		if skin then
			skin.Button(b)
		end
		return b
	end
	action("Undo", "UNDO", 0, 0.25).Activated:Connect(function()
		table.remove(picked)
		refresh()
	end)
	action("Clear", "CLEAR", 0.25, 0.25).Activated:Connect(function()
		picked = {}
		refresh()
	end)
	ui.Give = action("Give", "GIVE CHANGE", 0.5, 0.5)
	ui.Give.Activated:Connect(function()
		if current and given() == needed() then
			Remotes.RequestGiveChange:FireServer(given())
			ui.Status.Text = "…"
		end
	end)
	local x = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.panelTop, FontFace = Skin.FONT_TITLE, TextScaled = true, TextColor3 = C.text, Text = "X",
	}, panel)
	corner(x)
	x.Activated:Connect(function()
		close(true)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	-- shrink to fit small (phone) screens
	local camera = workspace.CurrentCamera
	local function fit()
		local vp = camera.ViewportSize
		panel.FitScale.Scale = math.min(1, (vp.X - 24) / 520, (vp.Y * 0.62) / 330)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end

local function myCounter(): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local counter = plot:FindFirstChild("Counter")
			return if counter and counter:IsA("BasePart") then counter else nil
		end
	end
	return nil
end

local function onUpdate(data: { [string]: any })
	if type(data) ~= "table" then
		return
	end
	if data.state == "open" then
		current = data
		picked = {}
		buildBills(data.bills or { 1, 5, 10, 20, 50 })
		gui.Enabled = true
		refresh()
		log("till open:", data.item, "change", (data.paid or 0) - (data.due or 0))
	elseif data.state == "wrong" and current then
		ui.Status.Text = "THAT'S NOT RIGHT — COUNT AGAIN"
		ui.Status.TextColor3 = Color3.fromRGB(240, 96, 80)
		sound("wrong")
		task.spawn(shake)
	elseif data.state == "done" then
		ui.Status.Text = "THANK YOU!"
		ui.Status.TextColor3 = C.good
		task.delay(0.7, function()
			if current then
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
	build()
	Remotes.CashierUpdate.OnClientEvent:Connect(onUpdate)
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
