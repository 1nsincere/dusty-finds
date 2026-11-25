-- InventoryController.luau
-- Purpose: Inventory screen: grid of my items (from ClientState) with filters and capacity, a details panel per
-- item. Restored items sell ONLY on a display shelf (Quick Sell is off, Sean + Ace 2026-11-25: the old button now says so).
-- "Sell unrestored…" (Ace's Dispose, RequestDisposeItems) sells many Dirty items at once. The server checks state and
-- price; this screen only shows and requests. Opens from HUD 🎒 (the counter's QuickSellPrompt is switched off, 2026-11-25).
-- Also the "Inventory full" banner at the top of the screen while every slot is used (InventoryFull, code-built).
-- Picker mode (OpenPicker, called by DisplayController from an empty slot): choose a Restored item and send
-- RequestPlaceDisplay / RequestPlaceExhibit for that slot.
-- Restore (Dirty/InProgress) calls Dev 2's RestorationController.RequestStartRestore(uid); greyed until that exists.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Remotes, Shared.Formulas,
-- Shared.Config (Items, Rarities, Economy), StarterGui.Inventory, ReplicatedStorage.Assets.UI.ItemCard,
-- Workspace.Plots (OwnerUserId attribute, Counter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Items = require(Config:WaitForChild("Items"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Economy = require(Config:WaitForChild("Economy"))

local InventoryController = {}
local DEBUG = true

local ESTIMATE_STARS = 2 -- value shown for items not restored yet ("~$X" at 2★, same as the Discovery card)
local NEAR_CHECK_SECONDS = 0.5 -- how often the details panel refreshes while the window is open
local BANNER_HEIGHT = 40 -- the "Inventory full" banner (reference px); the notification dock moves down by this + a gap
local BANNER_GAP = 6
local SOLD_MESSAGE_SECONDS = 2

-- States that don't use inventory space. Mirrors InventoryService (docs/08 §2).
local NOT_COUNTED = { Unopened = true, Displayed = true, Exhibited = true }
local STATE_ICONS = {
	Dirty = "🧽",
	InProgress = "🔧",
	Restored = "✨",
	Displayed = "🏷️",
	Exhibited = "🏆",
}
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
	ui.selCommon.BackgroundColor3 = UiTheme.Teal
	ui.confirm.Visible = true
	local sure = os.clock() < confirmUntil
	ui.confirm.Text = if n == 0 then "Pick items first" elseif sure then "Tap again to confirm" else `Sell {n} · +${total}`
	ui.confirm.BackgroundColor3 = if n == 0 then UiTheme.Disabled else UiTheme.Coral
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
	setDetailsVisible(details, true)
	details.ItemName.Text = (def and def.name or item.itemId) .. (if item.golden then " 🌟" else "")
	details.Rarity.Text = string.upper(rarity) .. (if item.golden then " · GOLDEN" else "")
	details.Rarity.TextColor3 = UiTheme.rarityColor(rarity)
	local stateText = STATE_TEXT[item.state] or item.state
	details.Info.Text = if type(item.stars) == "number" then `{stateText} · {starsText(item.stars)}` else stateText
	local value, estimate = itemValue(item)
	details.Value.Text = if estimate then `Est. value ${value}` else `Value ${value}`

	-- Quick Sell is off (Sean + Ace 2026-11-25): restored items sell only on a display shelf. The button stays as a
	-- greyed warning so players learn where to sell; tapping it explains (onQuickSell).
	local quickSell = details.QuickSellButton :: TextButton
	quickSell.Visible = item.state == "Restored" and type(item.stars) == "number"
	if quickSell.Visible then
		quickSell.Text = "⚠ Sell on a shelf"
		quickSell.BackgroundColor3 = UiTheme.Disabled
	end
	-- Restore hands over to Dev 2's RestorationController; greyed until that controller offers RequestStartRestore.
	local restore = details.RestoreButton :: TextButton
	restore.Visible = item.state == "Dirty" or item.state == "InProgress"
	local canRestore = restorationReady()
	restore.Text = if item.state == "InProgress" then "Continue" else "Restore"
	restore.BackgroundColor3 = if canRestore then UiTheme.Coral else UiTheme.Disabled
	restore.AutoButtonColor = canRestore

	-- Dispose (one item): only Dirty items, two taps (the second confirms).
	if disposeUi then
		local single = disposeUi.single
		single.Visible = item.state == "Dirty" and pickTarget == nil
		if single.Visible then
			local sure = os.clock() < confirmUntil
			single.Text = if sure then "Tap again to confirm" else `Sell +${Formulas.disposePrice(item.itemId, item.golden)}`
			single.BackgroundColor3 = if sure then UiTheme.Coral else UiTheme.Disabled
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

-- ===== "Inventory full" banner (top of the screen, stays while every slot is used) =====
-- Code-built, under the top chips in HudLayoutController's HudTop screen (so it scales with the HUD); its own screen
-- if HudTop isn't there. Hidden while the Inventory window is open (the player is already dealing with it).

local banner: Frame? = nil
local bannerShown = false

local function buildBanner(playerGui: Instance)
	local top = playerGui:FindFirstChild("HudTop")
	local parent: Instance
	if top and top:IsA("ScreenGui") then
		parent = top
	else
		local own = Instance.new("ScreenGui")
		own.Name = "InventoryFull"
		own.IgnoreGuiInset = true
		own.ResetOnSpawn = false
		own.DisplayOrder = 1
		own.Parent = playerGui
		parent = own
	end
	local frame = Instance.new("Frame")
	frame.Name = "InventoryFullBanner"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 54) -- just under the top chips (they sit at y 8, 40 tall)
	frame.Size = UDim2.fromOffset(400, BANNER_HEIGHT)
	frame.BackgroundColor3 = UiTheme.Coral
	frame.Visible = false
	frame.ZIndex = 5
	Instance.new("UICorner", frame).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(43, 26, 18)
	stroke.Thickness = 2.5
	stroke.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(16, 0)
	text.Size = UDim2.new(1, -128, 1, 0)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = "🎒 Inventory full! Go sell items to open more boxes"
	text.ZIndex = 6
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = 18
	textSize.Parent = text
	text.Parent = frame

	local button = Instance.new("TextButton")
	button.Name = "OpenButton"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -6, 0.5, 0)
	button.Size = UDim2.fromOffset(104, BANNER_HEIGHT - 10)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = UiTheme.Coral
	button.Text = "Sell items"
	button.ZIndex = 6
	Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
	local buttonSize = Instance.new("UITextSizeConstraint")
	buttonSize.MaxTextSize = 16
	buttonSize.Parent = button
	button.Parent = frame
	button.Activated:Connect(function()
		InventoryController.Open() -- the "Sell unrestored…" button is right there
	end)

	frame.Parent = parent
	banner = frame
end

local function updateBanner()
	if banner == nil then
		return
	end
	local full = usedSlots() >= capacity()
	local show = full and not (inventoryGui ~= nil and inventoryGui.Window.Visible)
	banner.Visible = show
	if show ~= bannerShown then
		bannerShown = show
		local layout = others and others.HudLayoutController
		if layout and layout.SetTopBannerRoom then
			layout.SetTopBannerRoom(if show then BANNER_HEIGHT + BANNER_GAP else 0)
		end
		log(if show then "inventory full: banner up" else "inventory has room: banner hidden")
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
	label.Text = `{used}/{max}`
	label.TextColor3 = if used >= max then UiTheme.Coral else UiTheme.Teal
end

local function renderGrid()
	if inventoryGui == nil then
		return
	end
	local grid = inventoryGui.Window.Grid
	local template = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("UI")
		and ReplicatedStorage.Assets.UI:FindFirstChild("ItemCard")
	if template == nil then
		warn("[InventoryController] ReplicatedStorage.Assets.UI.ItemCard is missing")
		return
	end
	-- Simple and safe: rebuild all cards (at most 40 items).
	for _, child in grid:GetChildren() do
		if child.Name == "Card" then
			child:Destroy()
		end
	end
	local list = sortedItems(if disposeMode then "DirtyOnly" else currentFilter)
	for uid in picked do -- forget picks that are no longer Dirty (disposed, restored, gone)
		local it = ClientState.Get("inventory." .. uid)
		if type(it) ~= "table" or it.state ~= "Dirty" then
			picked[uid] = nil
		end
	end
	inventoryGui.Window.Empty.Visible = #list == 0 -- lives on Window: the grid layout would squeeze it into a cell
	for order, item in list do
		local def = Items[item.itemId]
		local rarity = rarityOf(item)
		local card = template:Clone()
		card.Name = "Card"
		card.LayoutOrder = order
		card.RarityStroke.Color = UiTheme.rarityColor(rarity)
		card.RarityStroke.Thickness = if item.uid == selectedUid then 5 else 3
		card.StateIcon.Text = STATE_ICONS[item.state] or ""
		card.GoldenTag.Visible = item.golden == true
		card.ItemName.Text = def and def.name or item.itemId
		card.Stars.Text = if type(item.stars) == "number" then starsText(item.stars) else ""
		local value, estimate = itemValue(item)
		card.Value.Text = if estimate then `~${value}` else `${value}`
		local uid = item.uid
		if disposeMode then
			if picked[uid] then
				card.RarityStroke.Thickness = 5
				local tick = Instance.new("TextLabel")
				tick.Name = "Tick"
				tick.AnchorPoint = Vector2.new(1, 0)
				tick.Position = UDim2.new(1, -3, 0, 3)
				tick.Size = UDim2.fromOffset(24, 24)
				tick.BackgroundColor3 = UiTheme.Teal
				tick.TextColor3 = Color3.new(1, 1, 1)
				tick.Text = "✔"
				tick.TextSize = 16
				tick.ZIndex = 20
				Instance.new("UICorner", tick).CornerRadius = UDim.new(1, 0)
				tick.Parent = card
			end
			if item.golden or Rarities[rarityOf(item)].index >= 3 then
				card.StateIcon.Text = "⚠" -- rare or golden: think twice
			end
		end
		card.Activated:Connect(function()
			if disposeMode then
				picked[uid] = if picked[uid] then nil else true
				confirmUntil = 0
				renderGrid()
				return
			end
			selectedUid = uid
			soldMessageUntil = 0
			renderGrid() -- redraw the selection outline
			updateDetails()
		end)
		card.Parent = grid
	end
	updateCapacity()
	updateDetails()
end

local function selectTab(name: string)
	if FILTERS[name] == nil or inventoryGui == nil then
		return
	end
	currentFilter = name
	for _, tab in inventoryGui.Window.Tabs:GetChildren() do
		if tab:IsA("TextButton") then
			tab.BackgroundColor3 = if tab.Name == name then UiTheme.Teal else UiTheme.Disabled
		end
	end
	renderGrid()
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
	window.Details.Hint.Size = if on then UDim2.new(1, -20, 0, 120) else UDim2.new(1, -20, 0, 40)
	disposeUi.mode.Text = if on then "Done" else "Sell unrestored…"
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
	-- Cloned from existing (already skinned) buttons so they look like the rest of the window
	local function clone(from: GuiButton, name: string, parent: Instance): TextButton
		local b = from:Clone() :: TextButton
		b.Name = name
		b.Visible = false
		b.Parent = parent
		return b
	end
	local tab = window.Tabs:FindFirstChildWhichIsA("TextButton")
	local mode = clone(tab or details.QuickSellButton, "DisposeModeButton", window)
	mode.AnchorPoint = Vector2.new(0, 0)
	mode.Position = UDim2.fromOffset(300, 12)
	mode.Size = UDim2.fromOffset(160, 30) -- ends at x 460, well before the close button
	mode.Text = "Sell unrestored…"
	mode.BackgroundColor3 = UiTheme.Disabled
	mode.Visible = pickTarget == nil
	local single = clone(details.QuickSellButton, "DisposeButton", details)
	local selCommon = clone(details.QuickSellButton, "SelectCommonButton", details)
	local confirm = clone(details.RestoreButton, "DisposeConfirmButton", details)
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
		renderGrid()
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
			buildBanner(playerGui)
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
