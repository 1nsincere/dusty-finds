-- SkinShopController.luau (StarterPlayerScripts.Client.Controllers.SkinShopController)
-- Purpose: the skins stall window (docs/10_Stock_Shop_And_Skins.md): 4 tabs. Pedestals / Shelves / Cashiers show this
-- restock's skins of that kind with Buy buttons (a live "New stock in m:ss" timer on top); Owned lets you use an owned
-- skin (or Classic) in your shop. Opened from the stall's prompt (Workspace.SkinStall.Counter). Also turns Mythic sparkles off on this
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
-- the 4 tabs: one per kind (what is in stock now) + Owned (use an owned skin, or Classic)
local TABS = {
	{ key = "Pedestal", label = "Pedestals" },
	{ key = "Shelf", label = "Shelves" },
	{ key = "Cashier", label = "Cashiers" },
	{ key = "Owned", label = "Owned" },
	{ key = "Wishlist", label = "Wishlist" }, -- every skin you don't own: pin up to 5 to get a toast when one is in stock
}
local tab = "Pedestal" -- a kind ("Pedestal" | "Shelf" | "Cashier"), "Owned" or "Wishlist"
local emptyLabel: TextLabel? = nil
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

-- the classic (no skin) colour of each kind's swatch
local CLASSIC_COLOR = {
	Shelf = Color3.fromRGB(216, 185, 138),
	Pedestal = Color3.fromRGB(217, 210, 197),
	Cashier = Color3.fromRGB(176, 122, 72),
}

-- true if Config.Skins has at least one skin of this kind (a kind with none yet shows "coming soon")
local function kindHasSkins(kind: string): boolean
	for _, skin in Skins.LIST do
		if skin.kind == kind then
			return true
		end
	end
	return false
end

-- A small picture of the skin: the block in its colour, with a band in the trim colour.
local function swatch(parent: Instance, skin: any, kind: string): Frame
	local look = skin and skin.look
	local base = Instance.new("Frame")
	base.Name = "Swatch"
	base.AnchorPoint = Vector2.new(0.5, 0)
	base.Position = UDim2.new(0.5, 0, 0, 8)
	base.Size = if kind == "Pedestal" then UDim2.fromOffset(30, 40) else UDim2.fromOffset(70, 30)
	base.BackgroundColor3 = if look then look.color else (CLASSIC_COLOR[kind] or Color3.fromRGB(217, 210, 197))
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

local function pinned(id: string): boolean
	local wishlist = ClientState.Get("wishlist")
	return type(wishlist) == "table" and wishlist[id] == true
end

local function inUse(kind: string): string
	local skins = ClientState.Get("skins")
	local field = Skins.FIELD[kind]
	return if type(skins) == "table" and type(skins[field]) == "string" then skins[field] else ""
end

-- "Try" (60 s on your own shop, client only): shelves and pedestals; cashier skins are models and can't be previewed yet
local function tryable(kind: string): boolean
	return (kind == "Shelf" or kind == "Pedestal") and others.PreviewController ~= nil
end

local function tryButton(parent: Instance, skin: any, kind: string)
	button(parent, "Try", "Try", UDim2.new(0.38, -8, 0, 30), UDim2.new(0, 8, 1, -36), function()
		local ok, reason = others.PreviewController.Try(kind, skin.id)
		if ok then
			SkinShopController.Close()
		else
			log("preview refused:", reason)
		end
	end)
end

local function card(skin: any, kind: string, order: number)
	local c = panel(list :: ScrollingFrame, "Card_" .. (if skin then skin.id else "Classic" .. kind), UDim2.new(), nil)
	c.LayoutOrder = order
	swatch(c, skin, kind)
	text(c, "Name", if skin then skin.name else `Classic {kind:lower()}`, UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 52))
	local rarity = if skin then skin.rarity else "Classic"
	local liveNow = tab == "Wishlist" and skin ~= nil and Stock.isInStock(Stock.restockIndex(now()), skin.id)
	text(c, "Rarity", `{rarity} · {kind}{if liveNow then " · IN STOCK" else ""}`, UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 70), if skin then UiTheme.rarityColor(skin.rarity) else UiSkin.COLORS.textDim)
	local id = if skin then skin.id else ""
	if tab == "Wishlist" then
		-- pin / unpin; the server tells you when a pinned skin is in stock (notify only: never changes the odds)
		local isPinned = pinned(id)
		if tryable(kind) then
			tryButton(c, skin, kind)
		end
		button(c, "Pin", if isPinned then "★ Pinned" else "☆ Pin", if tryable(kind) then UDim2.new(0.62, -10, 0, 30) else UDim2.new(1, -16, 0, 30), if tryable(kind) then UDim2.new(0.38, 4, 1, -36) else UDim2.new(0, 8, 1, -36), function()
			Remotes.RequestSetWishlist:FireServer(skin.id, not isPinned)
			log("asked to", if isPinned then "unpin" else "pin", skin.id)
		end, if isPinned then UiSkin.COLORS.accent else nil)
	elseif tab ~= "Owned" then
		if owned(id) then
			text(c, "State", "Owned", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), UiSkin.COLORS.good, UiSkin.FONT_TITLE)
		else
			local cash = ClientState.Get("cash") or 0
			if tryable(kind) then
				tryButton(c, skin, kind)
			end
			button(c, "Buy", UiTheme.formatCash(skin.price), if tryable(kind) then UDim2.new(0.62, -10, 0, 30) else UDim2.new(1, -16, 0, 30), if tryable(kind) then UDim2.new(0.38, 4, 1, -36) else UDim2.new(0, 8, 1, -36), function()
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
	box.Size = if kind == "Pedestal" then UDim2.fromOffset(30, 40) else UDim2.fromOffset(70, 30)
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

-- The open tab keeps a gold outline (the skin's hover effect resets outlines on MouseLeave, so this runs after it too).
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
	local empty = ""
	if tab == "Wishlist" then
		-- every skin you don't own yet: pinned first, then by kind and rarity (commonest first); "in stock now" shows on the card
		local index = Stock.restockIndex(now())
		shownIndex = index
		local rank: { [string]: number } = {}
		for i, name in Stock.RARITY_ORDER do
			rank[name] = i
		end
		local todo = {}
		for _, skin in Skins.LIST do
			if not owned(skin.id) then
				table.insert(todo, skin)
			end
		end
		table.sort(todo, function(a, b)
			local pa, pb = pinned(a.id), pinned(b.id)
			if pa ~= pb then
				return pa
			end
			if a.kind ~= b.kind then
				return a.kind < b.kind
			end
			if (rank[a.rarity] or 0) ~= (rank[b.rarity] or 0) then
				return (rank[a.rarity] or 0) < (rank[b.rarity] or 0)
			end
			return a.id < b.id
		end)
		for _, skin in todo do
			order += 1
			card(skin, skin.kind, order)
		end
		if #todo == 0 then
			empty = "You own every skin!"
		end
	elseif tab ~= "Owned" then
		-- a kind's tab: one card per rarity, the real skin if it rolled this restock, else a greyed "?" teaser
		local kind = tab
		local index = Stock.restockIndex(now())
		shownIndex = index
		if not kindHasSkins(kind) then
			empty = `{kind} skins are coming soon!`
		else
			local rolled: { [string]: any } = {}
			for _, id in Stock.roll(index) do
				local skin = Skins.BY_ID[id]
				if skin and skin.kind == kind then
					rolled[skin.rarity] = skin
				end
			end
			for _, rarity in Stock.RARITY_ORDER do
				order += 1
				local skin = rolled[rarity]
				if skin then
					card(skin, kind, order)
				else
					teaserCard(kind, rarity, order)
				end
			end
		end
	else
		-- Owned: per kind (same order as the tabs), Classic + every owned skin, each with Use
		for _, t in TABS do
			local kind = t.key
			if kind ~= "Owned" and kindHasSkins(kind) then
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
	end
	if emptyLabel then
		emptyLabel.Text = empty
		emptyLabel.Visible = empty ~= ""
	end
	paintTabs()
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
	-- 4 tabs side by side (fits a phone: 4 x 128 px)
	for i, t in TABS do
		tabButtons[t.key] = button(w, "Tab" .. t.key, t.label, UDim2.fromOffset(120, 34), UDim2.fromOffset(14 + (i - 1) * 128, 46), function()
			tab = t.key
			render()
		end)
		tabButtons[t.key].MouseLeave:Connect(function()
			task.defer(paintTabs) -- after the hover effect's own reset
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
	grid.CellSize = UDim2.fromOffset(140, 128)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = scroll
	emptyLabel = text(w, "Empty", "", UDim2.new(1, -40, 0, 30), UDim2.new(0, 20, 0.5, -15), UiSkin.COLORS.textDim, UiSkin.FONT_TITLE)
	;(emptyLabel :: TextLabel).Visible = false
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
	tab = TABS[1].key
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
	-- a floating "Fresh stock in m:ss" sign over the stall (so you can see the restock from the market floor without opening the window)
	task.spawn(function()
		local stall = workspace:WaitForChild("SkinStall", 60)
		local counter = stall and stall:WaitForChild("Counter", 10)
		if not (counter and counter:IsA("BasePart")) then
			return
		end
		local board = Instance.new("BillboardGui")
		board.Name = "RestockSign"
		board.Adornee = counter
		board.Size = UDim2.fromOffset(190, 34)
		board.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
		board.MaxDistance = 70
		board.AlwaysOnTop = false
		board.Parent = counter
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(34, 36, 42)
		label.BackgroundTransparency = 0.2
		label.TextScaled = true
		label.FontFace = UiSkin.FONT_TITLE
		label.TextColor3 = UiSkin.COLORS.accent
		label.Parent = board
		Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.5 then
				return
			end
			acc = 0
			local left = math.max(0, math.floor(Stock.secondsLeft(now())))
			label.Text = string.format("Fresh stock in %d:%02d", left // 60, left % 60)
		end)
	end)
	-- live data: re-draw when skins or cash change; timer and restock while open
	ClientState.OnChanged("skins", function()
		if SkinShopController.IsOpen() then
			render()
		end
	end)
	ClientState.OnChanged("wishlist", function()
		if SkinShopController.IsOpen() and tab == "Wishlist" then
			render()
		end
	end)
	ClientState.OnChanged("cash", function()
		if SkinShopController.IsOpen() and tab ~= "Owned" then
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
		if tab ~= "Owned" and Stock.restockIndex(now()) ~= shownIndex then
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
