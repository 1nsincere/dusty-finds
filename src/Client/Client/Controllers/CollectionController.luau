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

local function drawEntry(card: Frame, def, entry)
	local found = type(entry) == "table" and entry.found == true
	local golden = found and entry.golden == true
	local stars = if found and type(entry.bestStars) == "number" then entry.bestStars else 0
	local color = UiTheme.rarityColor(def.rarity)

	card.Icon.BackgroundColor3 = if found then color else NOT_FOUND_COLOR
	card.Icon.Text = if found then string.sub(def.name, 1, 1) else "?"
	card.ItemName.Text = if found then def.name else "???"
	card.Info.Text = if not found then def.rarity -- a hint of what's still out there
		elseif stars > 0 then starsText(stars)
		else "Found"
	card.Info.TextColor3 = if found and stars > 0 then UiTheme.Coral else color
	card.RarityStroke.Color = if golden then UiTheme.Golden elseif found then color else NOT_FOUND_STROKE
	card.RarityStroke.Thickness = if golden then 3 else 2
	card.GoldenTag.Visible = golden
end

local function render()
	if collectionGui == nil or #pages == 0 then
		return
	end
	local book = collectionGui.Book
	local collection = ClientState.Get("collection") or {}
	local page = pages[pageIndex]

	for _, child in book.Grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local template = collectionGui.EntryTemplate
	for index, def in page.items do
		local card = template:Clone()
		card.Name = def.id
		card.LayoutOrder = index
		card.Visible = true
		drawEntry(card, def, collection[def.id])
		card.Parent = book.Grid
	end

	local total, totalFound = 0, 0
	for _, p in pages do
		total += #p.items
		totalFound += countFound(p.items, collection)
	end
	book.Title.Text = `📖 Collection {totalFound}/{total}`
	book.PageLabel.Text = `{page.name} · {countFound(page.items, collection)}/{#page.items} found`
	book.PrevButton.Visible = pageIndex > 1
	book.NextButton.Visible = pageIndex < #pages
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
