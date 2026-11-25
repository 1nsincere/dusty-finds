-- PaintShopController.luau (StarterPlayerScripts.Client.Controllers.PaintShopController)
-- Purpose: the Paint Bar window in the Warehouse Market (docs/12 Stage 2): tabs Walls / Floors (always in stock, Buy) and
-- Owned (use a paint, or the original look). Opened from the Paint Bar prompt (Workspace.PaintCounter).
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Paints, Shared.Remotes (RequestBuyPaint, RequestApplyPaint), ClientState
-- (paints, cash), UiTheme, UiSkin + HudSkinController (look). The server checks every request; this only shows and asks.
-- Built like SkinShopController (same card grid) so both stalls feel like one family.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Paints = require(Shared:WaitForChild("Config"):WaitForChild("Paints"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local PaintShopController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui? = nil
local list: ScrollingFrame? = nil
local tabButtons: { [string]: GuiObject } = {}
local TABS = {
	{ key = "Wall", label = "Walls" },
	{ key = "Floor", label = "Floors" },
	{ key = "Owned", label = "Owned" },
}
local tab = "Wall"

local function log(...)
	if DEBUG then
		print("[PaintShopController]", ...)
	end
end

local function counter(): BasePart?
	local c = workspace:FindFirstChild("PaintCounter")
	return if c and c:IsA("BasePart") then c else nil
end

-- ===== Building blocks (same pattern as SkinShopController) =====

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

-- ===== The list =====

local function state(): any
	local paints = ClientState.Get("paints")
	return if type(paints) == "table" then paints else { owned = {}, wall = "", floor = "" }
end

local function owned(id: string): boolean
	local s = state()
	return type(s.owned) == "table" and s.owned[id] == true
end

local function inUse(kind: string): string
	local value = state()[Paints.FIELD[kind]]
	return if type(value) == "string" then value else ""
end

-- A small picture: a wall panel in the paint colour, or a floor tile.
local function swatch(parent: Instance, paint: any, kind: string)
	local base = Instance.new("Frame")
	base.Name = "Swatch"
	base.AnchorPoint = Vector2.new(0.5, 0)
	base.Position = UDim2.new(0.5, 0, 0, 8)
	base.Size = UDim2.fromOffset(70, 34)
	base.BackgroundColor3 = if paint then paint.color else (if kind == "Wall" then Color3.fromRGB(244, 240, 232) else Color3.fromRGB(176, 150, 112))
	base.BorderSizePixel = 0
	Instance.new("UICorner", base).CornerRadius = UDim.new(0, 3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.7
	stroke.Parent = base
	if kind == "Floor" then
		-- tile lines so a floor swatch doesn't look like a wall swatch
		for i = 1, 2 do
			local line = Instance.new("Frame")
			line.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			line.BackgroundTransparency = 0.8
			line.BorderSizePixel = 0
			line.Size = UDim2.new(1, 0, 0, 1)
			line.Position = UDim2.new(0, 0, i / 3, 0)
			line.Parent = base
		end
	end
	base.Parent = parent
end

local function card(paint: any, kind: string, order: number)
	local c = panel(list :: ScrollingFrame, "Card_" .. (if paint then paint.id else "Original" .. kind), UDim2.new(), nil)
	c.LayoutOrder = order
	swatch(c, paint, kind)
	text(c, "Name", if paint then paint.name else `Original {kind:lower()}`, UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 48))
	text(c, "Kind", if paint then (if kind == "Wall" then "Wall paint" else "Floor") else "No paint", UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 66), UiSkin.COLORS.textDim)
	local id = if paint then paint.id else ""
	if tab ~= "Owned" then
		if owned(id) then
			text(c, "State", "Owned", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
		else
			local cash = ClientState.Get("cash") or 0
			-- "Try" shows it on YOUR shop for 60 s (client only); the window closes so you can see it
			button(c, "Try", "Try", UDim2.new(0.38, -8, 0, 30), UDim2.new(0, 8, 1, -36), function()
				local pv = others.PreviewController
				if pv then
					local ok, reason = pv.Try(kind, paint.id)
					if ok then
						PaintShopController.Close()
					else
						log("preview refused:", reason)
					end
				end
			end)
			button(c, "Buy", UiTheme.formatCash(paint.price), UDim2.new(0.62, -10, 0, 30), UDim2.new(0.38, 4, 1, -36), function()
				Remotes.RequestBuyPaint:FireServer(paint.id)
				log("asked to buy", paint.id)
			end, if cash >= paint.price then UiSkin.COLORS.money else UiSkin.COLORS.textDim)
		end
	else
		if inUse(kind) == id then
			text(c, "State", "In use", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
		else
			button(c, "Use", "Use", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -36), function()
				Remotes.RequestApplyPaint:FireServer(kind, id)
				log("asked to use", kind, id)
			end)
		end
	end
end

local function paintTabs()
	for name, b in tabButtons do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if name == tab then UiSkin.COLORS.accent else UiSkin.COLORS.edge
			stroke.Transparency = if name == tab then 0.15 else UiSkin.COLORS.edgeTransparency
		end
	end
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
	if tab ~= "Owned" then
		for _, paint in Paints.LIST do
			if paint.kind == tab then
				order += 1
				card(paint, tab, order)
			end
		end
	else
		for _, kind in Paints.KINDS do
			order += 1
			card(nil, kind, order)
			for _, paint in Paints.LIST do
				if paint.kind == kind and owned(paint.id) then
					order += 1
					card(paint, kind, order)
				end
			end
		end
	end
	paintTabs()
end

-- ===== Window =====

function PaintShopController.Close()
	if gui then
		gui.Enabled = false
	end
end

function PaintShopController.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "PaintShop"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 15
	local w = panel(screen, "Window", UDim2.fromScale(0.86, 0.8), UDim2.fromScale(0.5, 0.52))
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(660, 430)
	limit.Parent = w
	text(w, "Title", "PAINT BAR", UDim2.new(0.5, 0, 0, 30), UDim2.fromOffset(14, 8), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	text(w, "Hint", "Wall and floor colours for your shop. Always in stock.", UDim2.new(0.55, 0, 0, 18), UDim2.new(0.45, -50, 0, 16), UiSkin.COLORS.accent, UiSkin.FONT_TEXT, Enum.TextXAlignment.Right)
	button(w, "Close", "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), PaintShopController.Close)
	for i, t in TABS do
		tabButtons[t.key] = button(w, "Tab" .. t.key, t.label, UDim2.fromOffset(120, 34), UDim2.fromOffset(14 + (i - 1) * 128, 46), function()
			tab = t.key
			render()
		end)
		tabButtons[t.key].MouseLeave:Connect(function()
			task.defer(paintTabs)
		end)
	end
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
	grid.CellSize = UDim2.fromOffset(140, 118)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = scroll
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, list = screen, scroll
end

function PaintShopController.Open()
	if gui == nil then
		build()
	end
	-- one window at a time
	for _, name in { "InventoryController", "SettingsController", "CollectionController", "VisitController", "SkinShopController" } do
		local c = others[name]
		if c and c.Close then
			c.Close()
		end
	end
	if others.ShopController and others.ShopController.CloseAll then
		others.ShopController.CloseAll()
	end
	tab = TABS[1].key
	render();
	(gui :: ScreenGui).Enabled = true
	log("opened")
end

function PaintShopController.Init(controllers)
	others = controllers
end

function PaintShopController.Start()
	-- the Paint Bar prompt opens the window; walking away closes it
	task.spawn(function()
		local c = workspace:WaitForChild("PaintCounter", 60)
		local prompt = c and c:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			warn("[PaintShopController] Workspace.PaintCounter has no ProximityPrompt: the Paint Bar can't be opened")
			return
		end
		prompt.Triggered:Connect(PaintShopController.Open)
		log("ready: Paint Bar prompt hooked")
	end)
	ClientState.OnChanged("paints", function()
		if PaintShopController.IsOpen() then
			render()
		end
	end)
	ClientState.OnChanged("cash", function()
		if PaintShopController.IsOpen() and tab ~= "Owned" then
			render()
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.5 or not PaintShopController.IsOpen() then
			return
		end
		since = 0
		local c = counter()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if c and root and (root.Position - c.Position).Magnitude > Paints.BuyMaxStuds + 6 then
			PaintShopController.Close()
		end
	end)
end

return PaintShopController
