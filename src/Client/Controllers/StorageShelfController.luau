-- StorageShelfController.luau (StarterPlayerScripts.Client.Controllers.StorageShelfController)
-- Purpose: draws the items on every shop's storage room shelves (StorageShelves/Slot1..16), for owners AND visitors.
-- The server (StorageShelfService) decides what goes where through slot attributes (ItemId, Golden) and the folder's
-- More attribute; this only draws. Items look as they really are: still dirty and rusty, missing parts still missing
-- (only the restoration helpers, ghost sockets and spare parts on the tray, are removed). Shown as a "+N more" sign
-- when there are more unrestored items than slots. Purely visual: no prompts, no remotes.
-- Owner: Dev 3 (Sean). Depends on: Workspace.Plots.PlotN.{StorageShelves, StorageRoom.MoreSign}, ReplicatedStorage.Assets.Items
-- (Item Model Contract: Base + DirtSpots/RustSpots/Sockets/LooseParts), Shared.Config.Items, UiTheme (rarity colours).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Items"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local StorageShelfController = {}
local DEBUG = true

local MAX_HEIGHT = 2.1 -- studs between a shelf board and the one above it (upper tier is the tightest)
local MAX_FOOTPRINT = 2.0 -- slots are 2.35 apart: keep items from touching their neighbours
local PLACEHOLDER_SIZE = Vector3.new(1.4, 1.2, 1.4)

local visuals: { [BasePart]: Instance } = {}
local folder: Folder? = nil

local function log(...)
	if DEBUG then
		print("[StorageShelfController]", ...)
	end
end

-- The real item model if there is one (still dirty: helpers removed), else a small rarity-coloured crate.
local function makeVisual(itemId: string, golden: boolean): Instance
	local models = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Items")
	local template = models and models:FindFirstChild(itemId)
	if template and template:IsA("Model") then
		local model = template:Clone()
		for _, helper in { "Sockets", "LooseParts" } do -- ghost sockets and the spare parts tray: restoration-only
			local f = model:FindFirstChild(helper)
			if f then
				f:Destroy()
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		return model
	end
	local def = Items[itemId]
	local block = Instance.new("Part")
	block.Size = PLACEHOLDER_SIZE
	block.Anchored = true
	block.CanCollide = false
	block.CanQuery = false
	block.CanTouch = false
	block.Material = Enum.Material.WoodPlanks
	block.Color = if golden then UiTheme.Golden else UiTheme.rarityColor(def and def.rarity)
	return block
end

local function clear(slot: BasePart)
	local old = visuals[slot]
	if old then
		old:Destroy()
		visuals[slot] = nil
	end
end

local function render(slot: BasePart)
	clear(slot)
	local itemId = slot:GetAttribute("ItemId")
	if type(itemId) ~= "string" or folder == nil then
		return
	end
	local visual = makeVisual(itemId, slot:GetAttribute("Golden") == true)
	-- stand on the slot, facing the room (the slot part looks into the room)
	local top = slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0)
	if visual:IsA("Model") then
		visual:PivotTo(top)
		local _, size = visual:GetBoundingBox()
		local fit = math.min(1, MAX_HEIGHT / math.max(size.Y, 0.01), MAX_FOOTPRINT / math.max(size.X, size.Z, 0.01))
		if fit < 0.999 then
			visual:ScaleTo(visual:GetScale() * fit)
		end
		local box, boxSize = visual:GetBoundingBox()
		local bottom = top:PointToObjectSpace(box.Position).Y - boxSize.Y / 2
		visual:PivotTo(top * CFrame.new(0, -bottom, 0))
	else
		local block = visual :: BasePart
		block.CFrame = top * CFrame.new(0, block.Size.Y / 2, 0)
	end
	visual.Name = "Stored_" .. slot.Name
	visual.Parent = folder
	visuals[slot] = visual
end

local function updateMoreSign(plot: Instance, shelves: Instance)
	local room = plot:FindFirstChild("StorageRoom")
	local sign = room and room:FindFirstChild("MoreSign")
	local label = sign and sign:FindFirstChild("More", true)
	if not (sign and sign:IsA("BasePart") and label and label:IsA("TextLabel")) then
		return
	end
	local more = shelves:GetAttribute("More")
	local show = type(more) == "number" and more > 0
	sign.Transparency = if show then 0 else 1
	label.Text = if show then `+{more} more` else ""
end

local function hookSlot(slot: Instance)
	if not slot:IsA("BasePart") or slot:GetAttribute("SlotIndex") == nil then
		return
	end
	slot:GetAttributeChangedSignal("ItemId"):Connect(function()
		render(slot)
	end)
	slot:GetAttributeChangedSignal("Golden"):Connect(function()
		render(slot)
	end)
	slot.AncestryChanged:Connect(function()
		if slot.Parent == nil then
			clear(slot)
		end
	end)
	render(slot)
end

local function hookPlot(plot: Instance)
	task.spawn(function()
		local shelves = plot:WaitForChild("StorageShelves", 30)
		if shelves == nil then
			return -- an older plot without a storage room: nothing to draw
		end
		shelves.ChildAdded:Connect(hookSlot) -- slots stream in one by one
		for _, slot in shelves:GetChildren() do
			hookSlot(slot)
		end
		shelves:GetAttributeChangedSignal("More"):Connect(function()
			updateMoreSign(plot, shelves)
		end)
		updateMoreSign(plot, shelves)
	end)
end

function StorageShelfController.Init(_others) end

function StorageShelfController.Start()
	folder = Instance.new("Folder")
	folder.Name = "StorageShelfItems"
	folder.Parent = workspace
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 30)
		if plots == nil then
			warn("[StorageShelfController] Workspace.Plots not found")
			return
		end
		plots.ChildAdded:Connect(hookPlot)
		for _, plot in plots:GetChildren() do
			hookPlot(plot)
		end
		log("ready")
	end)
end

return StorageShelfController
