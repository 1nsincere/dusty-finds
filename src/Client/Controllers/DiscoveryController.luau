-- DiscoveryController.luau
-- Purpose: shows my waiting boxes at my plot's DeliveryPoint (client-side, only I see them) and plays the reveal:
-- "Open" on a box asks the server to open each item (RequestOpenBox), and each BoxOpened result is shown on the
-- Discovery card (rarity, name, dots, est. value, NEW!/GOLDEN). The server already rolled the item; we only show it.
-- Owner: Dev 3 (Sean) UI, Dev 2 (Dwayne) VFX later. Depends on: ClientState, UiTheme, Shared.Remotes,
-- Shared.Config (Items, Rarities, Crates, Economy), Shared.Formulas, StarterGui.Discovery,
-- ReplicatedStorage.Assets.Boxes, Workspace.Plots (OwnerUserId attribute, DeliveryPoint).

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
local Crates = require(Config:WaitForChild("Crates"))
local Economy = require(Config:WaitForChild("Economy"))

local DiscoveryController = {}
local DEBUG = true

local OPEN_TIMEOUT = 4 -- seconds to wait for BoxOpened; no answer = server refused (it sends a toast, e.g. "inventory full")
local ESTIMATE_STARS = 2 -- "Est. value" = price when restored to 2★ (Good)
local BOX_SPACING = 3.2 -- studs between boxes at the door
local DOT_EMPTY = UiTheme.Disabled

local player = Players.LocalPlayer
local others = nil
local discovery: ScreenGui? = nil
local myPlot: Model? = nil
local boxFolder: Folder? = nil
local boxModels: { [string]: Model } = {} -- [boxId] = model at the door
local results: { [string]: { itemId: string, golden: boolean, isNew: boolean } } = {} -- [uid] = BoxOpened info
local opening = false
local storePressed = Instance.new("BindableEvent")

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

local function showCard(info, index: number, total: number)
	if discovery == nil then
		return
	end
	local card = discovery.Card
	local def = Items[info.itemId]
	local rarity = def and def.rarity or "Common"
	local rarityDef = Rarities[rarity]
	local color = UiTheme.rarityColor(rarity)

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
	card.NewTag.Position = UDim2.new(0.5, if both then -46 else 0, 0, 116)
	card.GoldenTag.Position = UDim2.new(0.5, if both then 46 else 0, 0, 116)

	local estimate = if def then Formulas.sellPrice(info.itemId, ESTIMATE_STARS, info.golden) else 0
	card.Value.Text = `Est. value ${estimate}`
	card.Visible = true
end

local function hideCard()
	if discovery then
		discovery.Card.Visible = false
	end
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
	opening = true
	if others and others.ShopController and others.ShopController.CloseSupply then
		others.ShopController.CloseSupply() -- one modal at a time (docs/01 J4)
	end
	if others and others.InventoryController and others.InventoryController.Close then
		others.InventoryController.Close()
	end

	local total = #box.uids
	for index, uid in box.uids do
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
	Remotes.BoxOpened.OnClientEvent:Connect(function(uid, itemId, isGolden, isNew)
		if type(uid) == "string" and type(itemId) == "string" then
			results[uid] = { itemId = itemId, golden = isGolden == true, isNew = isNew == true }
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
		ClientState.OnChanged("inventory", renderBoxes)
		log(`ready at {myPlot.Name}, {#waitingBoxes()} box(es) waiting`)
	end)
end

return DiscoveryController
