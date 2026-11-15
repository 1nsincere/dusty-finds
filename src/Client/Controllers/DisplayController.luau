-- DisplayController.luau
-- Purpose: shelves and pedestals on the client. (1) Draws the item on every plot's occupied slot for everyone,
-- from the slot part's attributes (ItemId, Golden, Stars) that DisplayService sets on the server.
-- (2) In MY shop, adds a prompt to each unlocked slot: "Place item" (opens the Inventory picker) or "Take back"
-- (RequestRemoveFromSlot). The server checks everything (ownership, distance, state, slot free/unlocked).
-- Owner: Dev 3 (Sean). Depends on: InventoryController (OpenPicker), UiTheme, Shared.Remotes,
-- Shared.Config.Items, Workspace.Plots (DisplaySlots/Slot<N>, ExhibitSlots/Exhibit<N>, attributes SlotIndex,
-- Enabled, ItemId, Golden, Stars; OwnerUserId on the plot), ReplicatedStorage.Assets.Items (real models, later).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Config"):WaitForChild("Items"))

local DisplayController = {}
local DEBUG = true

local PLACEHOLDER_SIZE = Vector3.new(1.2, 1.2, 1.2) -- until Dev 2's item models exist
local TAG_MAX_DISTANCE = 30 -- name tags only show when close, to keep the street readable
local REMOVE_COOLDOWN = 1.5
-- Folder name in the plot -> the `kind` the server expects, and the words players see.
local KINDS = {
	DisplaySlots = { kind = "Display", label = "Shelf" },
	ExhibitSlots = { kind = "Exhibit", label = "Pedestal" },
}

local player = Players.LocalPlayer
local others = nil
local visualsFolder: Folder? = nil
local visuals: { [BasePart]: Instance } = {} -- [slot part] = the item drawn on it
local removeCooldownUntil: { [BasePart]: number } = {}

local function log(...)
	if DEBUG then
		print("[DisplayController]", ...)
	end
end

local function starsText(stars: any): string
	local n = if type(stars) == "number" then math.clamp(math.floor(stars), 0, 3) else 0
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

-- ===== Visuals (every plot, everyone) =====

-- A real model from ReplicatedStorage.Assets.Items.<ItemId> if Dev 2 made one, else a rarity-colored block.
local function makeItemVisual(itemId: string, golden: boolean): (Instance, BasePart)
	local models = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Items")
	local template = models and models:FindFirstChild(itemId)
	if template and template:IsA("Model") then
		local model = template:Clone()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end
		local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		return model, primary :: BasePart
	end
	local def = Items[itemId]
	local block = Instance.new("Part")
	block.Size = PLACEHOLDER_SIZE
	block.Anchored = true
	block.CanCollide = false
	block.CanQuery = false
	block.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	block.Color = if golden then UiTheme.Golden else UiTheme.rarityColor(def and def.rarity)
	return block, block
end

local function clearVisual(slot: BasePart)
	local old = visuals[slot]
	if old then
		old:Destroy()
		visuals[slot] = nil
	end
end

local function renderSlot(slot: BasePart)
	clearVisual(slot)
	local itemId = slot:GetAttribute("ItemId")
	if type(itemId) ~= "string" or visualsFolder == nil then
		return
	end
	local golden = slot:GetAttribute("Golden") == true
	local visual, anchorPart = makeItemVisual(itemId, golden)

	-- Sit on top of the slot part (shelf pad or pedestal top).
	local height = if anchorPart then anchorPart.Size.Y else PLACEHOLDER_SIZE.Y
	local target = slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + height / 2, 0)
	if visual:IsA("Model") then
		visual:PivotTo(target)
	elseif visual:IsA("BasePart") then
		visual.CFrame = target
	end

	-- Name tag: "Vintage Tin Robot ★★☆" (+ 🌟 for golden), seen by owner and visitors.
	local def = Items[itemId]
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(150, 30)
	tag.StudsOffset = Vector3.new(0, height / 2 + 1, 0)
	tag.MaxDistance = TAG_MAX_DISTANCE
	tag.Parent = anchorPart or visual
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = `{if golden then "🌟 " else ""}{def and def.name or itemId} {starsText(slot:GetAttribute("Stars"))}`
	label.Parent = tag

	visual.Name = "Item_" .. slot.Name
	visual.Parent = visualsFolder
	visuals[slot] = visual
end

-- ===== Prompts (my plot only) =====

local function isMine(plot: Instance): boolean
	return plot:GetAttribute("OwnerUserId") == player.UserId
end

local function updatePrompt(slot: BasePart, prompt: ProximityPrompt, plot: Instance, info)
	local index = slot:GetAttribute("SlotIndex")
	local occupied = type(slot:GetAttribute("ItemId")) == "string"
	prompt.ObjectText = `{info.label} {index or "?"}`
	prompt.ActionText = if occupied then "Take back" else "Place item"
	-- Only in my shop, only unlocked slots (Enabled is set by PlotService from my upgrades).
	prompt.Enabled = isMine(plot)
		and slot:GetAttribute("Enabled") == true
		and type(index) == "number"
		and os.clock() >= (removeCooldownUntil[slot] or 0)
end

local function hookSlot(slot: BasePart, plot: Instance, info)
	renderSlot(slot)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SlotPrompt"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = slot
	local function refresh()
		updatePrompt(slot, prompt, plot, info)
	end
	refresh()

	prompt.Triggered:Connect(function()
		local index = slot:GetAttribute("SlotIndex")
		if not isMine(plot) or type(index) ~= "number" then
			return
		end
		if type(slot:GetAttribute("ItemId")) == "string" then
			-- Take back: the server returns it to my inventory (refused if a customer reserved it or I'm full).
			removeCooldownUntil[slot] = os.clock() + REMOVE_COOLDOWN
			refresh()
			Remotes.RequestRemoveFromSlot:FireServer(info.kind, index)
			log("asked to take back", info.kind, index)
			task.delay(REMOVE_COOLDOWN, refresh)
		else
			local inventory = others and others.InventoryController
			if inventory and inventory.OpenPicker then
				inventory.OpenPicker(info.kind, index, `{info.label} {index}`)
			end
		end
	end)

	for _, attribute in { "ItemId", "Golden", "Stars" } do
		slot:GetAttributeChangedSignal(attribute):Connect(function()
			renderSlot(slot)
			refresh()
		end)
	end
	slot:GetAttributeChangedSignal("Enabled"):Connect(refresh)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
end

local function hookPlot(plot: Instance)
	for folderName, info in KINDS do
		local folder = plot:FindFirstChild(folderName)
		if folder then
			for _, slot in folder:GetChildren() do
				if slot:IsA("BasePart") then
					hookSlot(slot, plot, info)
				end
			end
		end
	end
end

-- ===== Lifecycle =====

function DisplayController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function DisplayController.Start()
	log("Start")
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 10)
		if plots == nil then
			warn("[DisplayController] Workspace.Plots not found")
			return
		end
		visualsFolder = Instance.new("Folder")
		visualsFolder.Name = "ShelfItems" -- client-side drawings; the truth is the server's slot attributes
		visualsFolder.Parent = workspace
		for _, plot in plots:GetChildren() do
			hookPlot(plot)
		end
		log(`ready: {#plots:GetChildren()} plots hooked`)
	end)
end

return DisplayController
