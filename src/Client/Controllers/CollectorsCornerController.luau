-- CollectorsCornerController.luau (StarterPlayerScripts.Client.Controllers.CollectorsCornerController)
-- Purpose: the Collector's Corner window (docs/12 Stage 5): every Robux product in one calm place, price always in plain sight.
-- Tabs: Passes (themes, Glow Pack, Saved Layouts, Companion, Big Storage; "Preview" on themes), VIP (buy, then choose your pet,
-- pet colour, aura style and title), Tip jar. Opened from the Corner's prompt (Workspace.CollectorsCorner.Counter).
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Monetization, Shared.Remotes (RequestPurchasePass, RequestPurchaseProduct,
-- RequestSetVip), ClientState (entitlements, vip), PreviewController, UiTheme, UiSkin + HudSkinController (look).
-- The server checks every request and only saves a pass after Roblox confirms it; this window only shows and asks.
-- Rules (docs/11): never opened by itself (no pop-up, not on spawn, not while restoring or at the till); a price is never hidden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local CollectorsCornerController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui? = nil
local list: ScrollingFrame? = nil
local tabButtons: { [string]: GuiObject } = {}
local TABS = {
	{ key = "Passes", label = "Passes" },
	{ key = "VIP", label = "VIP" },
	{ key = "Tips", label = "Tip jar" },
}
local tab = "Passes"
local MAX_STUDS = 22

local function log(...)
	if DEBUG then
		print("[CollectorsCornerController]", ...)
	end
end

local function counter(): BasePart?
	local corner = workspace:FindFirstChild("CollectorsCorner")
	local c = corner and corner:FindFirstChild("Counter")
	return if c and c:IsA("BasePart") then c else nil
end

-- ===== Building blocks (same pattern as the other stall windows) =====

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

local function owns(passId: string): boolean
	local entitlements = ClientState.Get("entitlements")
	return type(entitlements) == "table" and entitlements[passId] == true
end

local function vipChoice(field: string): string
	local vip = ClientState.Get("vip")
	return if type(vip) == "table" and type(vip[field]) == "string" then vip[field] else ""
end

local function robux(price: number): string
	return `R$ {price}`
end

-- ===== Tab: passes =====

-- One pass as a wide card: name + price on the left, a short plain explanation, and the button on the right.
local function passCard(pass: any, order: number)
	local c = panel(list :: ScrollingFrame, "Pass_" .. pass.id, UDim2.new(), nil)
	c.LayoutOrder = order
	text(c, "Name", pass.name, UDim2.new(1, -150, 0, 22), UDim2.fromOffset(10, 6), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	text(c, "Price", robux(pass.price), UDim2.new(0, 120, 0, 18), UDim2.fromOffset(10, 30), UiSkin.COLORS.money, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	local blurb = text(c, "Blurb", pass.blurb, UDim2.new(1, -150, 0, 34), UDim2.fromOffset(10, 52), UiSkin.COLORS.textDim, UiSkin.FONT_TEXT, Enum.TextXAlignment.Left)
	blurb.TextWrapped = true
	blurb.TextScaled = false
	blurb.TextSize = 13
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	if owns(pass.id) then
		text(c, "State", "Owned ✓", UDim2.fromOffset(120, 30), UDim2.new(1, -130, 0, 10), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
	elseif pass.passId <= 0 then
		text(c, "State", "Coming soon", UDim2.fromOffset(120, 30), UDim2.new(1, -130, 0, 10), UiSkin.COLORS.textDim, UiSkin.FONT_TITLE)
	else
		button(c, "Buy", "Buy", UDim2.fromOffset(120, 34), UDim2.new(1, -130, 0, 8), function()
			Remotes.RequestPurchasePass:FireServer(pass.id)
			log("asked to buy", pass.id)
		end, UiSkin.COLORS.money)
	end
	if pass.kind == "Theme" and pass.grants and others.PreviewController then
		button(c, "Preview", "Preview", UDim2.fromOffset(120, 28), UDim2.new(1, -130, 1, -38), function()
			local ok, reason = others.PreviewController.TryTheme(pass.name, pass.grants.paints or {}, pass.grants.skins or {})
			if ok then
				CollectorsCornerController.Close()
			else
				log("preview refused:", reason)
			end
		end)
	end
end

-- ===== Tab: VIP =====

local function choiceButtons(label: string, field: string, options: { any }, order: number)
	local row = panel(list :: ScrollingFrame, "Row_" .. field, UDim2.new(), nil)
	row.LayoutOrder = order
	text(row, "Label", label, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 4), UiSkin.COLORS.textDim, UiSkin.FONT_TEXT, Enum.TextXAlignment.Left)
	local x = 10
	local current = vipChoice(field)
	for _, option in options do
		local on = option.id == current
		button(row, "Opt_" .. option.id, option.name, UDim2.fromOffset(104, 30), UDim2.fromOffset(x, 28), function()
			Remotes.RequestSetVip:FireServer(field, if on then "" else option.id)
		end, if on then UiSkin.COLORS.accent else nil)
		x += 110
	end
end

local function vipTab()
	local pass = Monetization.BY_PASS.VIP
	local order = 1
	passCard(pass, order)
	if not owns("VIP") then
		return
	end
	order += 1
	choiceButtons("Pet (pick the same again to remove it)", "pet", Monetization.VIP.Pets, order)
	order += 1
	choiceButtons("Pet colour", "petColor", Monetization.VIP.PetColors, order)
	order += 1
	choiceButtons("Aura style (the aura's strength is still earned)", "auraStyle", Monetization.VIP.AuraStyles, order)
	order += 1
	local titles = {}
	for _, t in Monetization.VIP.Titles do
		table.insert(titles, { id = t, name = t })
	end
	choiceButtons("Title above your head", "title", titles, order)
end

-- ===== Tab: tip jar =====

local function tipsTab()
	local order = 0
	local intro = panel(list :: ScrollingFrame, "TipIntro", UDim2.new(), nil)
	intro.LayoutOrder = order
	local msg = text(intro, "Msg", "Loving Dusty Finds? A tip helps us make more. It gives nothing in the game, just our thanks!", UDim2.new(1, -20, 1, -10), UDim2.fromOffset(10, 5), UiSkin.COLORS.text, UiSkin.FONT_TEXT, Enum.TextXAlignment.Left)
	msg.TextWrapped = true
	msg.TextScaled = false
	msg.TextSize = 15
	for _, product in Monetization.PRODUCTS do
		order += 1
		local c = panel(list :: ScrollingFrame, "Tip_" .. product.id, UDim2.new(), nil)
		c.LayoutOrder = order
		text(c, "Name", product.name, UDim2.new(1, -150, 0, 22), UDim2.fromOffset(10, 8), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
		text(c, "Price", robux(product.price), UDim2.new(0, 120, 0, 18), UDim2.fromOffset(10, 34), UiSkin.COLORS.money, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
		if product.productId <= 0 then
			text(c, "State", "Coming soon", UDim2.fromOffset(120, 30), UDim2.new(1, -130, 0, 12), UiSkin.COLORS.textDim, UiSkin.FONT_TITLE)
		else
			button(c, "Tip", "Tip", UDim2.fromOffset(120, 34), UDim2.new(1, -130, 0, 10), function()
				Remotes.RequestPurchaseProduct:FireServer(product.id)
			end, UiSkin.COLORS.money)
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
	if tab == "Passes" then
		local order = 0
		for _, pass in Monetization.PASSES do
			if pass.id ~= "VIP" and pass.hidden ~= true then
				order += 1
				passCard(pass, order)
			end
		end
	elseif tab == "VIP" then
		vipTab()
	else
		tipsTab()
	end
	paintTabs()
end

-- ===== Window =====

function CollectorsCornerController.Close()
	if gui then
		gui.Enabled = false
	end
end

function CollectorsCornerController.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "CollectorsCorner"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 15
	local w = panel(screen, "Window", UDim2.fromScale(0.86, 0.82), UDim2.fromScale(0.5, 0.52))
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(680, 450)
	limit.Parent = w
	text(w, "Title", "COLLECTOR'S CORNER", UDim2.new(0.55, 0, 0, 30), UDim2.fromOffset(14, 8), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	text(w, "Hint", "Fixed prices. Nothing random. Looks and convenience only.", UDim2.new(0.5, -60, 0, 16), UDim2.new(0.5, 0, 0, 16), UiSkin.COLORS.accent, UiSkin.FONT_TEXT, Enum.TextXAlignment.Right)
	button(w, "Close", "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), CollectorsCornerController.Close)
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
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	-- every card is a wide row; the rows set their own height
	scroll.ChildAdded:Connect(function(child)
		if child:IsA("Frame") then
			local isChoice = string.sub(child.Name, 1, 4) == "Row_"
			child.Size = UDim2.new(1, -8, 0, if isChoice then 66 elseif child.Name == "TipIntro" then 56 elseif string.sub(child.Name, 1, 4) == "Tip_" then 64 else 92)
		end
	end)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = scroll
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, list = screen, scroll
end

function CollectorsCornerController.Open()
	if gui == nil then
		build()
	end
	-- one window at a time
	for _, name in { "InventoryController", "SettingsController", "CollectionController", "VisitController", "SkinShopController", "PaintShopController" } do
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

function CollectorsCornerController.Init(controllers)
	others = controllers
end

function CollectorsCornerController.Start()
	task.spawn(function()
		local corner = workspace:WaitForChild("CollectorsCorner", 60)
		local c = corner and corner:WaitForChild("Counter", 10)
		local prompt = c and c:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			warn("[CollectorsCornerController] Workspace.CollectorsCorner.Counter has no ProximityPrompt: the Corner can't be opened")
			return
		end
		prompt.Triggered:Connect(CollectorsCornerController.Open)
		log("ready: Corner prompt hooked")
	end)
	for _, key in { "entitlements", "vip" } do
		ClientState.OnChanged(key, function()
			if CollectorsCornerController.IsOpen() then
				render()
			end
		end)
	end
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.5 or not CollectorsCornerController.IsOpen() then
			return
		end
		since = 0
		local c = counter()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if c and root and (root.Position - c.Position).Magnitude > MAX_STUDS + 8 then
			CollectorsCornerController.Close()
		end
	end)
end

return CollectorsCornerController
