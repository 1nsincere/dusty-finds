-- ShopController.luau
-- Purpose: Supply Board screen: lists the crates from Config/Crates with price, item count and odds, and
-- asks the server to buy one (RequestBuyCrate). Opens from my plot's SupplyBoard prompt or the HUD 📦 button.
-- The server rolls, charges and refuses (toasts come from HudController); this screen only shows and requests.
-- Upgrades screen comes later in this same controller.
-- Owner: Dev 3 (Sean). Depends on: ClientState, UiTheme, Shared.Remotes, Shared.Config (Crates, Rarities),
-- StarterGui.Supply + HUD.LeftButtons.Supply (UI contract, docs/03 §8), Workspace.Plots (OwnerUserId attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Crates = require(Shared:WaitForChild("Config"):WaitForChild("Crates"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))

local ShopController = {}
local DEBUG = true

local BUY_COOLDOWN = 1.5 -- seconds the button shows "Ordering…" (also stops double taps)

local player = Players.LocalPlayer
local others = nil
local supply: ScreenGui? = nil
local cards: { [string]: Frame } = {} -- [crateId] = card
local ordering: { [string]: boolean } = {}

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
	refreshButtons()
	supply.Window.Visible = true
	log("Supply opened")
end

function ShopController.CloseSupply()
	if supply then
		supply.Window.Visible = false
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
