-- DiscoveryController.luau
-- Purpose: shows my waiting boxes at my plot's DeliveryPoint (client-side, only I see them) and plays the reveal:
-- "Open" on a box asks the server to open each item (RequestOpenBox), and each BoxOpened result is shown on the
-- Discovery card (rarity, name, dots, est. value, NEW!/GOLDEN). The server already rolled the item; we only show it.
-- Also the Free Delivery claim prompt + countdown sign on the same DeliveryPoint (RequestClaimFreeDelivery).
-- Owner: Dev 3 (Sean) UI, Dev 2 (Dwayne) VFX later. Depends on: ClientState, UiTheme, Shared.Remotes,
-- Shared.Config (Items, Rarities, Crates, Economy), Shared.Formulas, StarterGui.Discovery,
-- ReplicatedStorage.Assets.Boxes, Workspace.Plots (OwnerUserId attribute, DeliveryPoint).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Unboxing = require(script.Parent.Parent:WaitForChild("UnboxingKit")) -- the tap-to-open show (before the card)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Items = require(Config:WaitForChild("Items"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Crates = require(Config:WaitForChild("Crates"))
local Economy = require(Config:WaitForChild("Economy"))
local UiSkin = require(Config:WaitForChild("UiSkin"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DiscoveryController = {}
local DEBUG = true

local OPEN_TIMEOUT = 4 -- seconds to wait for BoxOpened; no answer = server refused (it sends a toast, e.g. "inventory full")
local CLAIM_COOLDOWN = 2 -- seconds the claim prompt stays off after a press (the box appearing is the confirmation)
local ESTIMATE_STARS = 2 -- "Est. value" = price when restored to 2★ (Good)
local BOX_SPACING = 3.2 -- studs between boxes at the door
local DOT_EMPTY = UiTheme.Disabled
-- same rule as InventoryService: these states don't use an inventory slot (opening a box turns Unopened into Dirty)
local NOT_COUNTED = { Unopened = true, Displayed = true, Exhibited = true }

local player = Players.LocalPlayer
local others = nil
local discovery: ScreenGui? = nil
local myPlot: Model? = nil
local boxFolder: Folder? = nil
local boxModels: { [string]: Model } = {} -- [boxId] = model at the door
local results: { [string]: { itemId: string, golden: boolean, isNew: boolean, autoSold: number } } = {} -- [uid] = BoxOpened info
local cardTexts: { hint: string, store: string }? = nil -- the card's own Hint + Store wording (auto-sold cards swap them)
local opening = false
local storePressed = Instance.new("BindableEvent")
local claimPrompt: ProximityPrompt? = nil
local claimSign: TextLabel? = nil
local claimCooldownUntil = 0

local function log(...)
	if DEBUG then
		print("[DiscoveryController]", ...)
	end
end

-- ===== Waiting boxes (grouped by boxId) =====

-- Returns my waiting boxes oldest first: { { boxId, crateId, uids } }, uids sorted so items open in a stable order.
local function waitingBoxes()
	local inventory = ClientState.Get("inventory") or {}
	local byBox = {}
	for uid, item in inventory do
		if type(item) == "table" and item.state == "Unopened" then
			local key = item.boxId or uid
			local box = byBox[key]
			if box == nil then
				box = { boxId = key, crateId = item.crateId, uids = {}, first = item.acquiredAt or 0 }
				byBox[key] = box
			end
			table.insert(box.uids, uid)
			box.first = math.min(box.first, item.acquiredAt or 0)
		end
	end
	local list = {}
	for _, box in byBox do
		table.sort(box.uids)
		table.insert(list, box)
	end
	table.sort(list, function(a, b)
		return a.first < b.first
	end)
	return list
end

-- Returns used, capacity. A copy of the server's check so the player sees "full" before trying; the server still decides.
local function inventoryRoom(): (number, number)
	local used = 0
	for _, item in ClientState.Get("inventory") or {} do
		if type(item) == "table" and not NOT_COUNTED[item.state] then
			used += 1
		end
	end
	return used, Formulas.inventoryCapacity(ClientState.Get("upgrades.StorageRacks") or 0)
end

local function isInventoryFull(): boolean
	local used, max = inventoryRoom()
	return used >= max
end

-- True if the server will auto-sell this waiting item (same rule as ShipmentService.shouldAutoSell: an allowed rarity,
-- not Golden, switched on in Settings). Auto-sold items need no slot, so a full inventory doesn't block them.
local function wouldAutoSell(uid: string): boolean
	local item = ClientState.Get("inventory." .. uid)
	local def = type(item) == "table" and Items[item.itemId]
	if not def or item.golden == true or table.find(Economy.AutoSellRarities, def.rarity) == nil then
		return false
	end
	return ClientState.Get("settings.autoSell" .. def.rarity) == true
end

-- Full, and nothing in this box would be auto-sold: opening it can't work.
local function boxBlocked(box): boolean
	if not isInventoryFull() then
		return false
	end
	for _, uid in box.uids do
		if wouldAutoSell(uid) then
			return false
		end
	end
	return true
end

local function notifyFull()
	local used, max = inventoryRoom()
	local text = `Inventory full ({used}/{max})! Sell unrestored items, put restored ones on shelves, or buy Storage Racks.`
	if others and others.HudController and others.HudController.Notify then
		others.HudController.Notify("Info", text)
	else
		warn("[DiscoveryController] " .. text)
	end
	log("box not opened: inventory full", used, max)
end

local function findBox(boxId: string)
	for _, box in waitingBoxes() do
		if box.boxId == boxId then
			return box
		end
	end
	return nil
end

-- ===== Discovery card =====

function DiscoveryController.IsOpen(): boolean
	return discovery ~= nil and discovery.Card.Visible
end

-- ----- the card's look (2026-11-25, from the Figma workshop style): walnut panel, rarity ribbon, a lit showcase with the item's
-- real model turning slowly, gold value line, chunky buttons. The Studio-authored card keeps its names; this only restyles it.
local WHITE_COLOR = Color3.new(1, 1, 1)
local FONT_TITLE = UiSkin.FONT_TITLE
local FONT_TEXT = UiSkin.FONT_TEXT
local C = UiSkin.COLORS
local cardSkinned = false
local spinConn: RBXScriptConnection? = nil
local showcaseParts = nil

local function decorate(parent: Instance, class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

local function skinCard(card: Frame)
	if cardSkinned then
		return
	end
	cardSkinned = true
	card.Size = UDim2.fromOffset(340, 496)
	card.BackgroundColor3 = WHITE_COLOR
	card.BackgroundTransparency = 0
	for _, c in card:GetChildren() do
		if c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	decorate(card, "UICorner", { CornerRadius = UDim.new(0, 24) })
	decorate(card, "UIGradient", { Color = ColorSequence.new(C.panelTop, C.panelBottom), Rotation = 90 })
	decorate(card, "UIStroke", { Color = C.ink, Thickness = 5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local rim = decorate(card, "Frame", { Name = "Rim", Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 1, -14), BackgroundTransparency = 1, ZIndex = 1 })
	decorate(rim, "UICorner", { CornerRadius = UDim.new(0, 19) })
	decorate(rim, "UIStroke", { Color = C.edge, Thickness = 1.5, Transparency = 0.65 })

	-- Restore button removed from the card (Sean, 2026-11-25): it only said "Restore: soon". Restoring starts from the
	-- Inventory / storage shelves. Hidden, not deleted, so the StarterGui.Discovery names in the UI contract stay the same.
	card.RestoreButton.Visible = false

	-- ribbon: the rarity colour (set per item), glossy, with the counter on the right
	local banner = card.RarityBanner
	banner.Position = UDim2.fromOffset(16, 14)
	banner.Size = UDim2.new(1, -32, 0, 36)
	banner.BackgroundColor3 = WHITE_COLOR
	for _, c in banner:GetChildren() do
		if c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	decorate(banner, "UICorner", { CornerRadius = UDim.new(1, 0) })
	decorate(banner, "UIGradient", { Color = ColorSequence.new(WHITE_COLOR, Color3.fromRGB(190, 190, 190)), Rotation = 90 })
	decorate(banner, "UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local bt = banner.Text
	bt.Position = UDim2.fromOffset(18, 0)
	bt.Size = UDim2.new(1, -90, 1, 0)
	bt.FontFace = FONT_TITLE
	bt.TextSize = 22
	bt.TextScaled = false
	bt.TextColor3 = C.cream
	bt.TextXAlignment = Enum.TextXAlignment.Left
	decorate(bt, "UIStroke", { Color = C.ink, Thickness = 2.5 })
	card.Counter.Position = UDim2.new(1, -86, 0, 20) -- sits on the right end of the ribbon
	card.Counter.Size = UDim2.fromOffset(60, 24)
	card.Counter.FontFace = FONT_TEXT
	card.Counter.TextSize = 16
	card.Counter.TextColor3 = C.cream
	card.Counter.TextXAlignment = Enum.TextXAlignment.Right
	card.Counter.ZIndex = banner.ZIndex + 3

	-- showcase: dark lit window with a glow, slow god rays and the item
	local show = decorate(card, "Frame", {
		Name = "Showcase", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(212, 200),
		BackgroundColor3 = Color3.fromRGB(26, 15, 10), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 2,
	})
	decorate(show, "UICorner", { CornerRadius = UDim.new(0, 20) })
	local showStroke = decorate(show, "UIStroke", { Color = C.accent, Thickness = 3, Transparency = 0.15 })
	local rays = decorate(show, "ImageLabel", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.7, 1.7), BackgroundTransparency = 1, Image = "rbxassetid://135275527744049", ImageTransparency = 0.55, ZIndex = 3 })
	local glow = decorate(show, "ImageLabel", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.15, 1.15), BackgroundTransparency = 1, Image = "rbxassetid://93831669035461", ImageTransparency = 0.25, ZIndex = 4 })
	local floor = decorate(show, "ImageLabel", { Name = "Floor", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.88), Size = UDim2.fromScale(0.7, 0.16), BackgroundTransparency = 1, Image = "rbxassetid://93831669035461", ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.35, ZIndex = 5 })
	local slot = decorate(show, "Frame", { Name = "Slot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 })
	local shine = decorate(show, "ImageLabel", { Name = "Sparkle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.8, 0.2), Size = UDim2.fromScale(0.2, 0.2), BackgroundTransparency = 1, Image = "rbxassetid://70480965980346", ImageTransparency = 0.2, ZIndex = 8 })
	showcaseParts = { show = show, stroke = showStroke, rays = rays, glow = glow, slot = slot, shine = shine }

	local name = card:FindFirstChild("Name") :: TextLabel
	name.Position = UDim2.fromOffset(12, 268)
	name.Size = UDim2.new(1, -24, 0, 40)
	name.FontFace = FONT_TITLE
	name.TextSize = 28
	name.TextScaled = false
	name.TextColor3 = C.cream
	name.ZIndex = 3
	decorate(name, "UIStroke", { Color = C.ink, Thickness = 2.5 })

	local dots = card.Dots
	dots.AnchorPoint = Vector2.new(0.5, 0)
	dots.Position = UDim2.new(0.5, 0, 0, 314)
	for _, d in dots:GetChildren() do
		if d:IsA("Frame") then
			for _, x in d:GetChildren() do
				if x:IsA("UICorner") or x:IsA("UIStroke") then
					x:Destroy()
				end
			end
			decorate(d, "UICorner", { CornerRadius = UDim.new(1, 0) })
			decorate(d, "UIStroke", { Color = C.ink, Thickness = 2 })
		end
	end
	for _, tag in { card.NewTag, card.GoldenTag } do
		for _, x in tag:GetChildren() do
			if x:IsA("UICorner") or x:IsA("UIStroke") then
				x:Destroy()
			end
		end
		decorate(tag, "UICorner", { CornerRadius = UDim.new(1, 0) })
		decorate(tag, "UIStroke", { Color = C.ink, Thickness = 2.5 })
		tag.Text.FontFace = FONT_TITLE
		tag.Text.TextSize = 15
		tag.Text.TextScaled = false
	end
	local value = card.Value
	value.Position = UDim2.fromOffset(12, 372)
	value.Size = UDim2.new(1, -24, 0, 34)
	value.FontFace = FONT_TITLE
	value.TextSize = 26
	value.TextScaled = false
	value.TextColor3 = C.gold
	decorate(value, "UIStroke", { Color = C.ink, Thickness = 2.5 })
	local hint = card.Hint
	hint.Position = UDim2.fromOffset(12, 410)
	hint.FontFace = UiSkin.FONT_BODY
	hint.TextSize = 13
	hint.TextColor3 = C.textDim

	for _, b in { card.StoreButton } do
		b.Size = UDim2.fromOffset(140, 50)
		b.FontFace = FONT_TITLE
		b.TextSize = 20
		b.TextScaled = false
		b.TextColor3 = C.cream
		b.AutoButtonColor = true
		for _, x in b:GetChildren() do
			if x:IsA("UICorner") or x:IsA("UIStroke") or x:IsA("UIGradient") then
				x:Destroy()
			end
		end
		decorate(b, "UICorner", { CornerRadius = UDim.new(0, 16) })
		decorate(b, "UIGradient", { Color = ColorSequence.new(WHITE_COLOR, Color3.fromRGB(190, 190, 190)), Rotation = 90 })
		decorate(b, "UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	end
	card.StoreButton.Position = UDim2.new(0.5, 0, 1, -16) -- centred now that it's the only button
	card.StoreButton.BackgroundColor3 = Color3.fromRGB(31, 194, 165)
	decorate(card, "UIScale", { Name = "Pop" })
end

-- fills the showcase for this item: rarity-coloured glow and rays, and the real model turning slowly (a star badge if a model is missing)
local function updateShowcase(card: Frame, info, color: Color3, rarityIndex: number)
	local parts = showcaseParts
	if parts == nil then
		return
	end
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
	for _, c in parts.slot:GetChildren() do
		c:Destroy()
	end
	parts.stroke.Color = color
	parts.glow.ImageColor3 = color
	parts.rays.ImageColor3 = color
	parts.rays.ImageTransparency = 0.7 - math.min(rarityIndex, 6) * 0.07
	parts.shine.ImageColor3 = color:Lerp(WHITE_COLOR, 0.6)
	local viewport, orbit = Unboxing.ItemViewport(parts.slot, info.itemId)
	if viewport == nil then
		decorate(parts.slot, "ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.55, 0.55), BackgroundTransparency = 1, Image = UiSkin.Art("Star"), ZIndex = 7 })
	end
	local started = os.clock()
	spinConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		if orbit then
			orbit(0.5 + t * 0.9)
		end
		parts.rays.Rotation = t * 10
		parts.shine.Size = UDim2.fromScale(0.16 + 0.05 * math.sin(t * 3), 0.16 + 0.05 * math.sin(t * 3))
		parts.shine.Rotation = t * 25
	end)
	-- a quick pop-in so each new card feels alive
	local pop = card:FindFirstChild("Pop") :: UIScale?
	if pop then
		-- the card is 496 px tall: shrink it to fit short (phone) screens, grow a little on big ones
		local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local fit = math.clamp(view.Y * 0.92 / 496, 0.55, 1.15)
		pop.Scale = fit * 0.9
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	end
end

local function showCard(info, index: number, total: number)
	if discovery == nil then
		return
	end
	local card = discovery.Card
	skinCard(card)
	local def = Items[info.itemId]
	local rarity = def and def.rarity or "Common"
	local rarityDef = Rarities[rarity]
	local color = UiTheme.rarityColor(rarity)
	updateShowcase(card, info, color, rarityDef and rarityDef.index or 1)

	card.RarityBanner.BackgroundColor3 = color
	card.RarityBanner.Text.Text = string.upper(rarity)
	card.Counter.Text = `{index}/{total}`
	card.Counter.Visible = total > 1
	-- "Name" clashes with the built-in Name property, so look it up as a child.
	(card:FindFirstChild("Name") :: TextLabel).Text = def and def.name or info.itemId

	local filled = rarityDef and rarityDef.index or 1
	for i = 1, 5 do
		local dot = card.Dots:FindFirstChild("Dot" .. i)
		if dot then
			dot.BackgroundColor3 = if i <= filled then color else DOT_EMPTY
		end
	end

	-- NEW! and GOLDEN sit side by side; a single tag moves to the center.
	card.NewTag.Visible = info.isNew
	card.GoldenTag.Visible = info.golden
	local both = info.isNew and info.golden
	card.NewTag.Position = UDim2.new(0.5, if both then -46 else 0, 0, 338)
	card.GoldenTag.Position = UDim2.new(0.5, if both then 46 else 0, 0, 338)

	-- Auto-sold (Settings → Auto sell): the card still shows the find, but says it was sold and for how much.
	if cardTexts == nil then
		cardTexts = { hint = card.Hint.Text, store = card.StoreButton.Text } -- the Studio-authored wording, kept for normal finds
	end
	local autoSold = tonumber(info.autoSold) or 0
	if autoSold > 0 then
		card.Value.Text = `Auto-sold +${autoSold}`
		card.Hint.Text = "Sold right away (Settings → Auto sell)"
		card.StoreButton.Text = "Nice!"
	else
		local estimate = if def then Formulas.sellPrice(info.itemId, ESTIMATE_STARS, info.golden) else 0
		card.Value.Text = `Est. value ${estimate}`
		card.Hint.Text = cardTexts.hint
		card.StoreButton.Text = cardTexts.store
	end
	card.Visible = true
end

local function hideCard()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
	if discovery then
		discovery.Card.Visible = false
	end
end

-- Dev helper: shows the discovery card for any item without opening a box (DiscoveryController.Preview("LavaLamp")).
function DiscoveryController.Preview(itemId: string, golden: boolean?)
	if discovery == nil or Items[itemId] == nil then
		return
	end
	showCard({ itemId = itemId, golden = golden == true, isNew = true }, 1, 1)
	storePressed.Event:Once(function()
		hideCard()
	end)
end

-- Opens every item in one box, one card at a time. The server checks everything (state, inventory room).
local function openBox(boxId: string)
	if opening then
		return
	end
	local box = findBox(boxId)
	if box == nil then
		return
	end
	if boxBlocked(box) then
		notifyFull()
		return
	end
	opening = true
	if others and others.ShopController and others.ShopController.CloseAll then
		others.ShopController.CloseAll() -- Supply + Upgrades; one modal at a time (docs/01 J4)
	end
	if others and others.InventoryController and others.InventoryController.Close then
		others.InventoryController.Close()
	end

	local total = #box.uids
	local skipShow = false
	for index, uid in box.uids do
		if isInventoryFull() and not wouldAutoSell(uid) then -- a box with several items can fill the last slots part-way through
			notifyFull()
			break
		end
		results[uid] = nil
		Remotes.RequestOpenBox:FireServer(uid)
		local started = os.clock()
		while results[uid] == nil and os.clock() - started < OPEN_TIMEOUT do
			task.wait(0.05)
		end
		local info = results[uid]
		results[uid] = nil
		if info == nil then
			log("no BoxOpened for", uid, "- server refused (see toast)")
			break
		end
		-- the tap-to-open show first (full for the first item, quick for the rest, none after "Skip all")
		if not skipShow then
			local def = Items[info.itemId]
			local settings = ClientState.Get("settings")
			local status = Unboxing.Play(
				{ itemId = info.itemId, name = def and def.name, rarity = def and def.rarity, golden = info.golden },
				{
					quick = index > 1,
					reduce = type(settings) == "table" and settings.reduceEffects == true,
					sfx = function(name)
						if others and others.SoundController and others.SoundController.Play then
							others.SoundController.Play(name)
						end
					end,
				}
			)
			skipShow = status == "skip"
		end
		showCard(info, index, total)
		storePressed.Event:Wait()
	end
	hideCard()
	opening = false
end

-- ===== Box models at my DeliveryPoint =====

local function makeBoxModel(box): Model?
	local boxes = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Boxes")
	if boxes == nil then
		warn("[DiscoveryController] ReplicatedStorage.Assets.Boxes is missing")
		return nil
	end
	local crate = box.crateId and Crates[box.crateId]
	local template = boxes:FindFirstChild(crate and crate.boxModel or "Box") or boxes:FindFirstChild("Box")
	if template == nil then
		return nil
	end
	local model = template:Clone() :: Model
	model.Name = "Box_" .. box.boxId
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")

	-- "?" marker so the box reads as "something to open" from across the shop (docs/01 J3)
	local marker = Instance.new("BillboardGui")
	marker.Size = UDim2.fromOffset(40, 40)
	marker.StudsOffset = Vector3.new(0, 2.5, 0)
	marker.AlwaysOnTop = true
	marker.Parent = body
	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Text = "❓"
	mark.TextScaled = true
	mark.Parent = marker

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = crate and crate.name or "Box"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	local boxId = box.boxId
	prompt.Triggered:Connect(function()
		task.spawn(openBox, boxId)
	end)
	return model
end

local function renderBoxes()
	if myPlot == nil or boxFolder == nil then
		return
	end
	local point = myPlot:FindFirstChild("DeliveryPoint")
	if point == nil or not point:IsA("BasePart") then
		return
	end

	local list = waitingBoxes()
	local keep = {}
	for slot, box in list do
		if slot > Economy.MaxWaitingBoxes then
			break
		end
		keep[box.boxId] = true
		local model = boxModels[box.boxId]
		if model == nil then
			model = makeBoxModel(box)
			if model == nil then
				continue
			end
			boxModels[box.boxId] = model
			model.Parent = boxFolder
		end
		-- the prompt itself says the inventory is full, so the player knows before pressing
		local openPrompt = model:FindFirstChild("OpenPrompt", true) :: ProximityPrompt?
		if openPrompt then
			openPrompt.ActionText = if boxBlocked(box) then "Inventory full" else "Open"
		end
		-- Slot 1 in the middle, then left, then right. Sit on top of the DeliveryPoint pad.
		local x = if slot == 1 then 0 elseif slot == 2 then -BOX_SPACING else BOX_SPACING
		local body = model.PrimaryPart
		local height = body and body.Size.Y or 2
		model:PivotTo(point.CFrame * CFrame.new(x, point.Size.Y / 2 + height / 2, 0))
	end
	for boxId, model in boxModels do
		if not keep[boxId] then
			model:Destroy()
			boxModels[boxId] = nil
		end
	end
end

-- ===== Free Delivery (claim prompt + countdown sign on my DeliveryPoint) =====

-- Mirrors the checks in ShipmentService.ClaimFreeDelivery so the prompt only shows when a claim will work.
-- Returns ready, sign text. The server checks again; this only decides what the player sees.
local function freeDeliveryStatus(): (boolean, string)
	local last = ClientState.Get("timers.lastFreeDelivery")
	if type(last) ~= "number" then
		return false, ""
	end
	local boxes = waitingBoxes()
	for _, box in boxes do
		if box.crateId == "FreeDelivery" then
			return false, "" -- the free box itself is at the door with its own "Open" prompt
		end
	end
	if #boxes >= Economy.MaxWaitingBoxes then
		return false, "📦 Open your boxes first"
	end
	-- Server time, not this PC's clock: os.time() on a PC with a wrong clock would show a wrong countdown.
	local remaining = Economy.FreeDeliveryIntervalSeconds - (math.floor(workspace:GetServerTimeNow()) - last)
	if remaining > 0 then
		return false, string.format("📦 Free box in %d:%02d", remaining // 60, remaining % 60)
	end
	return true, "📦 Free box ready!"
end

local function updateFreeDelivery()
	if claimPrompt == nil or claimSign == nil then
		return
	end
	local ready, text = freeDeliveryStatus()
	claimPrompt.Enabled = ready and os.clock() >= claimCooldownUntil
	claimSign.Text = text
	claimSign.Visible = text ~= ""
end

local function setUpFreeDelivery(point: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FreeDeliveryPrompt"
	prompt.ActionText = "Claim free box"
	prompt.ObjectText = "Free Delivery"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10 -- server allows Economy.InteractMaxStuds; stay well inside it
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = point
	prompt.Triggered:Connect(function()
		local ready = freeDeliveryStatus()
		if not ready then
			return
		end
		claimCooldownUntil = os.clock() + CLAIM_COOLDOWN
		prompt.Enabled = false
		Remotes.RequestClaimFreeDelivery:FireServer()
		log("asked for free delivery")
	end)
	claimPrompt = prompt

	-- Small sign above the pad, only visible to me (client-side like the boxes).
	local board = Instance.new("BillboardGui")
	board.Name = "FreeDeliverySign"
	board.Size = UDim2.fromOffset(200, 36)
	board.StudsOffset = Vector3.new(0, 5, 0)
	board.MaxDistance = 60
	board.Parent = point
	local sign = Instance.new("TextLabel")
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundColor3 = UiTheme.Cream
	sign.BackgroundTransparency = 0.1
	sign.TextColor3 = UiTheme.Ink
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.Text = ""
	sign.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = sign
	claimSign = sign

	-- One light loop for the countdown (1 update per second), plus instant updates on data changes.
	task.spawn(function()
		while claimPrompt == prompt do
			updateFreeDelivery()
			task.wait(1)
		end
	end)
	ClientState.OnChanged("timers", updateFreeDelivery)
end

-- Waits until PlotService marks a plot as mine (OwnerUserId attribute replicates from the server).
local function waitForMyPlot(): Model?
	local plots = workspace:WaitForChild("Plots", 10)
	if plots == nil then
		return nil
	end
	local started = os.clock()
	while os.clock() - started < 30 do
		for _, plot in plots:GetChildren() do
			if plot:GetAttribute("OwnerUserId") == player.UserId then
				return plot :: Model
			end
		end
		task.wait(0.25)
	end
	return nil
end

-- ===== Lifecycle =====

function DiscoveryController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function DiscoveryController.Start()
	log("Start")
	-- Listen right away so no BoxOpened is missed.
	Remotes.BoxOpened.OnClientEvent:Connect(function(uid, itemId, isGolden, isNew, autoSold)
		if type(uid) == "string" and type(itemId) == "string" then
			results[uid] = { itemId = itemId, golden = isGolden == true, isNew = isNew == true, autoSold = tonumber(autoSold) or 0 }
		end
	end)

	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		discovery = playerGui:WaitForChild("Discovery", 10) :: ScreenGui?
		if discovery == nil then
			warn("[DiscoveryController] PlayerGui.Discovery not found: is StarterGui.Discovery missing?")
		else
			discovery.Card.StoreButton.Activated:Connect(function()
				storePressed:Fire()
			end)
			-- RestoreButton stays greyed out until restoration (Dev 2) exists.
			discovery.Card.RestoreButton.AutoButtonColor = false
		end

		myPlot = waitForMyPlot()
		if myPlot == nil then
			warn("[DiscoveryController] no plot is mine: boxes at the door won't show")
			return
		end
		boxFolder = Instance.new("Folder")
		boxFolder.Name = "MyBoxes" -- client-only: other players don't see my boxes
		boxFolder.Parent = workspace
		renderBoxes()
		ClientState.OnChanged("inventory", function()
			renderBoxes()
			updateFreeDelivery()
		end)
		ClientState.OnChanged("upgrades", renderBoxes) -- Storage Racks bought: the prompt goes back to "Open"
		ClientState.OnChanged("settings", renderBoxes) -- auto sell switched on: a full inventory may not block the box now
		local point = myPlot:FindFirstChild("DeliveryPoint")
		if point and point:IsA("BasePart") then
			setUpFreeDelivery(point)
		end
		log(`ready at {myPlot.Name}, {#waitingBoxes()} box(es) waiting`)
	end)
end

return DiscoveryController
