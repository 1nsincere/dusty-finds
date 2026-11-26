-- CollectionController.luau
-- Purpose: the 📖 Collection Book. One page per item tier (4×3 grid); each entry shows not found (?) → found →
-- best restored stars → golden. Reads my `collection` data ([itemId] = {found, bestStars, golden}) and Config.Items.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Config.{Items,Crates}, StarterGui.Collection
-- (Book.{Title,CloseButton,PageLabel,PrevButton,NextButton,Grid}, EntryTemplate), HUD.LeftButtons.Collection,
-- Inventory/Shop/Discovery controllers (one window open at a time). Page rewards: not built on the server yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Items = require(Config:WaitForChild("Items"))
local Crates = require(Config:WaitForChild("Crates"))
local Unboxing = require(script.Parent.Parent:WaitForChild("UnboxingKit")) -- Unboxing.ItemViewport: the item model in a small viewport

local CollectionController = {}
local DEBUG = true

local NOT_FOUND_COLOR = Color3.fromRGB(70, 75, 85)
local NOT_FOUND_STROKE = Color3.fromRGB(190, 190, 190)

local player = Players.LocalPlayer
local others = nil
local collectionGui: ScreenGui? = nil
local pages: { { tier: number, name: string, items: { any } } } = {}
local pageIndex = 1

local function log(...)
	if DEBUG then
		print("[CollectionController]", ...)
	end
end

-- Pages come from Config: every tier that has items, named after the paid crate that sells it ("Starter").
local function buildPages()
	local tierNames = {}
	for _, crate in Crates do
		if type(crate) == "table" and type(crate.tier) == "number" and (crate.price or 0) > 0 and crate.name then
			tierNames[crate.tier] = string.gsub(crate.name, " Crate$", "")
		end
	end
	local byTier = {}
	for _, def in Items do
		if type(def) == "table" and type(def.tier) == "number" then
			byTier[def.tier] = byTier[def.tier] or {}
			table.insert(byTier[def.tier], def)
		end
	end
	for tier, list in byTier do
		-- Cheapest first, so Commons lead and the Legendary is the last tile on the page.
		table.sort(list, function(a, b)
			if a.baseValue ~= b.baseValue then
				return (a.baseValue or 0) < (b.baseValue or 0)
			end
			return a.id < b.id
		end)
		-- A page holds 12 tiles (4 x 3). A tier with more items (Starter has 15) continues on a second page: "Starter 2".
		local baseName = tierNames[tier] or `Tier {tier}`
		local PAGE_SIZE = 12
		for first = 1, #list, PAGE_SIZE do
			local chunk = {}
			for i = first, math.min(first + PAGE_SIZE - 1, #list) do
				table.insert(chunk, list[i])
			end
			table.insert(pages, { tier = tier, name = if first == 1 then baseName else `{baseName} {(first - 1) // PAGE_SIZE + 1}`, items = chunk })
		end
	end
	table.sort(pages, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.name < b.name
	end)
end

local function starsText(stars: number): string
	local n = math.clamp(math.floor(stars), 0, 3)
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

local function countFound(list: { any }, collection: { [string]: any }): number
	local found = 0
	for _, def in list do
		local entry = collection[def.id]
		if type(entry) == "table" and entry.found then
			found += 1
		end
	end
	return found
end

-- ===== The album (redesigned 2026-11-25): a tab rail on the left, trading cards on the right =====
-- Every page (tier) is a tab with its own progress and a gold star when complete. Every item is a card: the real model in a little
-- viewport with its rarity colour on top, its name and best stars; items you have not found yet are black silhouettes with "???"
-- so you can see what is still out there. Golden finds get a gold foil border. The old template pieces (grid, prev/next) are hidden.
local Skin = require(Config:WaitForChild("UiSkin"))
local SC = Skin.COLORS
local CARD_W, CARD_H, CARD_GAP = 126, 112, 8
local BOOK_W, BOOK_H = 780, 478
local RAIL_W = 192

local ui: { rail: ScrollingFrame, cards: Frame, progressLabel: TextLabel, progressFill: Frame, tabs: { [number]: TextButton }, footer: TextLabel }? = nil

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local object = Instance.new(className)
	for key, value in props do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function round(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function buildLayout(book: Frame)
	if ui then
		return
	end
	for _, name in { "PageLabel", "PrevButton", "NextButton", "Grid" } do
		local old = book:FindFirstChild(name)
		if old and old:IsA("GuiObject") then
			old.Visible = false
		end
	end
	book.Size = UDim2.fromOffset(BOOK_W, BOOK_H)
	local title = book:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Size = UDim2.new(0, 330, 0, 34)
	end

	-- overall progress, top right, beside the title
	local progressLabel = make("TextLabel", {
		Name = "Progress", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 8), Size = UDim2.fromOffset(240, 18),
		FontFace = Skin.FONT_TITLE, TextSize = 16, TextColor3 = SC.accent, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	}, book)
	local track = make("Frame", {
		Name = "ProgressTrack", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 30), Size = UDim2.fromOffset(240, 10),
		BackgroundColor3 = Color3.fromRGB(26, 15, 8), BorderSizePixel = 0,
	}, book)
	round(track, 5)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = SC.accent, BorderSizePixel = 0 }, track)
	round(fill, 5)

	-- the tab rail
	local rail = make("ScrollingFrame", {
		Name = "Rail", Position = UDim2.fromOffset(14, 62), Size = UDim2.fromOffset(RAIL_W, BOOK_H - 76), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = SC.accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, book)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rail)

	-- the cards: 4 x 3
	local cards = make("Frame", {
		Name = "Cards", Position = UDim2.fromOffset(RAIL_W + 28, 62), Size = UDim2.fromOffset(BOOK_W - RAIL_W - 42, BOOK_H - 110), BackgroundTransparency = 1,
	}, book)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, cards)
	local footer = make("TextLabel", {
		Name = "Footer", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -10), Size = UDim2.fromOffset(BOOK_W - RAIL_W - 42, 22),
		BackgroundTransparency = 1, FontFace = Skin.FONT_BODY, TextSize = 14, TextColor3 = SC.textDim, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	}, book)
	ui = { rail = rail, cards = cards, progressLabel = progressLabel, progressFill = fill, tabs = {}, footer = footer }
end

-- A tab for one page: tier name, found / total, a small bar and a gold star once the page is complete.
local function drawTabs(collection)
	local rail = (ui :: any).rail
	for _, child in rail:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for index, page in pages do
		local found = countFound(page.items, collection)
		local complete = found == #page.items
		local selected = index == pageIndex
		local tab = make("TextButton", {
			Name = "Tab" .. index, LayoutOrder = index, Size = UDim2.new(1, -6, 0, 50), AutoButtonColor = false, Text = "",
			BackgroundColor3 = if selected then Color3.fromRGB(122, 82, 54) else SC.walnutLight, BackgroundTransparency = if selected then 0 else 0.25,
		}, rail)
		round(tab, 12)
		make("UIStroke", {
			Color = if selected then SC.accent else SC.ink, Thickness = if selected then 2.5 else 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Transparency = if selected then 0 else 0.4,
		}, tab)
		-- a tier colour stripe on the left edge
		local tierColor = if complete then SC.accent else UiTheme.rarityColor(page.items[#page.items] and page.items[#page.items].rarity)
		local stripe = make("Frame", { Position = UDim2.fromOffset(6, 8), Size = UDim2.new(0, 5, 1, -16), BackgroundColor3 = tierColor, BorderSizePixel = 0 }, tab)
		round(stripe, 3)
		make("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 5), Size = UDim2.new(1, -52, 0, 20), FontFace = Skin.FONT_TITLE, TextSize = 16,
			TextColor3 = if selected then SC.accent else SC.cream, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = string.upper(page.name),
		}, tab)
		make("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 26), Size = UDim2.new(1, -52, 0, 14), FontFace = Skin.FONT_BODY, TextSize = 12,
			TextColor3 = SC.textDim, TextXAlignment = Enum.TextXAlignment.Left, Text = `{found} of {#page.items} found`,
		}, tab)
		local bar = make("Frame", { Position = UDim2.new(0, 20, 1, -8), Size = UDim2.new(1, -34, 0, 4), BackgroundColor3 = Color3.fromRGB(26, 15, 8), BorderSizePixel = 0 }, tab)
		round(bar, 2)
		local barFill = make("Frame", { Size = UDim2.fromScale(found / math.max(#page.items, 1), 1), BackgroundColor3 = tierColor, BorderSizePixel = 0 }, bar)
		round(barFill, 2)
		if complete then
			make("TextLabel", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, TextSize = 18, Text = "⭐",
			}, tab)
		end
		tab.Activated:Connect(function()
			if pageIndex ~= index then
				pageIndex = index
				CollectionController.Refresh()
			end
		end)
	end
end

-- One item card. Found: the model, rarity colour, name, stars. Not found: a black silhouette and "???".
local function drawCard(parent: Instance, order: number, def, entry)
	local found = type(entry) == "table" and entry.found == true
	local golden = found and entry.golden == true
	local stars = if found and type(entry.bestStars) == "number" then entry.bestStars else 0
	local color = UiTheme.rarityColor(def.rarity)
	local card = make("Frame", { Name = def.id, LayoutOrder = order, BackgroundColor3 = if found then SC.walnutLight else Color3.fromRGB(50, 34, 24), BorderSizePixel = 0 }, parent)
	round(card, 12)
	make("UIStroke", {
		Color = if golden then SC.accent else if found then color else Color3.fromRGB(96, 76, 62), Thickness = if golden then 3 else 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	-- rarity band across the top
	local band = make("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = if found then color else Color3.fromRGB(96, 76, 62), BorderSizePixel = 0, ZIndex = 2 }, card)
	round(band, 3)
	-- the model
	local stage = make("Frame", { Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 0, 62), BackgroundColor3 = Color3.fromRGB(34, 22, 15), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, card)
	round(stage, 8)
	local viewport = Unboxing.ItemViewport(stage, def.id)
	if viewport then
		viewport.ZIndex = 3
		if not found then
			-- a silhouette: every part dark and plain, no textures
			viewport.Ambient = Color3.fromRGB(10, 8, 6)
			viewport.LightColor = Color3.fromRGB(40, 30, 24)
			for _, d in viewport:GetDescendants() do
				if d:IsA("BasePart") then
					d.Color = Color3.fromRGB(18, 12, 9)
					d.Material = Enum.Material.SmoothPlastic
					if d:IsA("MeshPart") then
						d.TextureID = ""
					end
				elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
					d:Destroy()
				end
			end
		end
	end
	if not found then
		make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), FontFace = Skin.FONT_TITLE, TextSize = 30, TextColor3 = Color3.fromRGB(150, 122, 100), Text = "?", ZIndex = 5 }, stage)
	end
	make("TextLabel", {
		Position = UDim2.fromOffset(6, 72), Size = UDim2.new(1, -12, 0, 18), BackgroundTransparency = 1, FontFace = Skin.FONT_TITLE, TextSize = 14,
		TextColor3 = if found then SC.cream else Color3.fromRGB(150, 122, 100), TextTruncate = Enum.TextTruncate.AtEnd, Text = if found then def.name else "???",
	}, card)
	make("TextLabel", {
		Position = UDim2.fromOffset(6, 90), Size = UDim2.new(1, -12, 0, 16), BackgroundTransparency = 1, FontFace = Skin.FONT_TEXT, TextSize = 13,
		TextColor3 = if not found then Color3.fromRGB(120, 98, 82) elseif stars > 0 then SC.accent else color,
		Text = if not found then def.rarity elseif stars > 0 then starsText(stars) else "Found",
	}, card)
	if golden then
		make("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 0, 8), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, TextSize = 16, Text = "🌟", ZIndex = 6 }, card)
	end
end

local function render()
	if collectionGui == nil or #pages == 0 then
		return
	end
	local book = collectionGui.Book
	buildLayout(book)
	local layout = ui :: any
	local collection = ClientState.Get("collection") or {}
	local page = pages[pageIndex]

	for _, child in layout.cards:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, def in page.items do
		drawCard(layout.cards, index, def, collection[def.id])
	end
	drawTabs(collection)

	local total, totalFound = 0, 0
	for _, p in pages do
		total += #p.items
		totalFound += countFound(p.items, collection)
	end
	book.Title.Text = "📖 COLLECTION BOOK"
	layout.progressLabel.Text = `{totalFound} / {total} found · {math.floor(100 * totalFound / math.max(total, 1))}%`
	layout.progressFill.Size = UDim2.fromScale(totalFound / math.max(total, 1), 1)
	layout.footer.Text = `{page.name} · {countFound(page.items, collection)} of {#page.items} found`
end

function CollectionController.Refresh()
	render()
end

function CollectionController.IsOpen(): boolean
	return collectionGui ~= nil and collectionGui.Book.Visible
end

function CollectionController.Close()
	if collectionGui then
		collectionGui.Book.Visible = false
	end
end

function CollectionController.Open()
	if collectionGui == nil then
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return -- finish the reveal first
	end
	local inventory = others and others.InventoryController
	if inventory and inventory.Close then
		inventory.Close()
	end
	local shop = others and others.ShopController
	if shop and shop.CloseAll then
		shop.CloseAll()
	end
	local settings = others and others.SettingsController
	if settings and settings.Close then
		settings.Close()
	end
	render()
	collectionGui.Book.Visible = true
	log("opened on page", pageIndex)
end

local function turnPage(step: number)
	pageIndex = math.clamp(pageIndex + step, 1, math.max(#pages, 1))
	render()
end

-- One window at a time: if any other window opens, the book steps aside (no changes needed in those controllers).
local function closeWhenOtherOpens(playerGui: Instance)
	local watched = { { "Inventory", "Window" }, { "Supply", "Window" }, { "Upgrades", "Window" }, { "Discovery", "Card" }, { "Settings", "Window" } }
	for _, path in watched do
		local screen = playerGui:FindFirstChild(path[1])
		local window = screen and screen:FindFirstChild(path[2])
		if window and window:IsA("GuiObject") then
			window:GetPropertyChangedSignal("Visible"):Connect(function()
				if window.Visible then
					CollectionController.Close()
				end
			end)
		end
	end
end

function CollectionController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function CollectionController.Start()
	log("Start")
	buildPages()
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		collectionGui = playerGui:WaitForChild("Collection", 10) :: ScreenGui?
		if collectionGui == nil then
			warn("[CollectionController] PlayerGui.Collection not found: is StarterGui.Collection missing?")
			return
		end
		local book = collectionGui.Book
		-- shrink on short / narrow screens (phones), never grow
		local fit = Instance.new("UIScale")
		fit.Name = "FitScale"
		fit.Parent = book
		local function refit()
			local camera = workspace.CurrentCamera
			if camera then
				local view = camera.ViewportSize
				fit.Scale = math.clamp(math.min((view.Y - 24) / BOOK_H, (view.X - 16) / BOOK_W), 0.5, 1)
			end
		end
		refit()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
		end
		book.CloseButton.Activated:Connect(CollectionController.Close)
		book.PrevButton.Activated:Connect(function()
			turnPage(-1)
		end)
		book.NextButton.Activated:Connect(function()
			turnPage(1)
		end)
		-- New finds and better stars arrive as StateChanged("collection.<ItemId>...").
		ClientState.OnChanged("collection", function()
			if CollectionController.IsOpen() then
				render()
			end
		end)

		local hud = playerGui:WaitForChild("HUD", 10)
		local hudButton = hud and hud:FindFirstChild("LeftButtons") and hud.LeftButtons:FindFirstChild("Collection")
		if hudButton then
			hudButton.Activated:Connect(function()
				if CollectionController.IsOpen() then
					CollectionController.Close()
				else
					CollectionController.Open()
				end
			end)
		end
		closeWhenOtherOpens(playerGui)
		log(`ready: {#pages} pages`)
	end)
end

return CollectionController
