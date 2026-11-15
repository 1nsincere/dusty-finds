-- InventoryController.luau
-- Purpose: Inventory screen: grid of my items (from ClientState) with filters and capacity, a details panel per
-- item, and Quick Sell for Restored items at my counter (RequestQuickSell). The server checks state, distance and
-- price; this screen only shows and requests. Opens from HUD 🎒 or my Counter's QuickSellPrompt.
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
local NEAR_CHECK_SECONDS = 0.5 -- how often the Quick Sell button re-checks "am I at my counter?"
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
}

local player = Players.LocalPlayer
local others = nil
local inventoryGui: ScreenGui? = nil
local myPlot: Model? = nil
local currentFilter = "All"
local selectedUid: string? = nil
local selling = false
local soldMessageUntil = 0

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

-- ===== Am I at my counter? (server checks again; this only sets the button text) =====

local function nearMyCounter(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local counter = myPlot and myPlot:FindFirstChild("Counter")
	if root == nil or counter == nil or not counter:IsA("BasePart") then
		return false
	end
	return (root.Position - counter.Position).Magnitude <= Economy.InteractMaxStuds
end

-- ===== Details panel =====

local function setDetailsVisible(details: Frame, showItem: boolean)
	details.Hint.Visible = not showItem
	for _, name in { "ItemName", "Rarity", "Info", "Value" } do
		details[name].Visible = showItem
	end
	if not showItem then
		details.QuickSellButton.Visible = false
		details.RestoreButton.Visible = false
	end
end

local function updateDetails()
	if inventoryGui == nil then
		return
	end
	local details = inventoryGui.Window.Details
	if os.clock() < soldMessageUntil then
		return -- keep showing "Sold for $X!" for a moment
	end
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if type(item) ~= "table" or not FILTERS.All[item.state] then
		selectedUid = nil
		details.Hint.Text = "Tap an item to see what you can do."
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

	-- Quick Sell: only Restored items, only at my counter (docs/01 B10).
	local quickSell = details.QuickSellButton :: TextButton
	quickSell.Visible = item.state == "Restored" and type(item.stars) == "number"
	if quickSell.Visible then
		local price = Formulas.quickSellPrice(item.itemId, item.stars, item.golden)
		if selling then
			quickSell.Text = "Selling…"
			quickSell.BackgroundColor3 = UiTheme.Teal
		elseif nearMyCounter() then
			quickSell.Text = `Quick Sell ${price}`
			quickSell.BackgroundColor3 = UiTheme.Coral
		else
			quickSell.Text = "Sell at your counter"
			quickSell.BackgroundColor3 = UiTheme.Disabled
		end
	end
	-- Restore comes with Dev 2's restoration; until then it is a greyed placeholder.
	details.RestoreButton.Visible = item.state == "Dirty" or item.state == "InProgress"
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

local function updateCapacity()
	if inventoryGui == nil then
		return
	end
	local used = 0
	for _, item in ClientState.Get("inventory") or {} do
		if type(item) == "table" and not NOT_COUNTED[item.state] then
			used += 1
		end
	end
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
	local list = sortedItems(currentFilter)
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
		card.Activated:Connect(function()
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

local function onQuickSell()
	local item = selectedUid and ClientState.Get("inventory." .. selectedUid)
	if selling or type(item) ~= "table" or item.state ~= "Restored" or not nearMyCounter() then
		return
	end
	selling = true
	updateDetails() -- "Selling…" right away (docs/01 J4)
	Remotes.RequestQuickSell:FireServer(selectedUid)
	log("asked to quick sell", selectedUid)
	-- If the server refuses (too far, wrong state) nothing changes; unlock the button after a moment.
	task.delay(2, function()
		if selling then
			selling = false
			updateDetails()
		end
	end)
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

-- ===== Open / close (only one modal at a time, docs/01 J4) =====

function InventoryController.IsOpen(): boolean
	return inventoryGui ~= nil and inventoryGui.Window.Visible
end

function InventoryController.Close()
	if inventoryGui then
		inventoryGui.Window.Visible = false
	end
end

function InventoryController.Open(filter: string?)
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

-- Every counter has a QuickSellPrompt; only mine opens my inventory. Others' are hidden for me.
local function hookCounters()
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	for _, plot in plots:GetChildren() do
		local counter = plot:FindFirstChild("Counter")
		local prompt = counter and counter:FindFirstChild("QuickSellPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			local function updateEnabled()
				prompt.Enabled = plot:GetAttribute("OwnerUserId") == player.UserId
			end
			updateEnabled()
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(updateEnabled)
			prompt.Triggered:Connect(function()
				if plot:GetAttribute("OwnerUserId") == player.UserId then
					InventoryController.Open("Restored")
				end
			end)
		end
	end
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
		window.Details.RestoreButton.AutoButtonColor = false

		ClientState.OnChanged("inventory", function()
			selling = false
			renderGrid()
		end)
		ClientState.OnChanged("upgrades", updateCapacity)
		selectTab("All")

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
