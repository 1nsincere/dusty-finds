-- CashierController.luau
-- Purpose: the till screen. When the server opens the till (CashierUpdate "open"), show the bill and what the customer
-- paid; the player taps bills to count out the change and presses "Give change" (RequestGiveChange). Wrong change =
-- the customer complains (shake + message), try again. Closes on "done"/"closed", on the X, or when walking away.
-- Owner: Dev 1 (Ace). Depends on: Remotes (CashierUpdate, RequestGiveChange, RequestCloseCashier), UiTheme,
-- SoundController (optional), Workspace.Plots.<mine>.Counter (distance check). Shows only numbers the server sent;
-- the server checks the change and decides the money.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local CashierController = {}
local DEBUG = true
local WALK_AWAY_STUDS = 20

local function log(...)
	if DEBUG then
		print("[CashierController]", ...)
	end
end

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui
local panel: Frame
local labels: { [string]: TextLabel } = {}
local billRow: Frame
local giveButton: TextButton
local picked: { number } = {}
local current: { [string]: any }? = nil

local BILL_COLOR = Color3.fromHex("6BAF6B")

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

local function corner(parent: Instance, scale: number?)
	make("UICorner", { CornerRadius = UDim.new(scale or 0.15, 0) }, parent)
end

local function text(name: string, parent: Instance, pos: UDim2, size: UDim2, color: Color3?, align: Enum.TextXAlignment?): TextLabel
	local l = make("TextLabel", {
		Name = name, BackgroundTransparency = 1, Position = pos, Size = size, Font = Enum.Font.FredokaOne,
		TextScaled = true, TextColor3 = color or UiTheme.Ink, TextXAlignment = align or Enum.TextXAlignment.Center, Text = "",
	}, parent)
	labels[name] = l
	return l
end

local function changeSum(): number
	local sum = 0
	for _, v in picked do
		sum += v
	end
	return sum
end

local function refresh()
	if not current then
		return
	end
	labels.Item.Text = tostring(current.item or "")
	labels.Due.Text = string.format("Total: $%d", current.due or 0)
	labels.Paid.Text = string.format("Customer paid: $%d", current.paid or 0)
	labels.Change.Text = string.format("Your change: $%d", changeSum())
	local counts = {}
	for _, v in picked do
		counts[v] = (counts[v] or 0) + 1
	end
	local parts = {}
	for _, bill in current.bills or {} do
		if counts[bill] then
			table.insert(parts, string.format("$%d × %d", bill, counts[bill]))
		end
	end
	labels.Tray.Text = if #parts > 0 then table.concat(parts, "   ") else "Tap the bills to count out the change"
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
	for _, child in billRow:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, bill in bills do
		local b = make("TextButton", {
			Name = "Bill" .. bill, LayoutOrder = i, Size = UDim2.fromScale(1 / #bills - 0.025, 1), BackgroundColor3 = BILL_COLOR,
			Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "$" .. bill, AutoButtonColor = true,
		}, billRow)
		corner(b, 0.18)
		make("UIStroke", { Color = Color3.fromHex("2F5F2F"), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		b.Activated:Connect(function()
			if current then
				table.insert(picked, bill)
				refresh()
			end
		end)
	end
end

local function build()
	gui = make("ScreenGui", { Name = "Cashier", ResetOnSpawn = false, DisplayOrder = 6, IgnoreGuiInset = true, Enabled = false })
	panel = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.96), Size = UDim2.fromScale(0.5, 0.46),
		BackgroundColor3 = UiTheme.Cream, BackgroundTransparency = 0.05,
	}, gui)
	corner(panel, 0.06)
	make("UISizeConstraint", { MinSize = Vector2.new(340, 250), MaxSize = Vector2.new(640, 380) }, panel)
	make("UIStroke", { Color = UiTheme.Teal, Thickness = 3 }, panel)
	text("Title", panel, UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.5, 0.1), UiTheme.Golden, Enum.TextXAlignment.Left).Text = "🧾 Till"
	text("Item", panel, UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.92, 0.08), UiTheme.Ink, Enum.TextXAlignment.Left)
	text("Due", panel, UDim2.fromScale(0.04, 0.23), UDim2.fromScale(0.46, 0.13), UiTheme.Ink, Enum.TextXAlignment.Left)
	text("Paid", panel, UDim2.fromScale(0.5, 0.23), UDim2.fromScale(0.46, 0.13), UiTheme.Golden, Enum.TextXAlignment.Right)
	text("Change", panel, UDim2.fromScale(0.04, 0.38), UDim2.fromScale(0.6, 0.11), Color3.fromHex("8FE08F"), Enum.TextXAlignment.Left)
	text("Tray", panel, UDim2.fromScale(0.04, 0.5), UDim2.fromScale(0.92, 0.07), Color3.fromHex("B8BEC8"), Enum.TextXAlignment.Left)
	text("Message", panel, UDim2.fromScale(0.5, 0.38), UDim2.fromScale(0.46, 0.11), UiTheme.Coral, Enum.TextXAlignment.Right)
	billRow = make("Frame", { Name = "Bills", BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0.6), Size = UDim2.fromScale(0.92, 0.17) }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.025, 0), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, billRow)
	local function button(name: string, label: string, x: number, w: number, color: Color3): TextButton
		local b = make("TextButton", {
			Name = name, Position = UDim2.fromScale(x, 0.81), Size = UDim2.fromScale(w, 0.15), BackgroundColor3 = color,
			Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = label,
		}, panel)
		corner(b, 0.25)
		return b
	end
	button("Undo", "↩ Undo", 0.04, 0.2, UiTheme.Disabled).Activated:Connect(function()
		table.remove(picked)
		refresh()
	end)
	button("Clear", "Clear", 0.26, 0.2, UiTheme.Disabled).Activated:Connect(function()
		picked = {}
		refresh()
	end)
	giveButton = button("Give", "💵 Give change", 0.48, 0.48, UiTheme.Coral)
	giveButton.Activated:Connect(function()
		if current then
			Remotes.RequestGiveChange:FireServer(changeSum())
			labels.Message.Text = "…"
		end
	end)
	local x = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.97, 0.03), Size = UDim2.fromScale(0.08, 0.12),
		BackgroundColor3 = UiTheme.Disabled, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "X",
	}, panel)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, x)
	corner(x, 0.3)
	x.Activated:Connect(function()
		close(true)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
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
		labels.Message.Text = ""
		gui.Enabled = true
		refresh()
		log("till open:", data.item, data.due, data.paid)
	elseif data.state == "wrong" and current then
		labels.Message.Text = "That's not right! Count again."
		sound("wrong")
		task.spawn(shake)
	elseif data.state == "done" then
		labels.Message.Text = "Thank you! 😊"
		task.delay(0.8, function()
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
	-- walking away from the counter closes the till (the customer goes back to the normal auto-checkout timer)
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
