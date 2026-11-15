-- ShopController.luau
-- Purpose: Supply Board screen: lists the crates from Config/Crates with price, item count and odds, and
-- asks the server to buy one (RequestBuyCrate). Opens from my plot's SupplyBoard prompt or the HUD 📦 button.
-- The server rolls, charges and refuses (toasts come from HudController); this screen only shows and requests.
-- Also the Upgrades screen (HUD 🔨): cards per upgrade in Config/Upgrades with level dots, next-level effect,
-- cost or lock reason, and RequestBuyUpgrade. The server re-checks all 5 rules (UpgradeService).
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Remotes, Shared.Config (Crates, Rarities,
-- Upgrades, Economy), StarterGui.Supply + StarterGui.Upgrades + HUD.LeftButtons.{Supply,Upgrades}
-- (UI contract, docs/03 §8), Workspace.Plots (OwnerUserId attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Crates = require(Shared:WaitForChild("Config"):WaitForChild("Crates"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

local ShopController = {}
local DEBUG = true

local BUY_COOLDOWN = 1.5 -- seconds the button shows "Ordering…" (also stops double taps)

-- Upgrades screen
local UPGRADE_TABS = { "Tools", "Shop", "Decor", "Expansions" } -- = `tab` field in Config/Upgrades
-- Expansion rooms are not cloned into the plot yet (Dev 1, docs/08 §7), so they can't be bought from the UI
-- yet: nobody should pay for a room they can't see. Remove this when Back Room / Showroom models exist.
local COMING_SOON_TABS = { Expansions = true }
local UPGRADE_ICONS = {
	CleaningBrush = "🧽", RepairToolkit = "🧰", Polisher = "✨",
	-- Only older emoji: Roblox's emoji font draws newer ones (e.g. 🪴 🪧) as empty squares.
	DisplayShelves = "🗄️", StorageRacks = "📦", ShopSign = "📢",
	PottedPlants = "🌿", Rug = "🟫", WallPosters = "🖼️", PendantLamps = "💡", NeonSign = "🌟",
	FishTank = "🐠", Fountain = "⛲",
	BackRoom = "🚪", Showroom = "🏛️",
}

local player = Players.LocalPlayer
local others = nil
local supply: ScreenGui? = nil
local cards: { [string]: Frame } = {} -- [crateId] = card
local ordering: { [string]: boolean } = {}
local upgradesGui: ScreenGui? = nil
local currentUpgradeTab = "Tools"
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
		if ordering[crateId] then
			continue
		end
		if level < crate.requiredLevel then
			button.Text = `Reach Lv {crate.requiredLevel}`
			button.BackgroundColor3 = UiTheme.Disabled
			button.AutoButtonColor = false
		else
			button.Text = `${crate.price}`
			button.BackgroundColor3 = UiTheme.Coral
			button.AutoButtonColor = true
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

local function buildCards()
	if supply == nil then
		return
	end
	local list = supply.Window.List
	local template = supply.CrateTemplate
	local rarities = rarityOrder()
	for order, crate in buyableCrates() do
		local card = template:Clone()
		card.Name = crate.id
		card.LayoutOrder = order
		card.Visible = true
		-- The label is called "Name", which clashes with the built-in Name property, so look it up as a child.
		(card:FindFirstChild("Name") :: TextLabel).Text = crate.name
		card.Info.Text = `{crate.itemCount} items · Tier {crate.tier}`

		-- Odds table: always visible before buying (docs/01 J3 "transparent odds").
		local odds = card.Odds
		local rowTemplate = odds.RowTemplate
		for i, rarity in rarities do
			local percent = crate.odds[rarity.id] or 0
			if percent > 0 then
				local row = rowTemplate:Clone()
				row.Name = rarity.id
				row.LayoutOrder = i
				row.Text = `● {rarity.id} {percent}%`
				row.TextColor3 = UiTheme.rarityColor(rarity.id)
				row.Visible = true
				row.Parent = odds
			end
		end

		card.BuyButton.Activated:Connect(function()
			onBuy(crate.id)
		end)
		card.Parent = list
		cards[crate.id] = card
	end
	refreshButtons()
end

-- ===== Open / close (only one modal at a time, docs/01 J4) =====

function ShopController.IsSupplyOpen(): boolean
	return supply ~= nil and supply.Window.Visible
end

function ShopController.OpenSupply()
	if supply == nil then
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
		if def.tab == tab then
			table.insert(list, def)
		end
	end
	-- Cheapest first-level cost first, so the list reads as a path from easy to big goals.
	table.sort(list, function(a, b)
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

function ShopController.OpenUpgrades()
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
	renderUpgrades()
	upgradesGui.Window.Visible = true
	log("Upgrades opened on", currentUpgradeTab)
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
	for _, tabName in UPGRADE_TABS do
		local tab = window.Tabs:FindFirstChild(tabName)
		if tab then
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
		buildCards()
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
