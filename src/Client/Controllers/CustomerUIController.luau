-- CustomerUIController.luau (StarterPlayerScripts.Client.Controllers.CustomerUIController)
-- Purpose: a 💭 bubble over every customer NPC (its wish, then the item it chose) and hides the owner-only
-- Checkout prompt from visitors. Purely visual: the server (CustomerService/CustomerNpcService) decides everything.
-- Owner: Dev 3 (Sean). Depends on: Workspace.Customers (models with attributes CustomerId, Wish, ItemId, and from the
-- till via CustomerNpcService.SetCashierState: CashierPaid, Mood),
-- Workspace.Plots (OwnerUserId attribute, Counter.CheckoutPrompt), Shared.Config.Items, UiTheme, ClientState (settings).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Items"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local CustomerUIController = {}
local DEBUG = true

local LOCAL_PLAYER = Players.LocalPlayer
local BUBBLE_WIDTH_STUDS = 4 -- BillboardGui scale sizes are in studs, so the bubble shrinks with distance like a real object
local BUBBLE_HEIGHT_STUDS = 1.4
local BUBBLE_ABOVE_HEAD = 2.6 -- clears the hats on the greybox NPCs
local BUBBLE_MAX_DISTANCE = 70

-- Presentation only (the category list itself lives in Config.Economy.Categories).
local CATEGORY_ICONS = {
	Toys = "🧸",
	Kitchen = "🍵",
	Decor = "🖼️",
	Music = "🎵",
	Electronics = "📻",
}

local bubbles: { [Model]: { gui: BillboardGui, connections: { RBXScriptConnection } } } = {}

local function log(...)
	if DEBUG then
		print("[CustomerUIController]", ...)
	end
end

local function reduceEffects(): boolean
	local settings = ClientState.Get("settings")
	return type(settings) == "table" and settings.reduceEffects == true
end

-- ===== Bubbles =====

-- Till moods (Mood attribute). While the till is open (CashierPaid set) the bubble shows what the customer handed over.
local MOOD_TEXT = {
	Delighted = "🤩 Wow, so fast!",
	Happy = "😊 Thank you!",
	Upset = "😠 That's not right!",
	Angry = "😡 I'm leaving!",
}

local function bubbleText(model: Model): string
	local say = model:GetAttribute("Say") -- what the customer says right now (server sets it; empty = nothing)
	if type(say) == "string" and say ~= "" then
		return "💬 " .. say
	end
	local paid = model:GetAttribute("CashierPaid")
	local mood = model:GetAttribute("Mood")
	if paid ~= nil and mood == nil then
		return `💵 Here's ${paid}`
	end
	if type(mood) == "string" and MOOD_TEXT[mood] then
		if mood == "Upset" and paid == nil then
			return "😒 Hmpf." -- paid after a mistake: no longer waiting, just not happy
		end
		return MOOD_TEXT[mood]
	end
	local itemId = model:GetAttribute("ItemId")
	local item = itemId and Items[itemId]
	if item then
		return `😊 {item.name}`
	end
	local wish = model:GetAttribute("Wish")
	if type(wish) == "string" then
		return `💭 {CATEGORY_ICONS[wish] or ""} {wish}`
	end
	return "💭 ..."
end

local function buildBubble(head: BasePart): (BillboardGui, TextLabel, UIScale)
	local gui = Instance.new("BillboardGui")
	gui.Name = "WishBubble"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(BUBBLE_WIDTH_STUDS, BUBBLE_HEIGHT_STUDS)
	gui.StudsOffsetWorldSpace = Vector3.new(0, BUBBLE_ABOVE_HEAD, 0)
	gui.MaxDistance = BUBBLE_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false -- hidden behind walls, like a real speech bubble

	local frame = Instance.new("Frame")
	frame.Name = "Bubble"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = UiTheme.Teal
	stroke.Thickness = 2
	stroke.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 40, 40)
	label.Parent = frame

	return gui, label, scale
end

local function pop(scale: UIScale)
	if reduceEffects() then
		scale.Scale = 1
		return
	end
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function removeBubble(model: Model)
	local entry = bubbles[model]
	if not entry then
		return
	end
	bubbles[model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.gui:Destroy()
end

local function addBubble(model: Instance)
	if not model:IsA("Model") or bubbles[model] then
		return
	end
	-- The model arrives over the network part by part, so wait briefly for its Head.
	local head = model:WaitForChild("Head", 5)
	if not (head and head:IsA("BasePart")) or not model.Parent then
		return
	end

	local gui, label, scale = buildBubble(head)
	label.Text = bubbleText(model)
	-- In PlayerGui (not inside the NPC) so it never replicates and dies cleanly when the model is removed.
	gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
	pop(scale)

	local connections = {}
	local function refresh()
		local text = bubbleText(model)
		if label.Text ~= text then
			label.Text = text
			pop(scale)
		end
	end
	table.insert(connections, model:GetAttributeChangedSignal("Wish"):Connect(refresh))
	table.insert(connections, model:GetAttributeChangedSignal("ItemId"):Connect(refresh))
	table.insert(connections, model:GetAttributeChangedSignal("Mood"):Connect(refresh))
	table.insert(connections, model:GetAttributeChangedSignal("Say"):Connect(refresh))
	table.insert(connections, model:GetAttributeChangedSignal("CashierPaid"):Connect(refresh))
	bubbles[model] = { gui = gui, connections = connections }
	log("bubble for", model.Name, label.Text)
end

local function watchCustomers(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		task.spawn(addBubble, child)
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			removeBubble(child)
		end
	end)
	for _, child in folder:GetChildren() do
		task.spawn(addBubble, child)
	end
end

-- ===== Checkout prompt: owner only =====
-- The server already ignores visitors' taps; this just stops visitors seeing a prompt they can't use.
-- A client-side Enabled = false stays until the server changes Enabled again, which re-runs this check.

local function hidePromptFromVisitors(plot: Instance)
	local counter = plot:WaitForChild("Counter", 10)
	local prompt = counter and counter:WaitForChild("CheckoutPrompt", 10)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		return
	end
	local function check()
		if plot:GetAttribute("OwnerUserId") ~= LOCAL_PLAYER.UserId and prompt.Enabled then
			prompt.Enabled = false
		end
	end
	prompt:GetPropertyChangedSignal("Enabled"):Connect(check)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(check)
	check()
end

function CustomerUIController.Init(_others) end

function CustomerUIController.Start()
	task.spawn(function()
		local folder = workspace:WaitForChild("Customers", 30)
		if folder then
			watchCustomers(folder)
		else
			warn("[CustomerUIController] Workspace.Customers not found")
		end
	end)
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 30)
		if not plots then
			warn("[CustomerUIController] Workspace.Plots not found")
			return
		end
		for _, plot in plots:GetChildren() do
			task.spawn(hidePromptFromVisitors, plot)
		end
		plots.ChildAdded:Connect(function(plot)
			task.spawn(hidePromptFromVisitors, plot)
		end)
	end)
end

return CustomerUIController
