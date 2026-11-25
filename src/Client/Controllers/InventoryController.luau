-- InventoryController.luau
-- Purpose: Inventory screen: grid of my items (from ClientState) with filters and capacity, a details panel per
-- item. Restored items sell ONLY on a display shelf (Quick Sell is off, Sean + Ace 2026-11-25: the old button now says so).
-- "Sell unrestored…" (Ace's Dispose, RequestDisposeItems) sells many Dirty items at once. The server checks state and
-- price; this screen only shows and requests. Opens from HUD 🎒 (the counter's QuickSellPrompt is switched off, 2026-11-25).
-- Also the "INVENTORY FULL" chip in the HUD's top chip row while every slot is used (code-built, HudKit.Chip).
-- Picker mode (OpenPicker, called by DisplayController from an empty slot): choose a Restored item and send
-- RequestPlaceDisplay / RequestPlaceExhibit for that slot.
-- Restore (Dirty/InProgress) calls Dev 2's RestorationController.RequestStartRestore(uid); greyed until that exists.
-- Look (Sean, 2026-11-25): the Figma "Window · Inventory" (applyFigmaLayout + buildCard): capacity pill, gold tabs with counts,
-- cards with the item's cartoon icon (Config/ItemIcons) and a DIRTY tag / stars / progress bar, a details panel with a
-- rarity-glow art plaque showing the real 3D model.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, WindowKit, UnboxingKit (ItemViewport), Shared.Remotes, Shared.Formulas,
-- Shared.Config (Items, Rarities, Economy, UiSkin), StarterGui.Inventory,
-- Workspace.Plots (OwnerUserId attribute, Counter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit")) -- the inventory-full chip (same look as the Day chip)
local WindowKit = require(script.Parent.Parent:WaitForChild("WindowKit")) -- Figma pieces: Fit, Chunky buttons, Badge
local Unboxing = require(script.Parent.Parent:WaitForChild("UnboxingKit")) -- ItemViewport: the item's real model, lit
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Items = require(Config:WaitForChild("Items"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Economy = require(Config:WaitForChild("Economy"))
local UiSkin = require(Config:WaitForChild("UiSkin"))
local ItemIcons = require(Config:WaitForChild("ItemIcons")) -- flat cartoon icons for the cards

local InventoryController = {}
local DEBUG = true

-- Figma "Window · Inventory" (92:6180 phone 560 x 325, 92:7247 desktop = 1.4x), Sean 2026-11-25. Numbers below are the
-- 560 x 325 design in px; WindowKit.Fit scales the whole window up on bigger screens.
local DESIGN = Vector2.new(560, 325)
local CARD = Vector2.new(74, 82) -- card surface; +4 px for the lip under it
local INK = Color3.fromRGB(43, 27, 20)
local WALNUT_LIGHT = Color3.fromRGB(90, 59, 40)
local CREAM = Color3.fromRGB(255, 241, 214)
local GOLD = Color3.fromRGB(255, 200, 58)
local DIRT = Color3.fromRGB(107, 74, 42)
local TAG_BROWN = Color3.fromRGB(138, 90, 42)
local PROGRESS = Color3.fromRGB(46, 230, 196)
local GLOW_IMAGE = "rbxassetid://93831669035461" -- the soft glow the Discovery card uses behind the item
local FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_BOLD = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local FONT_BODY = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Regular)
local TAB_LABELS = { All = "All", NeedsRestoring = "Needs Restoring", Restored = "Restored" }

local ESTIMATE_STARS = 2 -- value shown for items not restored yet ("~$X" at 2★, same as the Discovery card)
local NEAR_CHECK_SECONDS = 0.5 -- how often the details panel refreshes while the window is open
local SOLD_MESSAGE_SECONDS = 2

-- States that don't use inventory space. Mirrors InventoryService (docs/08 §2).
local NOT_COUNTED = { Unopened = true, Displayed = true, Exhibited = true }
local STATE_TEXT = {
	Dirty = "Needs restoring",
	InProgress = "Being restored",
	Restored = "Restored",
	Displayed = "On a shelf",
	Exhibited = "On exhibit",
}
-- Tab name -> which states it shows. Unopened items are never listed: they are the boxes at the door.
local FILTERS = {
	All = { Dirty = true, InProgress = true, Restored = true, Displayed = true, Exhibited = true },
	NeedsRestoring = { Dirty = true, InProgress = true },
	Restored = { Restored = true },
	DirtyOnly = { Dirty = true }, -- Dispose mode: only items that were never started
}

local player = Players.LocalPlayer
local others = nil
local inventoryGui: ScreenGui? = nil
local myPlot: Model? = nil
local currentFilter = "All"
local selectedUid: string? = nil
local selling = false
local soldMessageUntil = 0
-- Picker mode: opened from a shelf/pedestal prompt (DisplayController) to choose a Restored item for that slot.
local pickTarget: { kind: string, slotIndex: number, label: string }? = nil
local placingUid: string? = nil
-- Dispose (2026-11-25): throw away Dirty items for ~40% of their estimated value (the server decides the price and re-checks).
local disposeMode = false -- the "pick what to throw away" view
local picked: { [string]: boolean } = {}
local confirmUntil = 0 -- a dispose button needs a second tap before this time
local disposeUi: { mode: TextButton, single: TextButton, selCommon: TextButton, confirm: TextButton }? = nil -- built on first open

local function log(...)
	if DEBUG then
		print("[InventoryController]", ...)
	end
end

-- Same formula the server uses (Formulas is shared), so the "used/max" number always matches.
local function capacity(): number
	return Formulas.inventoryCapacity(ClientState.Get("upgrades.StorageRacks") or 0)
end

local function starsText(stars: number?): string
	local n = math.clamp(stars or 0, 0, 3)
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

-- Value shown on a card: real price at its stars once restored, otherwise an estimate at 2★.
local function itemValue(item): (number, boolean)
	if not Items[item.itemId] then
		return 0, true
	end
	if type(item.stars) == "number" then
		return Formulas.sellPrice(item.itemId, item.stars, item.golden), false
	end
	return Formulas.sellPrice(item.itemId, ESTIMATE_STARS, item.golden), true
end

local function rarityOf(item): string
	local def = Items[item.itemId]
	return def and def.rarity or "Common"
end

-- ===== Figma layout (built once; the Studio objects keep their names, so the rest of this file works unchanged) =====

local cards: { [string]: GuiButton } = {} -- uid -> card in the grid (for selection / pick marks without a rebuild)
local artPlaque: Frame? = nil -- details panel: rarity glow + the item's model
local artUid: string? = nil -- which item the plaque shows

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

local function outline(parent: Instance, color: Color3, thickness: number): UIStroke
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

-- A plain label in the design's type (no scaling: sizes are design px, the window's DfFit scale does the rest).
local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1, TextColor3 = CREAM, FontFace = FONT_BOLD, TextSize = 12, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- Re-skins an existing Studio label to the design (drops its old size constraint so TextSize is exact).
local function restyle(label: TextLabel, props: { [string]: any })
	for _, c in label:GetChildren() do
		if c:IsA("UITextSizeConstraint") then
			c:Destroy()
		end
	end
	label.TextScaled = false
	label.BackgroundTransparency = 1
	for k, v in props do
		(label :: any)[k] = v
	end
end

-- The item's real model in `holder` (UnboxingKit.ItemViewport), drawn at the holder's ZIndex.
local function itemArt(holder: GuiObject, itemId: string)
	local viewport = Unboxing.ItemViewport(holder, itemId)
	if viewport then
		viewport.ZIndex = holder.ZIndex
	else
		-- no model yet: its cartoon icon, or the "?" icon
		new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.85, 0.85), ScaleType = Enum.ScaleType.Fit,
			BackgroundTransparency = 1, Image = ItemIcons[itemId] or ItemIcons.Unknown, ZIndex = holder.ZIndex,
		}, holder)
	end
end

-- The flat cartoon icon on a card (Config/ItemIcons, like the Figma cards); the 3D model if an item has no icon yet.
-- Icons are images, so a full grid stays cheap on phones; the detail panel shows the real model.
local function cardArt(holder: GuiObject, itemId: string)
	local icon = ItemIcons[itemId]
	if icon then
		new("ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), ZIndex = holder.ZIndex,
		}, holder)
	else
		itemArt(holder, itemId)
	end
end

-- Three brown smudges over the art of an item that still needs restoring (the design's "Dirt").
local function dirt(holder: GuiObject)
	for _, spot in { { 0.14, 0.16, 0.32, 0.2 }, { 0.55, 0.45, 0.26, 0.18 }, { 0.26, 0.64, 0.22, 0.15 } } do
		local blob = new("Frame", {
			Name = "Dirt", BackgroundColor3 = DIRT, BackgroundTransparency = 0.5, BorderSizePixel = 0,
			Position = UDim2.fromScale(spot[1], spot[2]), Size = UDim2.fromScale(spot[3], spot[4]), ZIndex = holder.ZIndex + 1,
		}, holder)
		round(blob, 99)
	end
end

local function applyFigmaLayout(window: Frame)
	window:SetAttribute("DfFigma", true) -- WindowKit: draw only the shell, this controller does the rest
	window.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	WindowKit.Fit(window, DESIGN.Y)

	-- close button: the design's 38 px square in the corner (Figma x 506, y 4); the Studio one was 44 px and reached
	-- down into the tab row, over "Sell unrestored…"
	local close = window.CloseButton :: GuiButton
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 5)
	close.Size = UDim2.fromOffset(38, 38)

	-- capacity pill: dark, inventory glyph + "12 / 24"
	local capacity = window.Capacity :: TextLabel
	restyle(capacity, {
		Position = UDim2.fromOffset(386, 7), Size = UDim2.fromOffset(108, 30), BackgroundTransparency = 0, BackgroundColor3 = INK,
		FontFace = FONT_TITLE, TextSize = 16, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Right,
	})
	round(capacity, 16)
	outline(capacity, WALNUT_LIGHT, 2.5)
	new("UIPadding", { PaddingRight = UDim.new(0, 12) }, capacity)
	new("ImageLabel", {
		Name = "Icon", BackgroundTransparency = 1, Image = UiSkin.Art("Inventory"), Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(22, 22),
		ZIndex = capacity.ZIndex + 1,
	}, capacity)

	-- tab row: chunky tabs that hug their text (gold = active)
	local tabs = window.Tabs :: Frame
	tabs.Position = UDim2.fromOffset(12, 48)
	tabs.Size = UDim2.fromOffset(330, 34)
	local list = tabs:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, 6)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
	end
	for _, tab in tabs:GetChildren() do
		if tab:IsA("TextButton") then
			tab.AutomaticSize = Enum.AutomaticSize.None
			tab.Size = UDim2.fromOffset(80, 30) -- refreshTabs sizes each tab to its text
			WindowKit.Chunky(tab, WindowKit.BUTTON.Walnut, 14, 12)
		end
	end

	-- grid: 4 cards a row, scrolls
	local grid = window.Grid :: ScrollingFrame
	grid.Position = UDim2.fromOffset(8, 87)
	grid.Size = UDim2.fromOffset(332, 224)
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = GOLD
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = UDim2.fromOffset(CARD.X, CARD.Y + 4)
		layout.CellPadding = UDim2.fromOffset(6, 6)
	end
	local pad = grid:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5), UDim.new(0, 0), UDim.new(0, 8)
	end
	restyle(window.Empty :: TextLabel, { FontFace = FONT_BODY, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.2, Position = UDim2.fromOffset(20, 110), Size = UDim2.fromOffset(300, 40) })

	-- details panel
	local details = window.Details :: Frame
	details.Position = UDim2.fromOffset(345, 86)
	details.Size = UDim2.fromOffset(198, 226)
	details.BackgroundColor3 = INK
	details.BackgroundTransparency = 0.1
	for _, c in details:GetChildren() do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	local corner = details:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 16)
	end
	outline(details, WALNUT_LIGHT, 2.5)
	artPlaque = new("Frame", {
		Name = "ArtPlaque", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(78, 78), Visible = false, ZIndex = details.ZIndex + 1,
	}, details)
	new("ImageLabel", {
		Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.6, 1.6),
		BackgroundTransparency = 1, Image = GLOW_IMAGE, ImageTransparency = 0, ZIndex = details.ZIndex + 1,
	}, artPlaque)
	new("Frame", {
		Name = "Art", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 1, ZIndex = details.ZIndex + 2,
	}, artPlaque)
	restyle(details.Hint, { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 60), FontFace = FONT_BODY, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.15 })
	restyle(details.ItemName, { Position = UDim2.fromOffset(6, 86), Size = UDim2.new(1, -12, 0, 22), FontFace = FONT_TITLE, TextSize = 16, TextColor3 = CREAM, TextTruncate = Enum.TextTruncate.AtEnd })
	local rarity = details.Rarity :: TextLabel
	restyle(rarity, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 111), Size = UDim2.fromOffset(0, 19) })
	WindowKit.Badge(rarity, Color3.fromRGB(176, 112, 255), 11)
	restyle(details.Info, { Position = UDim2.fromOffset(6, 134), Size = UDim2.new(1, -12, 0, 16), FontFace = FONT_BODY, TextSize = 11, TextColor3 = CREAM, TextTransparency = 0.15 })
	restyle(details.Value, { Position = UDim2.fromOffset(6, 151), Size = UDim2.new(1, -12, 0, 20), FontFace = FONT_TITLE, TextSize = 14, TextColor3 = GOLD })

	-- buttons: big teal Restore / Put on shelf on the left, a smaller coral Sell on the right
	local restore, place, quickSell = details.RestoreButton :: TextButton, details.PlaceButton :: TextButton, details.QuickSellButton :: TextButton
	for _, b in { restore, place } do
		b.AnchorPoint = Vector2.zero
		b.Position = UDim2.fromOffset(8, 176)
		b.Size = UDim2.fromOffset(104, 36)
		WindowKit.Chunky(b, WindowKit.BUTTON.Primary, 16, 13)
	end
	quickSell.AnchorPoint = Vector2.zero
	quickSell.Position = UDim2.fromOffset(8, 176)
	quickSell.Size = UDim2.new(1, -16, 0, 36)
	WindowKit.Chunky(quickSell, WindowKit.BUTTON.Disabled, 13, 13)
end

-- ===== Details panel =====

-- True once Dev 2's RestorationController offers RequestStartRestore(uid) (docs/Restoration_Contract.md §4).
local function restorationReady(): boolean
	local controller = others and others.RestorationController
	return controller ~= nil and type(controller.RequestStartRestore) == "function"
end

local function setDetailsVisible(details: Frame, showItem: boolean)
	details.Hint.Visible = not showItem
	for _, name in { "ItemName", "Rarity", "Info", "Value" } do
		details[name].Visible = showItem
	end
	if artPlaque then
		artPlaque.Visible = showItem
	end
	if not showItem then
		details.QuickSellButton.Visible = false
		details.RestoreButton.Visible = false
		details.PlaceButton.Visible = false
		if disposeUi then
			disposeUi.single.Visible = false
			disposeUi.selCommon.Visible = false
			disposeUi.confirm.Visible = false
		end
	end
end

-- The Dispose view's side panel: how many are picked, the payout, a warning for rare items, and the two buttons.
local function updateDisposePanel(details: Frame)
	local ui = disposeUi
	if ui == nil then
		return
	end
	local n, total, risky = 0, 0, false
	for uid in picked do
		local item = ClientState.Get("inventory." .. uid)
		if type(item) == "table" and item.state == "Dirty" then
			n += 1
			total += Formulas.disposePrice(item.itemId, item.golden)
			risky = risky or item.golden == true or Rarities[rarityOf(item)].index >= 3
		end
	end
	setDetailsVisible(details, false)
	details.Hint.Visible = true
	details.Hint.Text = (if n == 0
		then "Tap the unrestored items you want to sell. They pay about 40% of their estimated value."
		else `{n} picked · you get ${total}` .. (if risky then "\n⚠ Includes rare or golden items!" else ""))
		.. "\n⚠ Restored items can't be sold here: put them on a display shelf."
	ui.selCommon.Visible = true
	ui.selCommon.Text = "Select all Common"
	ui.confirm.Visible = true
	local sure = os.clock() < confirmUntil
	ui.confirm.Text = if n == 0 then "Pick items first" elseif sure then "Tap again to confirm" else `Sell {n} · +${total}`
	WindowKit.Chunky(ui.confirm, if n == 0 then WindowKit.BUTTON.Disabled elseif sure then WindowKit.BUTTON.Gold else WindowKit.BUTTON.Danger, 16, 13)
end

local function updateDetails()
	if inventoryGui == nil then
		return
	end
	local details = inventoryGui.Window.Details
	if os.clock() < soldMessageUntil then
		return -- keep showing "Sold for $X!" for a moment
	end
	if disposeUi then
		disposeUi.mode.Visible = pickTarget == nil -- not while choosing an item for a shelf
	end
	if disposeMode then
		updateDisposePanel(details)
		return
	end
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if type(item) ~= "table" or not FILTERS.All[item.state] then
		selectedUid = nil
		details.Hint.Text = if pickTarget
			then `Tap a restored item to put on {pickTarget.label}.`
			else "Tap an item to see what you can do."
		setDetailsVisible(details, false)
		return
	end

	local def = Items[item.itemId]
	local rarity = rarityOf(item)
	local color = UiTheme.rarityColor(rarity)
	setDetailsVisible(details, true)
	-- the art plaque: the item's model on a glow in its rarity colour (rebuilt only when the selection changes)
	local plaque = artPlaque
	if plaque and artUid ~= selectedUid then
		artUid = selectedUid
		local art = plaque:FindFirstChild("Art") :: Frame
		for _, c in art:GetChildren() do
			c:Destroy()
		end
		itemArt(art, item.itemId)
	end
	if plaque then
		(plaque:FindFirstChild("Glow") :: ImageLabel).ImageColor3 = color
	end
	details.ItemName.Text = (def and def.name or item.itemId) .. (if item.golden then " 🌟" else "")
	details.Rarity.Text = string.upper(rarity) .. (if item.golden then " · GOLDEN" else "")
	WindowKit.Badge(details.Rarity, color, 11)
	-- "Kitchen · needs 3 steps" (design); restored items show their stars instead
	local category = def and def.category or "Item"
	local steps = def and def.recipe and #def.recipe or 0
	local stateLine = if item.state == "Dirty" then `needs {steps} steps`
		elseif item.state == "InProgress" then `restoring · step {item.stepIndex or 1} of {steps}`
		elseif type(item.stars) == "number" then `{STATE_TEXT[item.state] or item.state} {starsText(item.stars)}`
		else (STATE_TEXT[item.state] or item.state)
	details.Info.Text = `{category} · {stateLine}`
	local value, estimate = itemValue(item)
	details.Value.Text = if estimate then `Worth about ${value}` else `Value ${value}`

	-- Quick Sell is off (Sean + Ace 2026-11-25): restored items sell only on a display shelf. The button stays as a
	-- greyed warning so players learn where to sell; tapping it explains (onQuickSell).
	local quickSell = details.QuickSellButton :: TextButton
	quickSell.Visible = item.state == "Restored" and type(item.stars) == "number"
	if quickSell.Visible then
		quickSell.Text = "⚠ Sell it on a display shelf"
		WindowKit.Chunky(quickSell, WindowKit.BUTTON.Disabled, 13, 13)
	end
	-- Restore hands over to Dev 2's RestorationController; greyed until that controller offers RequestStartRestore.
	local restore = details.RestoreButton :: TextButton
	restore.Visible = item.state == "Dirty" or item.state == "InProgress"
	local canRestore = restorationReady()
	restore.Text = if item.state == "InProgress" then "Continue" else "Restore"
	WindowKit.Chunky(restore, if canRestore then WindowKit.BUTTON.Primary else WindowKit.BUTTON.Disabled, 16, 13)

	-- Dispose (one item): only Dirty items, two taps (the second confirms).
	if disposeUi then
		local single = disposeUi.single
		single.Visible = item.state == "Dirty" and pickTarget == nil
		if single.Visible then
			local sure = os.clock() < confirmUntil
			single.Text = if sure then "Sure?" else `Sell ${Formulas.disposePrice(item.itemId, item.golden)}`
			WindowKit.Chunky(single, if sure then WindowKit.BUTTON.Gold else WindowKit.BUTTON.Danger, 13, 12)
		end
	end

	-- Picker mode: the only action is "put it on the slot I came from" (Quick Sell/Restore hidden).
	local place = details.PlaceButton :: TextButton
	place.Visible = pickTarget ~= nil and item.state == "Restored"
	if pickTarget then
		quickSell.Visible = false
		details.RestoreButton.Visible = false
		if place.Visible then
			place.Text = if placingUid
				then "Placing…"
				elseif pickTarget.kind == "Exhibit" then "Put on pedestal"
				else "Put on shelf"
		end
	end
end

-- ===== Grid =====

local function sortedItems(filter: string)
	local inventory = ClientState.Get("inventory") or {}
	local list = {}
	for uid, item in inventory do
		if type(item) == "table" and FILTERS[filter][item.state] then
			item.uid = uid
			table.insert(list, item)
		end
	end
	-- Rarest first, then by name, then uid so the order never jumps around.
	table.sort(list, function(a, b)
		local ra = Rarities[rarityOf(a)].index
		local rb = Rarities[rarityOf(b)].index
		if ra ~= rb then
			return ra > rb
		end
		local na = Items[a.itemId] and Items[a.itemId].name or a.itemId
		local nb = Items[b.itemId] and Items[b.itemId].name or b.itemId
		if na ~= nb then
			return na < nb
		end
		return a.uid < b.uid
	end)
	return list
end

local function usedSlots(): number
	local used = 0
	for _, item in ClientState.Get("inventory") or {} do
		if type(item) == "table" and not NOT_COUNTED[item.state] then
			used += 1
		end
	end
	return used
end

-- ===== "Inventory full" chip (top chip row, stays while every slot is used) =====
-- A HUD chip like the Day / Invite chips (HudKit.Chip in HudLayoutController's HudTop.TopChips): "INVENTORY FULL"
-- over "16/16 · Sell items"; tapping it opens Inventory. Hidden while the Inventory window is open (Sean, 2026-11-25:
-- replaces the red banner so it matches the rest of the HUD).

local fullChip: { [string]: any }? = nil
local chipShown = false

local function buildFullChip(playerGui: Instance)
	local top = playerGui:FindFirstChild("HudTop")
	local row = top and top:WaitForChild("TopChips", 10)
	if row == nil then
		warn("[InventoryController] HudTop.TopChips not found: no inventory-full chip")
		return
	end
	local chip = HudKit.Chip(row, {
		name = "InventoryFullChip", art = "Inventory", sub = "INVENTORY FULL", title = "Sell items", clickable = true,
	})
	local frame: any = chip.Frame
	frame.LayoutOrder = 3
	frame.Visible = false
	frame.Activated:Connect(function()
		InventoryController.Open() -- the "Sell unrestored…" button is right there
	end)
	fullChip = chip
end

local function updateBanner()
	local chip = fullChip
	if chip == nil then
		return
	end
	local used, max = usedSlots(), capacity()
	local show = used >= max and not (inventoryGui ~= nil and inventoryGui.Window.Visible)
	chip.SetTexts("INVENTORY FULL", `{used}/{max} · Sell items`)
	chip.Frame.Visible = show
	if show ~= chipShown then
		chipShown = show
		log(if show then "inventory full: chip shown" else "inventory has room: chip hidden")
	end
end

local function updateCapacity()
	updateBanner()
	if inventoryGui == nil then
		return
	end
	local used = usedSlots()
	local max = capacity()
	local label = inventoryGui.Window.Capacity
	label.Text = `{used} / {max}`
	label.TextColor3 = if used >= max then UiTheme.Coral else CREAM
end

-- One Figma "Item Card" (91:6033): rarity-stroked walnut card on an ink lip, the item's model, name, one state line
-- (DIRTY tag / stars / progress bar / shelf tag) and the price; golden items get a gold badge in the corner.
local function buildCard(item, order: number): ImageButton
	local def = Items[item.itemId]
	local rarity = rarityOf(item)
	local card = new("ImageButton", {
		Name = "Card", LayoutOrder = order, BackgroundTransparency = 1, Image = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(CARD.X, CARD.Y + 4), ZIndex = 2,
	})
	local lip = new("Frame", { Name = "Lip", BackgroundColor3 = INK, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(CARD.X, CARD.Y), ZIndex = 2 }, card)
	round(lip, 12)
	local surface = new("Frame", { Name = "Surface", BackgroundColor3 = WALNUT_LIGHT, BorderSizePixel = 0, Size = UDim2.fromOffset(CARD.X, CARD.Y), ZIndex = 3 }, card)
	round(surface, 12)
	local stroke = outline(surface, if item.golden then GOLD else UiTheme.rarityColor(rarity), 3)
	stroke.Name = "RarityStroke"
	local art = new("Frame", { Name = "Art", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 2), Size = UDim2.fromOffset(46, 44), ZIndex = 4 }, card)
	cardArt(art, item.itemId)
	if item.state == "Dirty" then
		dirt(art)
	end
	text(card, {
		Name = "ItemName", Text = def and def.name or item.itemId, Position = UDim2.fromOffset(2, 44), Size = UDim2.fromOffset(CARD.X - 4, 15),
		TextSize = 10.5, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5,
	})
	-- the state line
	if item.state == "Dirty" or item.state == "Displayed" or item.state == "Exhibited" then
		local tagText = if item.state == "Dirty" then "DIRTY" elseif item.state == "Displayed" then "ON SHELF" else "EXHIBIT"
		local tagColor = if item.state == "Dirty" then TAG_BROWN elseif item.state == "Displayed" then Color3.fromRGB(11, 127, 108) else Color3.fromRGB(90, 58, 196)
		local tag = text(card, {
			Name = "StateTag", Text = tagText, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(46, 11),
			BackgroundTransparency = 0, BackgroundColor3 = tagColor, TextSize = 8.5, ZIndex = 5,
		})
		round(tag, 6)
		outline(tag, INK, 1.5)
	elseif item.state == "InProgress" then
		local recipe = def and def.recipe or {}
		local done = math.clamp(((item.stepIndex or 1) - 1) / math.max(#recipe, 1), 0.08, 1)
		local track = new("Frame", { Name = "Progress", BackgroundColor3 = INK, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 62), Size = UDim2.fromOffset(50, 7), ZIndex = 5 }, card)
		round(track, 4)
		local fill = new("Frame", { Name = "Fill", BackgroundColor3 = PROGRESS, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(done, -2, 1, -2), ZIndex = 6 }, track)
		round(fill, 3)
	elseif type(item.stars) == "number" then
		for i = 1, 3 do
			new("ImageLabel", {
				Name = "Star" .. i, BackgroundTransparency = 1, Image = UiSkin.Art("Star"), ImageTransparency = if i <= item.stars then 0 else 0.7,
				Position = UDim2.fromOffset(18 + (i - 1) * 13, 59), Size = UDim2.fromOffset(12, 12), ZIndex = 5,
			}, card)
		end
	end
	local value = itemValue(item)
	text(card, { Name = "Value", Text = `${value}`, Position = UDim2.fromOffset(2, 70), Size = UDim2.fromOffset(CARD.X - 4, 12), FontFace = FONT_TITLE, TextSize = 11, TextColor3 = GOLD, ZIndex = 5 })
	if item.golden then
		local badge = new("Frame", { Name = "GoldenTag", BackgroundColor3 = GOLD, BorderSizePixel = 0, Position = UDim2.fromOffset(CARD.X - 18, -4), Size = UDim2.fromOffset(16, 16), ZIndex = 7 }, card)
		round(badge, 8)
		outline(badge, INK, 1.5)
		new("ImageLabel", { BackgroundTransparency = 1, Image = UiSkin.Art("Star"), Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(12, 12), ZIndex = 8 }, badge)
	end
	-- the white "selected" ring and the green "picked" tick (Sell unrestored mode); shown by refreshMarks
	local ring = new("Frame", { Name = "Selected", BackgroundTransparency = 1, Position = UDim2.fromOffset(-3, -3), Size = UDim2.fromOffset(CARD.X + 6, CARD.Y + 6), Visible = false, ZIndex = 9 }, card)
	round(ring, 15)
	outline(ring, Color3.new(1, 1, 1), 3)
	-- Sell unrestored: a gold "$" coin in the corner and a gold outline = this item is in the sale (refreshMarks)
	local pickedRing = new("Frame", { Name = "Picked", BackgroundTransparency = 1, Position = UDim2.fromOffset(-3, -3), Size = UDim2.fromOffset(CARD.X + 6, CARD.Y + 6), Visible = false, ZIndex = 9 }, card)
	round(pickedRing, 15)
	outline(pickedRing, GOLD, 3.5)
	local coin = new("Frame", {
		Name = "Coin", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = GOLD, BorderSizePixel = 0, Position = UDim2.fromOffset(CARD.X - 6, 6),
		Size = UDim2.fromOffset(24, 24), Visible = false, ZIndex = 10,
	}, card)
	round(coin, 12)
	outline(coin, INK, 2)
	new("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = UiSkin.Art("Cash"), ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), ZIndex = 11,
	}, coin)
	return card
end

-- Selection ring and pick ticks, without rebuilding the cards (and their 3D models).
local function refreshMarks()
	for uid, card in cards do
		local ring = card:FindFirstChild("Selected")
		local isPicked = disposeMode and picked[uid] == true
		if ring then
			(ring :: Frame).Visible = not disposeMode and uid == selectedUid
		end
		for _, name in { "Picked", "Coin" } do
			local mark = card:FindFirstChild(name)
			if mark then
				(mark :: GuiObject).Visible = isPicked
			end
		end
		-- the golden badge sits in the same corner: hide it while the coin is there
		local golden = card:FindFirstChild("GoldenTag")
		if golden then
			(golden :: GuiObject).Visible = not isPicked
		end
	end
end

-- "All  12" / "Needs Restoring  5" / "Restored  7"; gold = the tab you are on (Figma "Win Tab").
local function refreshTabs()
	if inventoryGui == nil then
		return
	end
	local counts = {}
	for name in TAB_LABELS do
		counts[name] = #sortedItems(name)
	end
	for _, tab in inventoryGui.Window.Tabs:GetChildren() do
		if tab:IsA("TextButton") and TAB_LABELS[tab.Name] then
			tab.Text = `{TAB_LABELS[tab.Name]}  {counts[tab.Name]}`
			-- hug the text like the design (14 px Oswald + 14 px padding each side)
			local width = TextService:GetTextSize(tab.Text, 14, Enum.Font.Oswald, Vector2.new(400, 30)).X
			tab.Size = UDim2.fromOffset(math.ceil(width) + 28, 30)
			WindowKit.Chunky(tab, if tab.Name == currentFilter then WindowKit.BUTTON.Gold else WindowKit.BUTTON.Walnut, 14, 12)
		end
	end
end

local function renderGrid()
	if inventoryGui == nil then
		return
	end
	local grid = inventoryGui.Window.Grid
	-- Rebuild all cards (at most 40 items); selection changes only move the ring (refreshMarks).
	for _, child in grid:GetChildren() do
		if child.Name == "Card" then
			child:Destroy()
		end
	end
	table.clear(cards)
	local list = sortedItems(if disposeMode then "DirtyOnly" else currentFilter)
	for uid in picked do -- forget picks that are no longer Dirty (disposed, restored, gone)
		local it = ClientState.Get("inventory." .. uid)
		if type(it) ~= "table" or it.state ~= "Dirty" then
			picked[uid] = nil
		end
	end
	inventoryGui.Window.Empty.Visible = #list == 0 -- lives on Window: the grid layout would squeeze it into a cell
	for order, item in list do
		local card = buildCard(item, order)
		local uid = item.uid
		cards[uid] = card
		card.Activated:Connect(function()
			if disposeMode then
				picked[uid] = if picked[uid] then nil else true
				confirmUntil = 0
				refreshMarks()
				updateDetails()
				return
			end
			selectedUid = uid
			soldMessageUntil = 0
			refreshMarks()
			updateDetails()
		end)
		card.Parent = grid
	end
	refreshMarks()
	refreshTabs()
	updateCapacity()
	updateDetails()
end

local function selectTab(name: string)
	if FILTERS[name] == nil or inventoryGui == nil then
		return
	end
	currentFilter = name
	renderGrid() -- redraws the tabs too (gold = this one)
end

-- ===== Quick Sell =====

local function onRestore()
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if type(item) ~= "table" or (item.state ~= "Dirty" and item.state ~= "InProgress") or not restorationReady() then
		return
	end
	local uid = selectedUid :: string
	InventoryController.Close() -- the Restoration screen takes over (RestorationUIController)
	others.RestorationController.RequestStartRestore(uid)
	log("asked to restore", uid)
end

-- The old Quick Sell button: restored items can't be sold from here any more, so it only explains where to sell them.
local function onQuickSell()
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if type(item) ~= "table" or item.state ~= "Restored" then
		return
	end
	local text = "⚠ Restored items can only be sold on a display shelf. Put it on one and customers will buy it!"
	if others and others.HudController and others.HudController.Notify then
		others.HudController.Notify("Info", text)
	end
	log("quick sell tapped: restored items sell on shelves only")
end

local function onSaleMade(amount: any)
	selling = false
	if inventoryGui == nil or type(amount) ~= "number" then
		return
	end
	if inventoryGui.Window.Visible then
		local details = inventoryGui.Window.Details
		setDetailsVisible(details, false)
		details.Hint.Text = `Sold for ${amount}!`
		soldMessageUntil = os.clock() + SOLD_MESSAGE_SECONDS
		task.delay(SOLD_MESSAGE_SECONDS, updateDetails)
	end
end

-- ===== Dispose (throw away Dirty items, ~40% of their estimated value) =====

local savedTitle: string? = nil

local function setDisposeMode(on: boolean)
	if inventoryGui == nil or disposeUi == nil then
		return
	end
	disposeMode = on
	table.clear(picked)
	confirmUntil = 0
	selectedUid = nil
	local window = inventoryGui.Window
	if on then
		savedTitle = window.Title.Text
	end
	window.Title.Text = if on then "Sell unrestored" else (savedTitle or window.Title.Text)
	window.Tabs.Visible = not on and pickTarget == nil
	window.Empty.Text = if on then "No unrestored items to sell." else "Nothing here yet. Open boxes at your door!"
	window.Details.Hint.Size = if on then UDim2.new(1, -24, 0, 118) else UDim2.new(1, -24, 0, 60)
	disposeUi.mode.Text = if on then "Done" else "Sell unrestored…"
	WindowKit.Chunky(disposeUi.mode, if on then WindowKit.BUTTON.Gold else WindowKit.BUTTON.Walnut, 14, 12)
	renderGrid()
end

-- Two taps: the first arms the button ("Tap again to confirm"), the second within 3 s goes through.
local function armed(): boolean
	if os.clock() < confirmUntil then
		confirmUntil = 0
		return true
	end
	confirmUntil = os.clock() + 3
	updateDetails()
	task.delay(3.05, updateDetails)
	return false
end

local function sendDispose(uids: { string })
	if #uids == 0 then
		return
	end
	Remotes.RequestDisposeItems:FireServer(uids)
	log("asked to dispose", #uids, "item(s)")
	table.clear(picked)
	selectedUid = nil
	-- the inventory change from the server redraws the grid and the details
end

local function buildDisposeUi()
	if disposeUi or inventoryGui == nil then
		return
	end
	local window = inventoryGui.Window
	local details = window.Details
	local function button(name: string, parent: Instance, props: { [string]: any }): TextButton
		local b = new("TextButton", { Name = name, Text = "", Visible = false, AutoButtonColor = false, ZIndex = 4 }, parent)
		for k, v in props do
			(b :: any)[k] = v
		end
		return b
	end
	-- "Sell unrestored…" sits in the tab row, right above the details panel
	local mode = button("DisposeModeButton", window, { Position = UDim2.fromOffset(345, 48), Size = UDim2.fromOffset(198, 30), Text = "Sell unrestored…" })
	WindowKit.Chunky(mode, WindowKit.BUTTON.Walnut, 14, 12)
	mode.Visible = pickTarget == nil
	local single = button("DisposeButton", details, { Position = UDim2.fromOffset(118, 179), Size = UDim2.fromOffset(72, 30) })
	WindowKit.Chunky(single, WindowKit.BUTTON.Danger, 13, 12)
	local selCommon = button("SelectCommonButton", details, { Position = UDim2.fromOffset(8, 136), Size = UDim2.new(1, -16, 0, 30) })
	WindowKit.Chunky(selCommon, WindowKit.BUTTON.Primary, 14, 12)
	local confirm = button("DisposeConfirmButton", details, { Position = UDim2.fromOffset(8, 176), Size = UDim2.new(1, -16, 0, 36) })
	WindowKit.Chunky(confirm, WindowKit.BUTTON.Danger, 16, 13)
	disposeUi = { mode = mode, single = single, selCommon = selCommon, confirm = confirm }

	mode.Activated:Connect(function()
		setDisposeMode(not disposeMode)
	end)
	single.Activated:Connect(function()
		local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
		if type(item) == "table" and item.state == "Dirty" and armed() then
			sendDispose({ selectedUid :: string })
		end
	end)
	selCommon.Activated:Connect(function()
		local commons, allPicked = {}, true
		for _, item in sortedItems("DirtyOnly") do
			if Rarities[rarityOf(item)].index == 1 and item.golden ~= true then
				table.insert(commons, item.uid)
				allPicked = allPicked and picked[item.uid] == true
			end
		end
		for _, uid in commons do
			picked[uid] = if allPicked then nil else true -- tap again to clear them
		end
		confirmUntil = 0
		refreshMarks()
		updateDetails()
	end)
	confirm.Activated:Connect(function()
		local uids = {}
		for uid in picked do
			table.insert(uids, uid)
		end
		if #uids > 0 and armed() then
			sendDispose(uids)
		end
	end)
end

-- ===== Open / close (only one modal at a time, docs/01 J4) =====

function InventoryController.IsOpen(): boolean
	return inventoryGui ~= nil and inventoryGui.Window.Visible
end

-- Leaves picker mode and puts the normal title and tabs back.
local function endPicker()
	pickTarget = nil
	placingUid = nil
	if inventoryGui then
		inventoryGui.Window.Title.Text = "🎒 Inventory"
		inventoryGui.Window.Tabs.Visible = true
		inventoryGui.Window.Empty.Text = "Nothing here yet. Open boxes at your door!"
	end
end

function InventoryController.Close()
	if inventoryGui then
		if disposeMode then
			setDisposeMode(false)
		end
		inventoryGui.Window.Visible = false
	end
	endPicker()
end

local openWindow -- forward declaration (defined below, used by OpenPicker)

function InventoryController.Open(filter: string?)
	endPicker() -- opened from the HUD or the counter: normal mode
	openWindow(filter)
end

-- Opened by DisplayController from an empty slot in my shop: choose a Restored item for that slot.
function InventoryController.OpenPicker(kind: string, slotIndex: number, label: string)
	if inventoryGui == nil or (kind ~= "Display" and kind ~= "Exhibit") then
		return
	end
	endPicker()
	pickTarget = { kind = kind, slotIndex = slotIndex, label = label }
	selectedUid = nil
	inventoryGui.Window.Title.Text = `Choose for {label}`
	inventoryGui.Window.Tabs.Visible = false -- only Restored items can go on a slot
	inventoryGui.Window.Empty.Text = "No restored items yet."
	openWindow("Restored")
end

local function onPlace()
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if pickTarget == nil or placingUid or type(item) ~= "table" or item.state ~= "Restored" then
		return
	end
	placingUid = selectedUid
	updateDetails() -- "Placing…" right away (docs/01 J4)
	local remote = if pickTarget.kind == "Exhibit" then Remotes.RequestPlaceExhibit else Remotes.RequestPlaceDisplay
	remote:FireServer(selectedUid, pickTarget.slotIndex)
	log("asked to place", selectedUid, "on", pickTarget.kind, pickTarget.slotIndex)
	-- If the server refuses (slot taken, too far…) a toast explains it; unlock the button after a moment.
	local uid = placingUid
	task.delay(2, function()
		if placingUid == uid then
			placingUid = nil
			updateDetails()
		end
	end)
end

openWindow = function(filter: string?)
	if inventoryGui == nil then
		return
	end
	local discovery = others and others.DiscoveryController
	if discovery and discovery.IsOpen and discovery.IsOpen() then
		return -- finish the reveal first
	end
	local shop = others and others.ShopController
	if shop and shop.CloseAll then
		shop.CloseAll() -- Supply + Upgrades
	end
	buildDisposeUi() -- first time only
	selectTab(filter or currentFilter)
	inventoryGui.Window.Visible = true
	log("opened on", currentFilter)

	-- While open, keep the Quick Sell button honest as the player walks to/from the counter.
	task.spawn(function()
		while InventoryController.IsOpen() do
			updateDetails()
			task.wait(NEAR_CHECK_SECONDS)
		end
	end)
end

-- ===== My plot (Counter prompt) =====

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

-- Every counter has a QuickSellPrompt ("Quick Sell" [Q]). Removed from the counter (Sean, 2026-11-25): it is switched
-- off on every counter, mine included, and kept off. Restored items still sell from the Inventory window (Quick Sell
-- button) or to customers. The prompt stays in the place, so this is easy to undo.
local function hookCounters()
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	local function switchOff(prompt: Instance)
		if prompt.Name == "QuickSellPrompt" and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
			prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
				if prompt.Enabled then
					prompt.Enabled = false
				end
			end)
		end
	end
	for _, d in plots:GetDescendants() do
		switchOff(d)
	end
	-- other shops' counters stream in (and back in) later: catch their prompts as they arrive
	plots.DescendantAdded:Connect(switchOff)
end

-- ===== Lifecycle =====

function InventoryController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function InventoryController.Start()
	log("Start")
	Remotes.SaleMade.OnClientEvent:Connect(onSaleMade)
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		inventoryGui = playerGui:WaitForChild("Inventory", 10) :: ScreenGui?
		if inventoryGui == nil then
			warn("[InventoryController] PlayerGui.Inventory not found: is StarterGui.Inventory missing?")
			return
		end
		local window = inventoryGui.Window
		applyFigmaLayout(window)
		-- load the card icons in the background now, so the first open doesn't show empty cards
		task.spawn(function()
			local ids = {}
			for _, id in ItemIcons do
				table.insert(ids, id)
			end
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(ids)
			end)
		end)
		window.CloseButton.Activated:Connect(InventoryController.Close)
		for _, tab in window.Tabs:GetChildren() do
			if tab:IsA("TextButton") then
				tab.Activated:Connect(function()
					selectTab(tab.Name)
				end)
			end
		end
		window.Details.QuickSellButton.Activated:Connect(onQuickSell)
		window.Details.PlaceButton.Activated:Connect(onPlace)
		window.Details.RestoreButton.Activated:Connect(onRestore)

		ClientState.OnChanged("inventory", function()
			selling = false
			-- Placed: the item is now Displayed/Exhibited, so the picker's job is done.
			if placingUid then
				local placed = ClientState.Get("inventory." .. placingUid)
				if type(placed) ~= "table" or placed.state ~= "Restored" then
					log("placed", placingUid)
					InventoryController.Close()
					return
				end
			end
			renderGrid()
		end)
		ClientState.OnChanged("upgrades", updateCapacity)
		window:GetPropertyChangedSignal("Visible"):Connect(updateBanner)
		selectTab("All")
		-- HudTop is made by HudLayoutController, which starts after this controller: wait a little for it
		task.spawn(function()
			playerGui:WaitForChild("HudTop", 10)
			buildFullChip(playerGui)
			updateBanner()
		end)

		local hud = playerGui:WaitForChild("HUD", 10)
		local hudButton = hud and hud:FindFirstChild("LeftButtons") and hud.LeftButtons:FindFirstChild("Inventory")
		if hudButton then
			hudButton.Activated:Connect(function()
				if InventoryController.IsOpen() then
					InventoryController.Close()
				else
					InventoryController.Open()
				end
			end)
		end

		hookCounters()
		myPlot = waitForMyPlot()
		log("ready", myPlot and myPlot.Name or "(no plot)")
	end)
end

return InventoryController
