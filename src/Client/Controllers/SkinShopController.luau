-- SkinShopController.luau (StarterPlayerScripts.Client.Controllers.SkinShopController)
-- Purpose: the skins stall window (docs/10_Stock_Shop_And_Skins.md): "In stock" shows this restock's shelf / pedestal
-- skins with a live "New stock in m:ss" timer and Buy buttons; "My skins" lets you use an owned skin (or Classic) in
-- your shop. Opened from the stall's prompt (Workspace.SkinStall.Counter). Also turns Mythic sparkles off on this
-- screen when Settings "Reduce effects" is on.
-- Owner: Dev 3 (Sean). Depends on: Shared.Stock (same roll as the server, from the server clock), Shared.Config
-- (Skins, Stock), Shared.Remotes (RequestBuySkin, RequestApplySkin), ClientState (skins, cash, settings), UiTheme,
-- UiSkin + HudSkinController (look). The server checks every request; this only shows and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Stock = require(Shared:WaitForChild("Stock"))
local Skins = require(Shared:WaitForChild("Config"):WaitForChild("Skins"))
local StockConfig = require(Shared:WaitForChild("Config"):WaitForChild("Stock"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local SkinShopController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui? = nil
local window: Frame? = nil
local list: ScrollingFrame? = nil
local timerLabel: TextLabel? = nil
local tab = "Stock" -- "Stock" | "Mine"
local shownIndex = -1
local tabButtons: { [string]: GuiObject } = {}

local function log(...)
	if DEBUG then
		print("[SkinShopController]", ...)
	end
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stallCounter(): BasePart?
	local stall = workspace:FindFirstChild("SkinStall")
	local counter = stall and stall:FindFirstChild("Counter")
	return if counter and counter:IsA("BasePart") then counter else nil
end

-- ===== Building blocks (text always sits in a child label: the skin's gradient would tint a label's own text) =====

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.new()
	f.Parent = parent
	local skin = others.HudSkinController
	if skin and skin.Panel then
		skin.Panel(f)
	else
		f.BackgroundColor3 = UiTheme.Cream
	end
	return f
end

local function text(parent: Instance, name: string, value: string, size: UDim2, position: UDim2?, color: Color3?, font: Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position or UDim2.new()
	l.TextScaled = true
	l.FontFace = font or UiSkin.FONT_TEXT
	l.TextColor3 = color or UiSkin.COLORS.text
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Text = value
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, size: UDim2, position: UDim2?, onClick: () -> (), color: Color3?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = name
	b.Image = ""
	b.Size = size
	b.Position = position or UDim2.new()
	b.Parent = parent
	local skin = others.HudSkinController
	if skin and skin.Panel then
		skin.Panel(b)
	end
	if skin and skin.Button then
		skin.Button(b)
	end
	local t = text(b, "Text", label, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), color or UiSkin.COLORS.text, UiSkin.FONT_TITLE)
	t.ZIndex = b.ZIndex + 1
	b.Activated:Connect(onClick)
	return b
end

-- A small picture of the skin: the block in its colour, with a band in the trim colour.
local function swatch(parent: Instance, skin: any, kind: string): Frame
	local look = skin and skin.look
	local base = Instance.new("Frame")
	base.Name = "Swatch"
	base.AnchorPoint = Vector2.new(0.5, 0)
	base.Position = UDim2.new(0.5, 0, 0, 8)
	base.Size = if kind == "Shelf" then UDim2.fromOffset(70, 30) else UDim2.fromOffset(30, 40)
	base.BackgroundColor3 = if look then look.color else (if kind == "Shelf" then Color3.fromRGB(216, 185, 138) else Color3.fromRGB(217, 210, 197))
	base.BorderSizePixel = 0
	Instance.new("UICorner", base).CornerRadius = UDim.new(0, 3)
	if look and look.trim then
		local band = Instance.new("Frame")
		band.Name = "Trim"
		band.BackgroundColor3 = look.trim
		band.BorderSizePixel = 0
		band.Size = UDim2.new(1, 4, 0, 5)
		band.Position = UDim2.fromOffset(-2, -2)
		band.Parent = base
	end
	if look and look.light then
		local glow = Instance.new("UIStroke")
		glow.Color = look.light
		glow.Thickness = 2
		glow.Parent = base
	end
	base.Parent = parent
	return base
end

-- ===== The list =====

local function owned(id: string): boolean
	local skins = ClientState.Get("skins")
	return type(skins) == "table" and type(skins.owned) == "table" and skins.owned[id] == true
end

local function inUse(kind: string): string
	local skins = ClientState.Get("skins")
	local field = if kind == "Shelf" then "shelf" else "pedestal"
	return if type(skins) == "table" and type(skins[field]) == "string" then skins[field] else ""
end

local function card(skin: any, kind: string, order: number)
	local c = panel(list :: ScrollingFrame, "Card_" .. (if skin then skin.id else "Classic" .. kind), UDim2.new(), nil)
	c.LayoutOrder = order
	swatch(c, skin, kind)
	text(c, "Name", if skin then skin.name else `Classic {kind:lower()}`, UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 52))
	local rarity = if skin then skin.rarity else "Classic"
	text(c, "Rarity", `{rarity} · {kind}`, UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 70), if skin then UiTheme.rarityColor(skin.rarity) else UiSkin.COLORS.textDim)
	local id = if skin then skin.id else ""
	if tab == "Stock" then
		if owned(id) then
			text(c, "State", "Owned", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
		else
			local cash = ClientState.Get("cash") or 0
			button(c, "Buy", UiTheme.formatCash(skin.price), UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -36), function()
				Remotes.RequestBuySkin:FireServer(skin.id)
				log("asked to buy", skin.id)
			end, if cash >= skin.price then UiSkin.COLORS.money else UiSkin.COLORS.textDim)
		end
	else
		if inUse(kind) == id then
			text(c, "State", "In use", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
		else
			button(c, "Use", "Use", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -36), function()
				Remotes.RequestApplySkin:FireServer(kind, id)
				log("asked to use", kind, id)
			end)
		end
	end
end

-- A rarity that didn't roll this restock: you see what COULD come, not the skin itself.
local function teaserCard(kind: string, rarity: string, order: number)
	local c = panel(list :: ScrollingFrame, `Teaser_{kind}_{rarity}`, UDim2.new(), nil)
	c.LayoutOrder = order
	local box = Instance.new("Frame")
	box.Name = "Mystery"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 8)
	box.Size = if kind == "Shelf" then UDim2.fromOffset(70, 30) else UDim2.fromOffset(30, 40)
	box.BackgroundColor3 = Color3.fromRGB(46, 50, 58)
	box.BorderSizePixel = 0
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiTheme.rarityColor(rarity)
	stroke.Transparency = 0.4
	stroke.Parent = box
	box.Parent = c
	text(box, "Q", "?", UDim2.fromScale(1, 1), nil, UiTheme.rarityColor(rarity), UiSkin.FONT_TITLE)
	text(c, "Name", "???", UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 52), UiSkin.COLORS.textDim)
	text(c, "Rarity", `{rarity} · {kind}`, UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 70), UiTheme.rarityColor(rarity))
	text(c, "State", "Not in stock", UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.textDim, UiSkin.FONT_TITLE)
	c.BackgroundTransparency = 0.45 -- dimmer than a real card
end

local function render()
	if list == nil then
		return
	end
	for _, child in (list :: ScrollingFrame):GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	if tab == "Stock" then
		-- one card per kind and rarity: the real skin if it rolled this restock, else a greyed "?" teaser
		local index = Stock.restockIndex(now())
		shownIndex = index
		local rolled: { [string]: any } = {}
		for _, id in Stock.roll(index) do
			local skin = Skins.BY_ID[id]
			if skin then
				rolled[skin.kind .. "/" .. skin.rarity] = skin
			end
		end
		for _, kind in Skins.KINDS do
			for _, rarity in Stock.RARITY_ORDER do
				order += 1
				local skin = rolled[kind .. "/" .. rarity]
				if skin then
					card(skin, kind, order)
				else
					teaserCard(kind, rarity, order)
				end
			end
		end
	else
		for _, kind in Skins.KINDS do
			order += 1
			card(nil, kind, order)
			for _, skin in Skins.LIST do
				if skin.kind == kind and owned(skin.id) then
					order += 1
					card(skin, kind, order)
				end
			end
		end
	end
	for name, b in tabButtons do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if name == tab then UiSkin.COLORS.accent else UiSkin.COLORS.edge
			stroke.Transparency = if name == tab then 0.15 else UiSkin.COLORS.edgeTransparency
		end
	end
end

-- ===== Window =====

function SkinShopController.Close()
	if gui then
		gui.Enabled = false
	end
end

function SkinShopController.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SkinShop"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 15
	local w = panel(screen, "Window", UDim2.fromScale(0.86, 0.8), UDim2.fromScale(0.5, 0.52))
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(660, 430)
	limit.Parent = w
	text(w, "Title", "SKINS STALL", UDim2.new(0.5, 0, 0, 30), UDim2.fromOffset(14, 8), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	timerLabel = text(w, "Timer", "", UDim2.new(0.42, 0, 0, 20), UDim2.new(0.5, -50, 0, 14), UiSkin.COLORS.accent, UiSkin.FONT_TEXT, Enum.TextXAlignment.Right)
	button(w, "Close", "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), SkinShopController.Close)
	tabButtons.Stock = button(w, "TabStock", "In stock", UDim2.fromOffset(120, 34), UDim2.fromOffset(14, 46), function()
		tab = "Stock"
		render()
	end)
	tabButtons.Mine = button(w, "TabMine", "My skins", UDim2.fromOffset(120, 34), UDim2.fromOffset(142, 46), function()
		tab = "Mine"
		render()
	end)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 90)
	scroll.Size = UDim2.new(1, -24, 1, -100)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = w
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(140, 128)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = scroll
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, window, list = screen, w, scroll
end

function SkinShopController.Open()
	if gui == nil then
		build()
	end
	-- one window at a time
	for _, name in { "InventoryController", "SettingsController", "CollectionController", "VisitController" } do
		local c = others[name]
		if c and c.Close then
			c.Close()
		end
	end
	if others.ShopController and others.ShopController.CloseAll then
		others.ShopController.CloseAll()
	end
	tab = "Stock"
	render();
	(gui :: ScreenGui).Enabled = true
	log("opened")
end

-- ===== Mythic sparkles follow Settings "Reduce effects" on this screen =====

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

local function syncSparkle(emitter: Instance)
	if emitter:IsA("ParticleEmitter") and emitter.Name == "SkinSparkle" and reduceEffects() and emitter.Enabled then
		emitter.Enabled = false -- local only; the server turns it back on when the piece is shown again
	end
end

local function watchSparkles()
	local plots = workspace:WaitForChild("Plots", 30)
	if not plots then
		return
	end
	local function hook(d: Instance)
		if d:IsA("ParticleEmitter") and d.Name == "SkinSparkle" then
			syncSparkle(d)
			d:GetPropertyChangedSignal("Enabled"):Connect(function()
				syncSparkle(d)
			end)
		end
	end
	for _, d in plots:GetDescendants() do
		hook(d)
	end
	plots.DescendantAdded:Connect(hook)
	ClientState.OnChanged("settings", function()
		for _, d in plots:GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Name == "SkinSparkle" then
				local visible = d.Parent and d.Parent:IsA("BasePart") and d.Parent.Transparency < 0.99
				d.Enabled = visible and not reduceEffects()
			end
		end
	end)
end

function SkinShopController.Init(controllers)
	others = controllers
end

function SkinShopController.Start()
	-- the stall's prompt opens the window; walking away closes it
	task.spawn(function()
		local stall = workspace:WaitForChild("SkinStall", 60)
		local counter = stall and stall:WaitForChild("Counter", 10)
		local prompt = counter and counter:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			warn("[SkinShopController] Workspace.SkinStall.Counter has no ProximityPrompt: the stall can't be opened")
			return
		end
		prompt.Triggered:Connect(SkinShopController.Open)
		log("ready: stall prompt hooked")
	end)
	task.spawn(watchSparkles)
	-- live data: re-draw when skins or cash change; timer and restock while open
	ClientState.OnChanged("skins", function()
		if SkinShopController.IsOpen() then
			render()
		end
	end)
	ClientState.OnChanged("cash", function()
		if SkinShopController.IsOpen() and tab == "Stock" then
			render()
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.25 or not SkinShopController.IsOpen() then
			return
		end
		since = 0
		local left = math.max(0, math.floor(Stock.secondsLeft(now())))
		if timerLabel then
			timerLabel.Text = string.format("New stock in %d:%02d", left // 60, left % 60)
		end
		if tab == "Stock" and Stock.restockIndex(now()) ~= shownIndex then
			render()
		end
		local counter = stallCounter()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if counter and root and (root.Position - counter.Position).Magnitude > StockConfig.BuyMaxStuds + 6 then
			SkinShopController.Close()
		end
	end)
end

return SkinShopController
