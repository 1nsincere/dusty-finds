-- ShopController.luau
-- Purpose: Supply Board screen: lists the crates from Config/Crates with price, item count and odds, and
-- asks the server to buy one (RequestBuyCrate). Opens from my plot's SupplyBoard prompt or the HUD 📦 button.
-- Look (Sean, 2026-11-25): the Figma "Window · Supply (Warehouse)" (94:7998, 560 x 325): two crate cards a row (scrolls
-- down for more), each with the crate's real 3D model (ReplicatedStorage.Assets.Boxes.<boxModel>) turning slowly on a
-- glow, name, item count, level chip, ODDS bars per rarity, the special-find chances, and a chunky Buy button.
-- The server rolls, charges and refuses (toasts come from HudController); this screen only shows and requests.
-- Also the Upgrades screen (HUD 🔨): cards per upgrade in Config/Upgrades with level dots, next-level effect,
-- cost or lock reason, and RequestBuyUpgrade. The server re-checks all 5 rules (UpgradeService).
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, WindowKit, Shared.Remotes, Shared.Config (Crates, Rarities,
-- Upgrades, Economy, UiSkin), ReplicatedStorage.Assets.Boxes, StarterGui.Supply + StarterGui.Upgrades + HUD.LeftButtons.{Supply,Upgrades}
-- (UI contract, docs/03 §8), Workspace.Plots (OwnerUserId attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local WindowKit = require(script.Parent.Parent:WaitForChild("WindowKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Crates = require(Shared:WaitForChild("Config"):WaitForChild("Crates"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local DecorStock = require(Shared:WaitForChild("DecorStock"))
local DecorRooms = require(Shared:WaitForChild("Config"):WaitForChild("DecorRooms"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))

local ShopController = {}
local DEBUG = true

local BUY_COOLDOWN = 1.5 -- seconds the button shows "Ordering…" (also stops double taps)

-- Supply window, Figma "Window · Supply (Warehouse)": numbers are the 560 x 325 design in px (WindowKit.Fit scales it).
local SUPPLY_DESIGN = Vector2.new(560, 325)
local CRATE_CARD = Vector2.new(256, 254) -- + a 3 px ink lip under it
local INK = Color3.fromRGB(43, 27, 20)
local WALNUT_LIGHT = Color3.fromRGB(90, 59, 40)
local CREAM = Color3.fromRGB(255, 241, 214)
local GOLD = Color3.fromRGB(255, 200, 58)
local CHIP_OPEN = Color3.fromRGB(70, 101, 122) -- "Unlocked at Lv 5+"
local CHIP_LOCKED = Color3.fromRGB(150, 64, 48) -- "Locked · Lv 10"
local GLOW_IMAGE = "rbxassetid://93831669035461" -- the soft glow the Discovery card and Inventory use
-- glow colour behind each crate, cheapest first (Figma: Starter warm, Flea Market blue)
local CRATE_GLOWS = {
	Color3.fromRGB(255, 150, 60), Color3.fromRGB(95, 209, 107), Color3.fromRGB(77, 163, 255),
	Color3.fromRGB(176, 112, 255), Color3.fromRGB(255, 200, 58),
}
-- the design's odds colours (dot + bar)
local ODDS_COLORS = {
	Common = Color3.fromRGB(207, 199, 184), Uncommon = Color3.fromRGB(95, 209, 107), Rare = Color3.fromRGB(77, 163, 255),
	Epic = Color3.fromRGB(176, 112, 255), Legendary = Color3.fromRGB(255, 200, 58),
}
-- special finds per item (Economy.<key>[crateId]), shown under the odds so nothing is hidden (docs/01 J3)
local SPECIALS = { { "RelicChance", "Relic" }, { "MythicChance", "Mythic" }, { "SecretChance", "Secret" }, { "TimeCapsuleChance", "Time Capsule" } }
local FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_BOLD = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local FONT_BODY = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Regular)

-- Upgrades screen
local UPGRADE_TABS = { "Tools", "Shop", "Decor", "Expansions" } -- = `tab` field in Config/Upgrades
-- Tabs listed here show "Coming soon" instead of Buy (nobody should pay for something not built yet).
-- Expansions unlocked 2026-11-16: PlotService now clones ServerStorage.Expansions.{BackRoom,Showroom} into the plot.
local COMING_SOON_TABS: { [string]: boolean } = {}
local UPGRADE_ICONS = {
	CleaningBrush = "🧽", RepairToolkit = "🧰", Polisher = "✨",
	-- Only older emoji: Roblox's emoji font draws newer ones (e.g. 🪴 🪧) as empty squares.
	DisplayShelves = "🗄️", StorageRacks = "📦", ShopSign = "📢",
	PottedPlants = "🌿", Rug = "🟫", WallPosters = "🖼️", PendantLamps = "💡", NeonSign = "🌟",
	FishTank = "🐠", Fountain = "⛲",
	-- Cozy Living and Kitchen Nook decor (older emoji only: newer ones draw as empty squares)
	CozyRug = "🟫", CozyPlant = "🌿", CozyLamp = "💡", CozyTeaTable = "🍵", CozyTable = "🎋", CozyChair = "🐈", CozyBookcase = "📚", CozyLoveseat = "🛋️",
	KitchenFruit = "🍎", KitchenBanga = "🏺", KitchenJarShelf = "🍯", KitchenPotRack = "🍳", KitchenStove = "🔥", KitchenAparador = "🗄️", KitchenDining = "🍽️", KitchenCart = "🍞",
	BackRoom = "🚪", Showroom = "🏛️",
}

local player = Players.LocalPlayer
local others = nil
local supply: ScreenGui? = nil
local cards: { [string]: Frame } = {} -- [crateId] = card
local ordering: { [string]: boolean } = {}
local crateSpins: { (number) -> () } = {} -- turns each crate model a little every frame while the window is open
local spinAngle = 0.6
local upgradesGui: ScreenGui? = nil
local currentUpgradeTab = "Tools"
local currentDecorRoom: string? = nil -- set while the window is open at a decor room counter: only that room's pieces show (Config/DecorRooms)
local stallMode = false -- true = opened at a decor counter (only the Decor tab); false = the normal Upgrades window (no Decor tab)
local buyingUpgrade: { [string]: boolean } = {}

local function log(...)
	if DEBUG then
		print("[ShopController]", ...)
	end
end

-- Crates the player can buy here: everything with a price (Free Delivery is claimed at the door, not bought).
local function buyableCrates()
	local list = {}
	for _, crate in Crates do
		if crate.price > 0 then
			table.insert(list, crate)
		end
	end
	table.sort(list, function(a, b)
		return a.price < b.price
	end)
	return list
end

local function rarityOrder()
	local list = {}
	for id, def in Rarities do
		table.insert(list, { id = id, index = def.index })
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

-- Updates every Buy button for my current level (cash is checked by the server, which sends a toast).
local function refreshButtons()
	local level = ClientState.Get("level") or 1
	for crateId, card in cards do
		local crate = Crates[crateId]
		local button = card.BuyButton :: TextButton
		local locked = level < crate.requiredLevel
		local chip = card:FindFirstChild("LevelChip") :: TextLabel?
		if chip then
			chip.Text = if locked then `Locked · Lv {crate.requiredLevel}` else `Unlocked at Lv {crate.requiredLevel}+`
			chip.BackgroundColor3 = if locked then CHIP_LOCKED else CHIP_OPEN
		end
		if ordering[crateId] then
			continue
		end
		if locked then
			WindowKit.Chunky(button, WindowKit.BUTTON.Disabled, 16, 13)
			button.Text = `Reach Lv {crate.requiredLevel}`
		else
			WindowKit.Chunky(button, WindowKit.BUTTON.Primary, 16, 13)
			button.Text = `Buy  {UiTheme.formatCash(crate.price)}`
		end
	end
end

local function onBuy(crateId: string)
	local crate = Crates[crateId]
	local level = ClientState.Get("level") or 1
	if ordering[crateId] or level < crate.requiredLevel then
		return
	end
	ordering[crateId] = true
	local button = cards[crateId].BuyButton :: TextButton
	button.Text = "Ordering…" -- instant feedback (docs/01 J4); the box appearing at the door is the real confirmation
	button.BackgroundColor3 = UiTheme.Teal
	Remotes.RequestBuyCrate:FireServer(crateId)
	log("asked to buy", crateId)
	task.delay(BUY_COOLDOWN, function()
		ordering[crateId] = nil
		refreshButtons()
	end)
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function outline(parent: Instance, color: Color3, thickness: number)
	new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1, TextColor3 = CREAM, FontFace = FONT_BOLD, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- "0.2%", "1.5%", "0.08%"
local function percentText(p: number): string
	return string.format("%g%%", math.round(p * 100) / 100)
end

-- The crate's real model (ReplicatedStorage.Assets.Boxes.<boxModel>, the one that arrives at the door) in a viewport.
-- Returns a function(angle) that turns the camera round it, or nil (then the crate glyph is shown).
local function crateArt(holder: GuiObject, boxModel: string?): ((number) -> ())?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local boxes = assets and assets:FindFirstChild("Boxes")
	local template = boxes and ((boxModel and boxes:FindFirstChild(boxModel)) or boxes:FindFirstChild("Box"))
	if template == nil then
		new("ImageLabel", { BackgroundTransparency = 1, Image = UiSkin.Art("Crate"), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = holder.ZIndex }, holder)
		return nil
	end
	local vp = new("ViewportFrame", {
		Name = "Model", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = holder.ZIndex,
		LightColor = Color3.fromRGB(255, 240, 215), Ambient = Color3.fromRGB(150, 130, 118), LightDirection = Vector3.new(-0.6, -1, -0.5),
	}, holder)
	local model = template:Clone()
	if not model:IsA("Model") then
		local wrap = Instance.new("Model")
		model.Parent = wrap
		model = wrap
	end
	-- only the look: no prompts or scripts inside the picture
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BaseScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = new("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	local dist = math.max(size.X, size.Y, size.Z) * 2.4
	return function(angle: number)
		local eye = cf.Position + Vector3.new(math.sin(angle) * dist, size.Y * 0.55 + dist * 0.25, math.cos(angle) * dist)
		cam.CFrame = CFrame.lookAt(eye, cf.Position)
	end
end

-- One crate card (Figma "Crate card"): positions are px inside the 256 x 254 card.
local function buildCrateCard(crate, order: number, rarities, parent: Instance): Frame
	local z = (parent :: any).ZIndex + 1
	local cell = new("Frame", { Name = crate.id, LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.fromOffset(CRATE_CARD.X, CRATE_CARD.Y + 3), ZIndex = z }, parent)
	local lip = new("Frame", { Name = "Lip", BackgroundColor3 = INK, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(CRATE_CARD.X, CRATE_CARD.Y), ZIndex = z }, cell)
	round(lip, 16)
	local card = new("Frame", { Name = "Card", BackgroundColor3 = WALNUT_LIGHT, BorderSizePixel = 0, Size = UDim2.fromOffset(CRATE_CARD.X, CRATE_CARD.Y), ZIndex = z + 1 }, cell)
	round(card, 16)
	outline(card, INK, 2.5)
	card.ClipsDescendants = true -- the big soft glow stays inside the card
	local cz = z + 2

	-- art: the glow, and the crate's model turning on it
	new("ImageLabel", {
		Name = "Glow", BackgroundTransparency = 1, Image = GLOW_IMAGE, ImageColor3 = CRATE_GLOWS[(order - 1) % #CRATE_GLOWS + 1],
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(63, 44), Size = UDim2.fromOffset(150, 150), ZIndex = cz,
	}, card)
	-- the glow image alone is too faint on walnut: two soft tinted discs under it make the spotlight (Figma "Crate glow")
	for i, disc in { { 98, 0.84 }, { 72, 0.76 } } do
		local spot = new("Frame", {
			Name = "Spot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(63, 44), Size = UDim2.fromOffset(disc[1], disc[1]),
			BackgroundColor3 = CRATE_GLOWS[(order - 1) % #CRATE_GLOWS + 1], BackgroundTransparency = disc[2], BorderSizePixel = 0, ZIndex = cz,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, spot)
	end
	local art = new("Frame", { Name = "Art", BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 2), Size = UDim2.fromOffset(78, 78), ZIndex = cz + 1 }, card)
	local spin = crateArt(art, crate.boxModel)
	if spin then
		local offset = order * 0.9 -- so the crates don't all face the same way
		table.insert(crateSpins, function(angle)
			spin(angle + offset)
		end)
		spin(spinAngle + offset)
	end

	text(card, { Name = "CrateName", Text = crate.name, FontFace = FONT_TITLE, TextSize = 19, TextWrapped = true, Position = UDim2.fromOffset(104, 8), Size = UDim2.fromOffset(146, 26), ZIndex = cz, TextScaled = true })
	local nameLabel = card.CrateName :: TextLabel
	new("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 12 }, nameLabel)
	text(card, {
		Name = "Info", Text = `{crate.itemCount} items · Tier {crate.tier} finds`, FontFace = FONT_BODY, TextSize = 11.5, TextTransparency = 0.15,
		Position = UDim2.fromOffset(104, 34), Size = UDim2.fromOffset(146, 16), ZIndex = cz,
	})
	if crate.requiredLevel > 1 then
		local chip = text(card, {
			Name = "LevelChip", Text = "", TextSize = 10.5, BackgroundTransparency = 0, BackgroundColor3 = CHIP_OPEN, AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(104, 52), Size = UDim2.fromOffset(0, 18), ZIndex = cz,
		})
		round(chip, 9)
		outline(chip, INK, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
	end

	-- ODDS: dot, rarity, bar (longest = the crate's most likely rarity, like the design), percent
	text(card, { Name = "OddsTitle", Text = "ODDS", TextSize = 10.5, TextColor3 = GOLD, Position = UDim2.fromOffset(14, 78), Size = UDim2.fromOffset(60, 14), ZIndex = cz })
	local rows = {}
	local most = 0
	for _, rarity in rarities do
		local percent = crate.odds[rarity.id] or 0
		if percent > 0 then
			table.insert(rows, { id = rarity.id, percent = percent })
			most = math.max(most, percent)
		end
	end
	for i, row in rows do
		local y = 96 + (i - 1) * 17
		local color = ODDS_COLORS[row.id] or UiTheme.rarityColor(row.id)
		local dot = new("Frame", { Name = "Dot_" .. row.id, BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(9, 9), ZIndex = cz }, card)
		round(dot, 5)
		outline(dot, INK, 1.5)
		text(card, { Name = "Rarity_" .. row.id, Text = row.id, Position = UDim2.fromOffset(28, y - 3), Size = UDim2.fromOffset(70, 15), ZIndex = cz })
		local track = new("Frame", { Name = "Track_" .. row.id, BackgroundColor3 = INK, BorderSizePixel = 0, Position = UDim2.fromOffset(100, y), Size = UDim2.fromOffset(100, 9), ZIndex = cz }, card)
		round(track, 5)
		local fill = new("Frame", {
			Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
			Size = UDim2.fromOffset(math.max(3, math.round(98 * row.percent / most)), 7), ZIndex = cz + 1,
		}, track)
		round(fill, 4)
		text(card, {
			Name = "Percent_" .. row.id, Text = percentText(row.percent), FontFace = FONT_TITLE, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(206, y - 4), Size = UDim2.fromOffset(36, 16), ZIndex = cz,
		})
	end

	-- special finds (per item): Relic / Mythic / Secret / Time Capsule, when this crate has them
	local specials = {}
	for _, entry in SPECIALS do
		local chances = Economy[entry[1]]
		local chance = type(chances) == "table" and chances[crate.id] or nil
		if type(chance) == "number" and chance > 0 then
			table.insert(specials, `{entry[2]} {percentText(chance * 100)}`)
		end
	end
	if #specials > 0 then
		local line = text(card, {
			Name = "Specials", Text = "Per item: " .. table.concat(specials, " · "), FontFace = FONT_BODY, TextColor3 = GOLD, TextScaled = true,
			Position = UDim2.fromOffset(14, 178), Size = UDim2.fromOffset(228, 13), ZIndex = cz,
		})
		new("UITextSizeConstraint", { MaxTextSize = 10.5, MinTextSize = 7 }, line)
	end

	local buy = new("TextButton", {
		Name = "BuyButton", Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(180, 38),
		BackgroundColor3 = WindowKit.BUTTON.Primary.face, ZIndex = cz,
	}, card)
	WindowKit.Chunky(buy, WindowKit.BUTTON.Primary, 16, 13)
	buy.Activated:Connect(function()
		onBuy(crate.id)
	end)
	return card
end

-- The Figma window: shell size, title, cash pill, close button, a 2-column scrolling list of cards.
local function applyFigmaSupply(window: Frame)
	window:SetAttribute("DfFigma", true) -- WindowKit: draw only the shell, this controller does the rest
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(SUPPLY_DESIGN.X, SUPPLY_DESIGN.Y)
	WindowKit.Fit(window, SUPPLY_DESIGN.Y)

	local title = window:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = "WAREHOUSE SUPPLY"
	end
	local close = window.CloseButton :: GuiButton
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 5)
	close.Size = UDim2.fromOffset(38, 38)

	-- cash pill: dark, coin glyph, gold amount, grows to the left from just beside the close button
	local cash = window:FindFirstChild("Cash")
	if cash and cash:IsA("TextLabel") then
		for _, c in cash:GetChildren() do
			if c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIPadding") or c:IsA("UITextSizeConstraint") or c:IsA("UIGradient") then
				c:Destroy()
			end
		end
		cash:SetAttribute("DfCash", true) -- Start's updateCash: plain amount, no 💰 (the glyph is an image)
		cash.AnchorPoint = Vector2.new(1, 0)
		cash.Position = UDim2.new(1, -56, 0, 7)
		cash.Size = UDim2.fromOffset(0, 30)
		cash.AutomaticSize = Enum.AutomaticSize.X
		cash.BackgroundTransparency = 0
		cash.BackgroundColor3 = INK
		cash.TextScaled = false
		cash.FontFace = FONT_TITLE
		cash.TextSize = 18
		cash.TextColor3 = GOLD
		round(cash, 16)
		outline(cash, WALNUT_LIGHT, 2.5)
		new("UIPadding", { PaddingLeft = UDim.new(0, 36), PaddingRight = UDim.new(0, 14) }, cash)
		new("ImageLabel", {
			Name = "Coin", BackgroundTransparency = 1, Image = UiSkin.Art("Cash"), ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0, -28, 0.5, -12), Size = UDim2.fromOffset(24, 24), ZIndex = cash.ZIndex + 1,
		}, cash)
	end

	local list = window.List :: ScrollingFrame
	list.Position = UDim2.fromOffset(12, 50)
	list.Size = UDim2.fromOffset(SUPPLY_DESIGN.X - 24, 266)
	list.BackgroundTransparency = 1
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = GOLD
	for _, c in list:GetChildren() do
		if c:IsA("UIListLayout") or c:IsA("UIGridLayout") or c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CRATE_CARD.X, CRATE_CARD.Y + 3), CellPadding = UDim2.fromOffset(14, 12),
		SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 2,
	}, list)
	new("UIPadding", { PaddingLeft = UDim.new(0, 1), PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 6) }, list)

	-- turn the crates while the window is open (nothing runs while it's closed)
	RunService.RenderStepped:Connect(function(dt)
		if window.Visible and #crateSpins > 0 then
			spinAngle += dt * 0.6
			for _, spin in crateSpins do
				spin(spinAngle)
			end
		end
	end)
end

local function buildCards()
	if supply == nil then
		return
	end
	local list = supply.Window.List
	local rarities = rarityOrder()
	for order, crate in buyableCrates() do
		cards[crate.id] = buildCrateCard(crate, order, rarities, list)
	end
	refreshButtons()
end

-- ===== Open / close (only one modal at a time, docs/01 J4) =====

function ShopController.IsSupplyOpen(): boolean
	return supply ~= nil and supply.Window.Visible
end

-- Crates are sold at the Supply Warehouse (south end of Workshop Lane), so restocking means a walk. The server checks the same
-- distance on RequestBuyCrate (Economy.SupplyMaxStuds); this client check only explains it instead of opening an empty window.
local function distanceToSupplyCounter(): number
	local env = workspace:FindFirstChild("Environment")
	local districts = env and env:FindFirstChild("Districts")
	local warehouse = districts and districts:FindFirstChild("Warehouse")
	local counter = warehouse and warehouse:FindFirstChild("SupplyCounter")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if counter == nil or root == nil or not counter:IsA("BasePart") or not root:IsA("BasePart") then
		return math.huge
	end
	return (counter.Position - root.Position).Magnitude
end

function ShopController.OpenSupply()
	if supply == nil then
		return
	end
	if distanceToSupplyCounter() > Economy.SupplyMaxStuds then
		local hud = others and others.HudController
		if hud and hud.Notify then
			hud.Notify("Info", "📦 Crates are sold at the Supply Warehouse, at the south end of Workshop Lane.")
		end
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return -- finish the reveal first
	end
	local inventory = others and others.InventoryController
	if inventory and inventory.Close then
		inventory.Close() -- one modal at a time (docs/01 J4)
	end
	if upgradesGui then
		upgradesGui.Window.Visible = false
	end
	if next(cards) == nil then
		buildCards()
	end
	refreshButtons()
	supply.Window.Visible = true
	log("Supply opened")
end

function ShopController.CloseSupply()
	if supply then
		supply.Window.Visible = false
	end
end

-- ===== Upgrades screen =====

local function ownedLevel(upgradeId: string): number
	local level = ClientState.Get("upgrades." .. upgradeId)
	return if type(level) == "number" then level else 0
end

-- What the NEXT level gives (or the current one when maxed), written for players. Numbers come from Config.
local function effectText(def, owned: number): string
	local nextLevel = math.min(owned + 1, def.maxLevel)
	local effect = def.effect or {}
	local description = def.description or ""

	-- "Scrub %d%% faster": fill in the percent from the first ...SpeedMult value of the next level.
	if string.find(description, "%d", 1, true) then
		for key, values in effect do
			if string.sub(key, -9) == "SpeedMult" and type(values) == "table" and values[nextLevel] then
				return string.format(description, math.floor((values[nextLevel] - 1) * 100 + 0.5))
			end
		end
	end
	if type(effect.displaySlots) == "table" then
		local now = if owned > 0 then effect.displaySlots[owned] else Economy.StartingDisplaySlots
		return if owned >= def.maxLevel then `Display slots: {now}` else `Display slots {now} → {effect.displaySlots[nextLevel]}`
	end
	if type(effect.inventoryCapacity) == "table" then
		local now = if owned > 0 then effect.inventoryCapacity[owned] else Economy.StartingInventoryCapacity
		return if owned >= def.maxLevel then `Storage: {now}` else `Storage {now} → {effect.inventoryCapacity[nextLevel]}`
	end
	-- Decor: ratingPoints is the TOTAL at each level, so the gain is next minus current.
	if type(effect.ratingPoints) == "table" then
		if owned >= def.maxLevel then
			return `{description} · {effect.ratingPoints[owned] or 0} rating` -- maxed: show what you have
		end
		local gain = (effect.ratingPoints[nextLevel] or 0) - (if owned > 0 then effect.ratingPoints[owned] or 0 else 0)
		return `{description} · +{gain} rating`
	end
	if type(effect.ratingPoints) == "number" then
		return `{description} · +{effect.ratingPoints} rating`
	end
	return (string.gsub(description, "%%d%%%%", "more")) -- never show a raw "%d"
end

-- Button text + whether it can be pressed. Same order as UpgradeService.BuyUpgrade so the reason matches.
local function upgradeButtonState(def, owned: number): (string, boolean, boolean)
	if owned >= def.maxLevel then
		return "MAX", false, false
	end
	if def.comingSoon then
		return "Coming soon", false, false -- one upgrade switched off (Config/Upgrades comingSoon = true), whatever the player's level
	end
	if DecorStock.isStocked(def) and not DecorStock.inStock(DecorStock.restockIndex(workspace:GetServerTimeNow()), def.id) then
		return "Out of stock", false, false -- decor is sold from the rotating stock: the nicer the piece, the rarer (Shared/DecorStock)
	end
	local nextLevel = owned + 1
	local level = ClientState.Get("level") or 1
	if level < def.requiredLevel[nextLevel] then
		return `Reach Lv {def.requiredLevel[nextLevel]}`, false, false
	end
	if def.requires and ownedLevel(def.requires) < 1 then
		local needed = Upgrades[def.requires]
		return `Needs {needed and needed.name or def.requires}`, false, false
	end
	if COMING_SOON_TABS[def.tab] then
		return "Coming soon", false, false
	end
	local cost = def.costs[nextLevel]
	local affordable = (ClientState.Get("cash") or 0) >= cost
	return UiTheme.formatCash(cost), true, affordable
end

local function upgradesInTab(tab: string)
	local list = {}
	for _, def in Upgrades do
		if def.tab == tab and (tab ~= DecorRooms.TAB or currentDecorRoom == nil or def.room == currentDecorRoom) then
			table.insert(list, def)
		end
	end
	-- Cheapest first-level cost first, so the list reads as a path from easy to big goals.
	-- (decor from the stock: pieces that are in stock now come first)
	local stockIndex = DecorStock.restockIndex(workspace:GetServerTimeNow())
	table.sort(list, function(a, b)
		local sa = if DecorStock.isStocked(a) and DecorStock.inStock(stockIndex, a.id) then 0 else 1
		local sb = if DecorStock.isStocked(b) and DecorStock.inStock(stockIndex, b.id) then 0 else 1
		if tab == "Decor" and sa ~= sb then
			return sa < sb
		end
		if a.costs[1] ~= b.costs[1] then
			return a.costs[1] < b.costs[1]
		end
		return a.id < b.id
	end)
	return list
end

local function renderUpgrades()
	if upgradesGui == nil then
		return
	end
	local window = upgradesGui.Window
	local template = upgradesGui.UpgradeTemplate
	for _, child in window.List:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, tab in window.Tabs:GetChildren() do
		if tab:IsA("TextButton") then
			tab.BackgroundColor3 = if tab.Name == currentUpgradeTab then UiTheme.Teal else UiTheme.Disabled
		end
	end

	for order, def in upgradesInTab(currentUpgradeTab) do
		local owned = ownedLevel(def.id)
		local card = template:Clone()
		card.Name = def.id
		card.LayoutOrder = order
		card.Visible = true
		card.Icon.Text = UPGRADE_ICONS[def.id] or "⭐"
		card.Title.Text = def.name
		card.Effect.Text = effectText(def, owned)
		if DecorStock.isStocked(def) and owned < def.maxLevel then
			-- the rarity tells how often it comes into stock; out of stock pieces come back with a later restock
			local inStock = DecorStock.inStock(DecorStock.restockIndex(workspace:GetServerTimeNow()), def.id)
			card.Effect.Text = `{def.rarity} · {if inStock then "in stock" else "out of stock"} · {card.Effect.Text}`
		end

		-- One dot per level; filled = owned. Hide the dots this upgrade doesn't have (decor has 1 or 2).
		for i = 1, 3 do
			local dot = card.Dots:FindFirstChild("Dot" .. i)
			if dot then
				dot.Visible = i <= def.maxLevel
				dot.BackgroundColor3 = if i <= owned then UiTheme.Coral else UiTheme.Disabled
			end
		end

		local text, canPress, affordable = upgradeButtonState(def, owned)
		local button = card.BuyButton :: TextButton
		if buyingUpgrade[def.id] then
			text, canPress = "Buying…", false
		end
		button.Text = text
		button.AutoButtonColor = canPress
		button.BackgroundColor3 = if buyingUpgrade[def.id]
			then UiTheme.Teal
			elseif canPress and affordable then UiTheme.Coral
			elseif canPress then UiTheme.Teal -- unlocked but can't afford yet: the server's toast says so
			else UiTheme.Disabled
		-- "Affordable glow" (docs/01 J3): coral, thicker outline when you can buy it right now.
		card.Glow.Color = if canPress and affordable then UiTheme.Coral else UiTheme.Ink
		card.Glow.Thickness = if canPress and affordable then 4 else 2

		local upgradeId = def.id
		button.Activated:Connect(function()
			local _, pressable = upgradeButtonState(Upgrades[upgradeId], ownedLevel(upgradeId))
			if not pressable or buyingUpgrade[upgradeId] then
				return
			end
			buyingUpgrade[upgradeId] = true
			renderUpgrades() -- "Buying…" right away (docs/01 J4); the 🔨 banner + new level confirm it
			Remotes.RequestBuyUpgrade:FireServer(upgradeId)
			log("asked to buy upgrade", upgradeId)
			task.delay(BUY_COOLDOWN, function()
				buyingUpgrade[upgradeId] = nil
				renderUpgrades()
			end)
		end)
		card.Parent = window.List
	end
end

function ShopController.IsUpgradesOpen(): boolean
	return upgradesGui ~= nil and upgradesGui.Window.Visible
end

-- Which tab buttons show: at a decor counter only the Decor tab, in the normal Upgrades window every tab except Decor.
local function applyTabMode()
	if upgradesGui == nil then
		return
	end
	for _, tabName in UPGRADE_TABS do
		local tab = upgradesGui.Window.Tabs:FindFirstChild(tabName)
		if tab and tab:IsA("GuiObject") then
			if (Economy.ClosedUpgradeTabs or {})[tabName] then
				tab.Visible = false
			elseif stallMode then
				tab.Visible = tabName == DecorRooms.TAB
			else
				tab.Visible = tabName ~= DecorRooms.TAB
			end
		end
	end
end

function ShopController.IsDecorStallOpen(): boolean
	return stallMode and ShopController.IsUpgradesOpen()
end

function ShopController.OpenUpgrades()
	if upgradesGui == nil then
		return
	end
	stallMode, currentDecorRoom = false, nil
	if currentUpgradeTab == DecorRooms.TAB then
		currentUpgradeTab = "Tools"
	end
	applyTabMode()
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return
	end
	local inventory = others and others.InventoryController
	if inventory and inventory.Close then
		inventory.Close()
	end
	ShopController.CloseSupply()
	renderUpgrades()
	upgradesGui.Window.Visible = true
	log("Upgrades opened on", currentUpgradeTab)
end

-- Opens the window at a decor room's counter: only the Decor tab, only that room's pieces (DecorStallController calls this).
function ShopController.OpenDecorStall(room: string)
	if upgradesGui == nil then
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return
	end
	local inventory = others and others.InventoryController
	if inventory and inventory.Close then
		inventory.Close()
	end
	ShopController.CloseSupply()
	stallMode, currentDecorRoom, currentUpgradeTab = true, room, DecorRooms.TAB
	applyTabMode()
	renderUpgrades()
	upgradesGui.Window.Visible = true
	log("Decor counter opened:", room)
end

function ShopController.CloseUpgrades()
	if upgradesGui then
		upgradesGui.Window.Visible = false
	end
end

-- Closes every window this controller owns (other controllers call this to keep one modal open).
function ShopController.CloseAll()
	ShopController.CloseSupply()
	ShopController.CloseUpgrades()
end

local function setUpUpgrades(playerGui: Instance, hud: Instance?)
	upgradesGui = playerGui:WaitForChild("Upgrades", 10) :: ScreenGui?
	if upgradesGui == nil then
		warn("[ShopController] PlayerGui.Upgrades not found: is StarterGui.Upgrades missing?")
		return
	end
	local window = upgradesGui.Window
	window.CloseButton.Activated:Connect(ShopController.CloseUpgrades)
	applyTabMode() -- the normal window has no Decor tab (decor is bought at the counters in the market)
	for _, tabName in UPGRADE_TABS do
		local tab = window.Tabs:FindFirstChild(tabName)
		if tab and tab:IsA("GuiObject") and (Economy.ClosedUpgradeTabs or {})[tabName] then
			tab.Visible = false -- switched off in Config (decor waits for the decor shop): the server refuses it anyway
		elseif tab then
			tab.Activated:Connect(function()
				currentUpgradeTab = tabName
				renderUpgrades()
			end)
		end
	end
	-- Re-draw when anything that changes a card changes (only while open, to keep it cheap).
	local function refreshIfOpen()
		if ShopController.IsUpgradesOpen() then
			renderUpgrades()
		end
	end
	ClientState.OnChanged("upgrades", refreshIfOpen)
	ClientState.OnChanged("cash", refreshIfOpen)
	ClientState.OnChanged("level", refreshIfOpen)

	local hudButton = hud and hud:FindFirstChild("LeftButtons") and hud.LeftButtons:FindFirstChild("Upgrades")
	if hudButton then
		hudButton.Activated:Connect(function()
			if ShopController.IsUpgradesOpen() then
				ShopController.CloseUpgrades()
			else
				ShopController.OpenUpgrades()
			end
		end)
	end
end

-- ===== My plot's Supply Board prompt =====

local function isMine(plot: Instance): boolean
	return plot:GetAttribute("OwnerUserId") == player.UserId
end

-- Every plot has a board; only my own opens my Supply screen. Others' prompts are hidden for me.
local function hookPlot(plot: Instance)
	local board = plot:FindFirstChild("SupplyBoard")
	local prompt = board and board:FindFirstChild("Prompt")
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		return
	end
	local function updateEnabled()
		prompt.Enabled = isMine(plot)
	end
	updateEnabled()
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(updateEnabled)
	prompt.Triggered:Connect(function()
		if isMine(plot) then
			ShopController.OpenSupply()
		end
	end)
end

-- ===== Lifecycle =====

function ShopController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function ShopController.Start()
	log("Start")
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		supply = playerGui:WaitForChild("Supply", 10) :: ScreenGui?
		if supply == nil then
			warn("[ShopController] PlayerGui.Supply not found: is StarterGui.Supply missing?")
			return
		end
		-- load the crate meshes now, so the 3D crates are ready by the time the player walks to the Warehouse
		task.spawn(function()
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			local boxes = assets and assets:FindFirstChild("Boxes")
			if boxes then
				pcall(function()
					ContentProvider:PreloadAsync({ boxes })
				end)
			end
		end)
		applyFigmaSupply(supply.Window)
		-- the cards are built on the first open (OpenSupply): HudSkinController restyles every window once at startup (all
		-- corners 10 px, plain font), which would undo the Figma cards if they already existed
		supply.Window.CloseButton.Activated:Connect(ShopController.CloseSupply)
		ClientState.OnChanged("level", refreshButtons)

		local hud = playerGui:WaitForChild("HUD", 10)
		local hudButton = hud and hud:FindFirstChild("LeftButtons") and hud.LeftButtons:FindFirstChild("Supply")
		if hudButton then
			hudButton.Activated:Connect(function()
				if ShopController.IsSupplyOpen() then
					ShopController.CloseSupply()
				else
					ShopController.OpenSupply()
				end
			end)
		end

		setUpUpgrades(playerGui, hud)

		-- New decor stock arrives every few minutes (Config/Stock.RestockSeconds): refresh the Decor tab when that happens while it is open
		task.spawn(function()
			local lastIndex = DecorStock.restockIndex(workspace:GetServerTimeNow())
			while true do
				task.wait(2)
				local index = DecorStock.restockIndex(workspace:GetServerTimeNow())
				if index ~= lastIndex then
					lastIndex = index
					if ShopController.IsUpgradesOpen() and currentUpgradeTab == "Decor" then
						renderUpgrades()
					end
				end
			end
		end)

		-- Walking away from the Warehouse counter closes the Supply window (a little slack so it doesn't flicker).
		task.spawn(function()
			while true do
				task.wait(0.5)
				if ShopController.IsSupplyOpen() and distanceToSupplyCounter() > Economy.SupplyMaxStuds + 8 then
					ShopController.CloseSupply()
				end
			end
		end)

		-- Cash pill in both title bars: on phones the window covers the HUD money, so show it here too.
		local cashLabels = {}
		for _, screen in { supply, playerGui:FindFirstChild("Upgrades") } do
			local label = screen and screen:FindFirstChild("Window") and screen.Window:FindFirstChild("Cash")
			if label and label:IsA("TextLabel") then
				if not label:GetAttribute("DfCash") then
					label.BackgroundColor3 = UiTheme.Teal
				end
				table.insert(cashLabels, label)
			end
		end
		local function updateCash()
			local amount = UiTheme.formatCash(ClientState.Get("cash") or 0)
			for _, label in cashLabels do
				label.Text = if label:GetAttribute("DfCash") then amount else "💰 " .. amount
			end
		end
		updateCash()
		ClientState.OnChanged("cash", updateCash)

		local plots = workspace:WaitForChild("Plots", 10)
		if plots then
			for _, plot in plots:GetChildren() do
				hookPlot(plot)
			end
		end
		log(`Supply ready: {#buyableCrates()} crates`)
	end)
end

return ShopController
