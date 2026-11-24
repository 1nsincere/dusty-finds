-- TownTalk.local.luau (StarterPlayerScripts.Client.TownTalk)
-- Purpose: local greetings for ambient walkers and a stationary canal guide.
-- Owner: Dwayne (Dev 2), with the world and UI owners' approval.
-- Reads the existing local walkers, Vendor look and Directory board.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TALK = {
	range = 6,
	updateSeconds = 0.15,
	bubbleSeconds = 3,
	layoutGraceSeconds = 0.3,
	promptClearance = 2,
	guideOffset = Vector3.new(7, 0, -3),
	vendorSpawnRange = 45,
	walkerLines = {
		"Kumusta! The canal is lovely today.",
		"I like this walk when the shop lights come on.",
		"Someone on this street can fix almost anything.",
	},
	guideLines = {
		"Welcome! The Directory can help you find your way.",
		"Looking for crates? Try the Warehouse.",
		"The museum is a good stop if you like seeing old things made new.",
	},
}

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "TownTalkPrompt"
prompt.ActionText = "Talk"
prompt.KeyboardKeyCode = Enum.KeyCode.F
prompt.MaxActivationDistance = TALK.range
prompt.RequiresLineOfSight = true
prompt.ClickablePrompt = true
prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
prompt.Enabled = false

-- Keep the prompt on a local anchor so no walker or existing world model gets new children.
local promptAnchor = Instance.new("Part")
promptAnchor.Name = "TownTalkAnchor"
promptAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
promptAnchor.Transparency = 1
promptAnchor.Anchored = true
promptAnchor.CanCollide = false
promptAnchor.CanTouch = false
promptAnchor.CanQuery = false
promptAnchor.CastShadow = false
promptAnchor.Parent = workspace
prompt.Parent = promptAnchor

local buyPrompt = Instance.new("ProximityPrompt")
buyPrompt.Name = "FishballBuyPrompt"
buyPrompt.ActionText = "Buy fishball"
buyPrompt.KeyboardKeyCode = Enum.KeyCode.E
buyPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
buyPrompt.MaxActivationDistance = TALK.range
buyPrompt.RequiresLineOfSight = true
buyPrompt.ClickablePrompt = true
buyPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
buyPrompt.UIOffset = Vector2.new(0, 64)
buyPrompt.Enabled = false
buyPrompt.Parent = promptAnchor

-- A static bubble is the same in both effects modes. Its lifetime is local.
local bubble = Instance.new("BillboardGui")
bubble.Name = "TownTalkBubble"
bubble.Size = UDim2.fromOffset(188, 48)
bubble.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
bubble.MaxDistance = 18
bubble.LightInfluence = 0
bubble.Enabled = false
bubble.ResetOnSpawn = false
bubble.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "Line"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundColor3 = Color3.fromRGB(34, 37, 43)
label.TextColor3 = Color3.fromRGB(244, 240, 232)
label.Font = Enum.Font.GothamBold
label.TextSize = 13
label.TextWrapped = true
label.Parent = bubble

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = label

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = label

-- The skewer is a static part of the shared bubble.
local skewer = Instance.new("Frame")
skewer.Name = "FishballSkewer"
skewer.BackgroundTransparency = 1
skewer.Size = UDim2.fromOffset(14, 32)
skewer.Position = UDim2.fromOffset(0, 8)
skewer.Visible = false
skewer.Parent = label

local stick = Instance.new("Frame")
stick.BorderSizePixel = 0
stick.BackgroundColor3 = Color3.fromRGB(229, 186, 132)
stick.Size = UDim2.fromOffset(2, 30)
stick.Position = UDim2.fromOffset(6, 2)
stick.Parent = skewer

for i = 0, 2 do
	local snack = Instance.new("Frame")
	snack.BorderSizePixel = 0
	snack.BackgroundColor3 = Color3.fromRGB(246, 202, 145)
	snack.Size = UDim2.fromOffset(8, 8)
	snack.Position = UDim2.fromOffset(3, i * 8)
	snack.Parent = skewer
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = snack
end

-- Array order breaks distance ties consistently. Lines and icons share the same index.
local CARTS = {
	{ name = "Fishball", lines = {
		{ "Kumusta! Which dip would you pick, sweet or spicy?", "FishballSkewer" },
		{ "Fresh fishballs! The sweet dip is my favorite.", "FishballSkewer" },
		{ "The canal breeze makes a snack break even better.", "FishballSkewer" },
	} },
	{ name = "Pandesal", title = "Pandesal and Turon Vendor", lines = {
		{ "Warm pandesal for the walk?", "Bread" },
		{ "The turon is extra crunchy today.", "Turon" },
	} },
	{ name = "Taho", rearSideOffset = 2.25, lines = {
		{ "Taho! I saved a little extra arnibal for this cup.", "Cup" },
		{ "A warm cup is lovely on a breezy day.", "Cup" },
	} },
	{ name = "HaloHalo", title = "Halo-Halo Vendor", lines = {
		{ "Mix it to the bottom. The good stuff hides there!", "Spoon" },
		{ "I save the purple scoop for last.", "Spoon" },
	} },
	{ name = "BananaCue", title = "Banana Cue Vendor", lines = {
		{ "The sugar is still warm. Can you hear it crackle?", "BananaSkewer" },
		{ "The best bite is the little crispy edge.", "BananaSkewer" },
	} },
	{ name = "Barbecue", title = "Ihaw-Ihaw Vendor", lines = {
		{ "The breeze carries that grill smell down the canal.", "Grill" },
		{ "I turn the skewers when the edges turn golden.", "Grill" },
	} },
}

local icons: { [string]: Frame } = { FishballSkewer = skewer }
local gold = Color3.fromRGB(246, 202, 145)
local wood = Color3.fromRGB(229, 186, 132)
local cream = Color3.fromRGB(245, 234, 211)
local ember = Color3.fromRGB(234, 126, 92)

local function icon(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = skewer.Size
	frame.Position = skewer.Position
	frame.Visible = false
	frame.Parent = label
	icons[name] = frame
	return frame
end

local function shape(parent: Frame, x: number, y: number, w: number, h: number, color: Color3, radius: number)
	local part = Instance.new("Frame")
	part.BorderSizePixel = 0
	part.BackgroundColor3 = color
	part.Size = UDim2.fromOffset(w, h)
	part.Position = UDim2.fromOffset(x, y)
	part.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = part
end

local bread = icon("Bread")
shape(bread, 0, 10, 14, 12, gold, 5)
shape(bread, 5, 12, 4, 2, cream, 1)
local turon = icon("Turon")
shape(turon, 3, 5, 9, 22, wood, 3)
shape(turon, 5, 7, 2, 16, gold, 1)
local cup = icon("Cup")
shape(cup, 2, 10, 10, 16, wood, 3)
shape(cup, 1, 8, 12, 4, cream, 2)
local spoon = icon("Spoon")
shape(spoon, 6, 12, 2, 16, cream, 1)
shape(spoon, 3, 3, 8, 12, cream, 4)
local banana = skewer:Clone()
banana.Name = "BananaSkewer"
for _, part in banana:GetChildren() do
	if part:IsA("Frame") and part.Size.X.Offset == 8 then part.BackgroundColor3 = ember end
end
banana.Parent = label
icons.BananaSkewer = banana
local grill = icon("Grill")
shape(grill, 0, 11, 14, 8, ember, 2)
shape(grill, 1, 9, 12, 3, cream, 1)
shape(grill, 2, 18, 2, 7, wood, 1)
shape(grill, 10, 18, 2, 7, wood, 1)

type Vendor = { model: Model, cart: Model, index: number, talkAt: Vector3 }
local vendors: { [number]: Vendor } = {}
local vendorActors: { [Instance]: Vendor } = {}
local blockedCarts: { [number]: Model } = {}
local vendorLines: { [number]: number } = {}
local shownIcon: Frame? = nil
local guide: Model? = nil
local guideBoard: BasePart? = nil
local boardConnection: RBXScriptConnection? = nil
local guideLine = 0
local currentHead: BasePart? = nil
local actorConnection: RBXScriptConnection? = nil
local bubbleEnds = 0
local layoutBlockedSince: number? = nil

local function clearBubble()
	bubble.Enabled = false
	bubble.Adornee = nil
	bubbleEnds = 0
end

local function talkAnchorPosition(head: BasePart): Vector3
	local actor = head.Parent
	local vendor = actor and vendorActors[actor]
	return if vendor then vendor.talkAt else head.Position
end

local function setTarget(head: BasePart?)
	if head then promptAnchor.Position = talkAnchorPosition(head) end
	if currentHead == head then return end
	if actorConnection then
		actorConnection:Disconnect()
		actorConnection = nil
	end
	clearBubble()
	currentHead = head
	buyPrompt.Enabled = false
	layoutBlockedSince = nil
	prompt.Enabled = false
	if head then
		local actor = head.Parent
		local vendor = actor and vendorActors[actor]
		local config = vendor and CARTS[vendor.index]
		prompt.ObjectText = if actor == guide then "Canal Guide"
			elseif config then config.title or (config.name .. " Vendor") else "Townsperson"
		prompt.Enabled = true
		actorConnection = head.AncestryChanged:Connect(function()
			if not head:IsDescendantOf(workspace) or head.Parent ~= actor then
				setTarget(nil)
			end
		end)
	end
end

local function screenEnabled(name: string): boolean
	local screen = playerGui:FindFirstChild(name)
	return screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled
end

local function sceneBusy(): boolean
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable
		or screenEnabled("Cashier") or screenEnabled("RestorationTest") or screenEnabled("RestorationWork") then
		return true
	end
	local restoration = playerGui:FindFirstChild("Restoration")
	if restoration and restoration:IsA("ScreenGui") and restoration.Enabled then
		for _, name in { "Hint", "StepChips", "Progress", "ExitButton", "FinishCard" } do
			local control = restoration:FindFirstChild(name)
			if control and control:IsA("GuiObject") and control.Visible then return true end
		end
	end
	return false
end

local function suppressWhenBusy()
	if sceneBusy() then setTarget(nil) end
end

local function watchScreen(screen: Instance)
	if not screen:IsA("ScreenGui") or (screen.Name ~= "Restoration" and screen.Name ~= "RestorationTest"
		and screen.Name ~= "RestorationWork" and screen.Name ~= "Cashier") then return end
	screen:GetPropertyChangedSignal("Enabled"):Connect(suppressWhenBusy)
	if screen.Name == "Restoration" then
		for _, control in screen:GetChildren() do
			if control:IsA("GuiObject") then
				control:GetPropertyChangedSignal("Visible"):Connect(suppressWhenBusy)
			end
		end
	end
	suppressWhenBusy()
end

for _, screen in playerGui:GetChildren() do watchScreen(screen) end
playerGui.ChildAdded:Connect(watchScreen)

local cameraConnection: RBXScriptConnection? = nil
local function watchCamera()
	if cameraConnection then cameraConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	cameraConnection = if camera then camera:GetPropertyChangedSignal("CameraType"):Connect(suppressWhenBusy) else nil
	suppressWhenBusy()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

local function nearPrompt(promptObject: Instance?, position: Vector3): boolean
	if not promptObject or not promptObject:IsA("ProximityPrompt") or not promptObject.Enabled then return false end
	local holder = promptObject.Parent
	if not holder then return false end
	local worldPosition = if holder:IsA("Attachment") then holder.WorldPosition
		elseif holder:IsA("BasePart") then holder.Position else nil
	return worldPosition ~= nil and (worldPosition - position).Magnitude <= promptObject.MaxActivationDistance + TALK.promptClearance
end

local function nearGameplayPrompt(position: Vector3): boolean
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return false end
	for _, plot in plots:GetChildren() do
		local counter = plot:FindFirstChild("Counter")
		if counter and nearPrompt(counter:FindFirstChild("CheckoutPrompt"), position) then return true end
		local benches = plot:FindFirstChild("Benches")
		if benches then
			for _, bench in benches:GetChildren() do
				if nearPrompt(bench:FindFirstChild("Prompt"), position) then return true end
			end
		end
	end
	return false
end

local function directoryBoard(): BasePart?
	local environment = workspace:FindFirstChild("Environment")
	local districts = environment and environment:FindFirstChild("Districts")
	local directory = districts and districts:FindFirstChild("Directory")
	local board = directory and directory:FindFirstChild("Board")
	return if board and board:IsA("BasePart") then board else nil
end

local function cloneVendorLook(template: Model, name: string): Model
	local actor = template:Clone()
	actor.Name = name
	for _, descendant in actor:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			-- R15 can set torso collision when entering Workspace, even for a stationary clone.
			descendant:GetPropertyChangedSignal("CanCollide"):Connect(function()
				if descendant.CanCollide then descendant.CanCollide = false end
			end)
		elseif descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			-- As with the ambient walkers, the state machine must not re-enable collision.
			descendant.EvaluateStateMachine = false
		end
	end
	return actor
end

local function resetVendorPhysics(actor: Model)
	for _, descendant in actor:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
end

local function parentVendor(actor: Model)
	actor.Parent = workspace
	resetVendorPhysics(actor)
	-- The Humanoid can reapply torso collision after the clone enters Workspace.
	task.delay(0.1, function()
		if actor.Parent == workspace then resetVendorPhysics(actor) end
	end)
end

local function updateGuide()
	local board = directoryBoard()
	if board == guideBoard and guide and guide.Parent then return end
	if not board then
		guideBoard = nil
		if guide then guide.Parent = nil end
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local looks = assets and assets:FindFirstChild("Townsfolk")
	local vendor = looks and looks:FindFirstChild("Vendor")
	if not vendor or not vendor:IsA("Model") then return end

	local spot = board.CFrame:PointToWorldSpace(TALK.guideOffset)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { board.Parent }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(spot + Vector3.new(0, 7, 0), Vector3.new(0, -20, 0), params)
	if not hit then
		if guide then guide.Parent = nil end
		return
	end
	if not guide then
		guide = cloneVendorLook(vendor, "LocalCanalGuide")
	end
	local box, size = guide:GetBoundingBox()
	local pivotToFloor = guide:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	local at = hit.Position + Vector3.new(0, pivotToFloor, 0)
	local facing = Vector3.new(board.CFrame.LookVector.X, 0, board.CFrame.LookVector.Z)
	if facing.Magnitude < 0.01 then facing = Vector3.new(0, 0, -1) end
	guide:PivotTo(CFrame.lookAt(at, at + facing))
	if boardConnection then boardConnection:Disconnect() end
	guideBoard = board
	boardConnection = board.AncestryChanged:Connect(function()
		if board ~= directoryBoard() then
			if boardConnection then
				boardConnection:Disconnect()
				boardConnection = nil
			end
			if guide then guide.Parent = nil end
			guideBoard = nil
		end
	end)
	parentVendor(guide)
end

local function characterPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then root.Position else nil
end

local function clearVendor(index: number)
	local vendor = vendors[index]
	if not vendor then return end
	if currentHead and currentHead:IsDescendantOf(vendor.model) then setTarget(nil) end
	vendorActors[vendor.model] = nil
	vendors[index] = nil
	vendor.model:Destroy()
end

local function updateCartVendor(index: number, cart: Instance?, position: Vector3?)
	if not position or not cart or not cart:IsA("Model")
		or not cart:FindFirstChildWhichIsA("BasePart", true)
		or (cart:GetPivot().Position - position).Magnitude > TALK.vendorSpawnRange then
		clearVendor(index)
		return
	end
	local vendor = vendors[index]
	if blockedCarts[index] == cart or (vendor and vendor.cart == cart) then return end
	clearVendor(index)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local looks = assets and assets:FindFirstChild("Townsfolk")
	local template = looks and looks:FindFirstChild("Vendor")
	if not template or not template:IsA("Model") then return end

	local sign = cart:FindFirstChild("FoodSign")
	local surface = sign and sign:FindFirstChildWhichIsA("SurfaceGui", true)
	if not sign or not sign:IsA("BasePart") or not surface then return end
	local normal = sign.CFrame:VectorToWorldSpace(Vector3.FromNormalId(surface.Face))
	local front = Vector3.new(normal.X, 0, normal.Z)
	if front.Magnitude < 0.99 then return end
	front = front.Unit

	local pivot = cart:GetPivot()
	local box, size = cart:GetBoundingBox()
	local direction = front:Dot(box.LookVector)
	if math.abs(direction) < 0.99 then return end
	local actor = cloneVendorLook(template, "Local" .. CARTS[index].name .. "Vendor")
	local actorBox, actorSize = actor:GetBoundingBox()
	local floorOffset = actor:GetPivot().Position.Y - (actorBox.Position.Y - actorSize.Y / 2)
	local rearClearance = actorSize.Z / 2 + 0.2
	local spot = Vector3.new(box.Position.X, pivot.Position.Y, box.Position.Z)
		- front * (size.Z / 2 + rearClearance)
		+ pivot.RightVector * (CARTS[index].rearSideOffset or 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cart.Parent, player.Character }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(spot + Vector3.yAxis * 3, -Vector3.yAxis * 8, params)
	if not hit or hit.Normal.Y < 0.95 then
		actor:Destroy()
		return
	end

	local at = hit.Position + Vector3.yAxis * floorOffset
	actor:PivotTo(CFrame.lookAt(at, at + front))
	local bounds, dimensions = actor:GetBoundingBox()
	local center = box:PointToObjectSpace(bounds.Position)
	local half = dimensions / 2
	-- The imported cart meshes are visual only. Physics queries miss their body and counter.
	for _, part in cart:GetDescendants() do
		if part:IsA("BasePart") then
			local relative = box:ToObjectSpace(part.CFrame)
			local right, up, look = relative.RightVector, relative.UpVector, relative.LookVector
			local extent = part.Size / 2
			local function axisExtent(x: number, y: number, z: number): number
				return math.abs(x) * extent.X + math.abs(y) * extent.Y + math.abs(z) * extent.Z
			end
			local delta = relative.Position - center
			if math.abs(delta.X) < half.X + axisExtent(right.X, up.X, look.X)
				and math.abs(delta.Y) < half.Y + axisExtent(right.Y, up.Y, look.Y)
				and math.abs(delta.Z) < half.Z + axisExtent(right.Z, up.Z, look.Z) then
				blockedCarts[index] = cart
				actor:Destroy()
				return
			end
		end
	end
		-- Only Talk moves to the customer side. The speech bubble still follows the vendor.
	local talkAt = Vector3.new(box.Position.X, hit.Position.Y + 4, box.Position.Z)
		+ front * (size.Z / 2 + 0.45)
	local slot = { model = actor, cart = cart, index = index, talkAt = talkAt }
	vendors[index] = slot
	vendorActors[actor] = slot
	parentVendor(actor)
end

local function updateCartVendors(position: Vector3?)
	local assembly = workspace:FindFirstChild("CanalTownAssembly")
	local carts = assembly and assembly:FindFirstChild("FoodCarts")
	for index, config in CARTS do
		updateCartVendor(index, carts and carts:FindFirstChild(config.name .. "Cart"), position)
	end
end
local function talkPosition(): Vector3?
	local position = characterPosition()
	if position and not sceneBusy() and not nearGameplayPrompt(position) then return position end
	return nil
end

local function walkerIndex(actor: Instance): number?
	return tonumber(actor.Name:match("^Townsperson(%d+)$"))
end

local function bubbleOffset(head: BasePart): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local _, headVisible = camera:WorldToViewportPoint(head.Position)
	if not headVisible then return nil end
	local point = camera:WorldToViewportPoint(head.Position + bubble.StudsOffsetWorldSpace)
	if point.Z <= 0 then return nil end

	-- Convert the projected point to the same core-safe coordinates as the HUD.
	local origin = GuiService:GetInsetArea(Enum.ScreenInsets.None).Min
	local center = Vector2.new(point.X, point.Y) + origin
	local size = Vector2.new(bubble.Size.X.Offset, bubble.Size.Y.Offset)
	local half = size / 2 + Vector2.new(4, 4)
	local safe = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local low, high = safe.Min + half, safe.Max - half
	if low.X > high.X or low.Y > high.Y then return nil end
	local x = math.clamp(center.X, low.X, high.X)
	local y = math.clamp(center.Y, low.Y, high.Y)

	local blocked = {}
	local hud = playerGui:FindFirstChild("HUD")
	if hud and hud:IsA("ScreenGui") and hud.Enabled then
		for _, control in hud:GetDescendants() do
			if control:IsA("GuiObject") and (control:IsA("GuiButton")
				or control.Name == "MoneyPill" or control.Name == "Stars" or control.Name == "XPBar") then
				local ancestor = control
				while ancestor:IsA("GuiObject") and ancestor.Visible do
					ancestor = ancestor.Parent
				end
				if ancestor == hud then
					local min = control.AbsolutePosition
					table.insert(blocked, Rect.new(min - half, min + control.AbsoluteSize + half))
				end
			end
		end
	end

	local function clearAt(px: number, py: number): boolean
		for _, rect in blocked do
			if px > rect.Min.X and px < rect.Max.X and py > rect.Min.Y and py < rect.Max.Y then
				return false
			end
		end
		return true
	end

	local function offsetAt(px: number, py: number): Vector2
		return Vector2.new((px - center.X) / size.X, (center.Y - py) / size.Y)
	end

	if clearAt(x, y) then return offsetAt(x, y) end

	-- The closest free point lies on an obstacle edge or on the original clamped axis.
	local xs, ys = { x }, { y }
	for _, rect in blocked do
		table.insert(xs, math.clamp(rect.Min.X, low.X, high.X))
		table.insert(xs, math.clamp(rect.Max.X, low.X, high.X))
		table.insert(ys, math.clamp(rect.Min.Y, low.Y, high.Y))
		table.insert(ys, math.clamp(rect.Max.Y, low.Y, high.Y))
	end
	local best, shortest = nil, math.huge
	for _, px in xs do
		for _, py in ys do
			local distance = (Vector2.new(px, py) - center).Magnitude
			if distance < shortest and clearAt(px, py) then
				best, shortest = offsetAt(px, py), distance
			end
		end
	end
	return best
end

local function layoutAllows(head: BasePart): boolean
	if bubbleOffset(head) then
		if head == currentHead then layoutBlockedSince = nil end
		return true
	end
	if head ~= currentHead or not prompt.Enabled then return false end
	local now = os.clock()
	layoutBlockedSince = layoutBlockedSince or now
	return now - layoutBlockedSince < TALK.layoutGraceSeconds
end

local function nearestHead(position: Vector3): BasePart?
	local nearest: BasePart? = nil
	local shortest = TALK.range
	local nearestIndex = math.huge
	local function consider(actor: Instance, index: number)
		local head = actor:FindFirstChild("Head")
		local root = actor:FindFirstChild("HumanoidRootPart")
		if not head or not head:IsA("BasePart") or not root or not root:IsA("BasePart") then return end
		local distance = (talkAnchorPosition(head) - position).Magnitude
		if (distance < shortest or (distance == shortest and index < nearestIndex)) and layoutAllows(head) then
			nearest = head
			shortest = distance
			nearestIndex = index
		end
	end
	local walkers = workspace:FindFirstChild("Townsfolk")
	if walkers then
		for _, actor in walkers:GetChildren() do
			local index = walkerIndex(actor)
			if actor:IsA("Model") and index then consider(actor, index) end
		end
	end
	if guide and guide.Parent and guideBoard == directoryBoard() then consider(guide, 0) end
	for index, vendor in vendors do
		if vendor.cart:IsDescendantOf(workspace) then consider(vendor.model, index - #CARTS - 1) end
	end
	return nearest
end

prompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer ~= player or not currentHead or bubbleEnds > 0 then return end
	local position = talkPosition()
	local actor = currentHead.Parent
	if not position or not actor or not currentHead:IsDescendantOf(workspace)
		or (talkAnchorPosition(currentHead) - position).Magnitude > TALK.range or not layoutAllows(currentHead) then return end
	local line: string
	local iconName: string? = nil
	local vendor = vendorActors[actor]
	if actor == guide then
		if not guideBoard or guideBoard ~= directoryBoard() then return end
		guideLine = guideLine % #TALK.guideLines + 1
		line = TALK.guideLines[guideLine]
	elseif vendor then
		if not vendor.cart:IsDescendantOf(workspace) then return end
		local lines = CARTS[vendor.index].lines
		local pick = (vendorLines[vendor.index] or 0) % #lines + 1
		vendorLines[vendor.index] = pick
		line, iconName = lines[pick][1], lines[pick][2]
	else
		local index = walkerIndex(actor)
		if not index or actor.Parent ~= workspace:FindFirstChild("Townsfolk") then return end
		line = TALK.walkerLines[(index - 1) % #TALK.walkerLines + 1]
	end
	if shownIcon then shownIcon.Visible = false end
	shownIcon = if iconName then icons[iconName] else nil
	if shownIcon then shownIcon.Visible = true end
	padding.PaddingLeft = UDim.new(0, if shownIcon then 28 else 8)
	label.Text = line
	bubble.Adornee = currentHead
	bubbleEnds = os.clock() + TALK.bubbleSeconds
end)

RunService.RenderStepped:Connect(function()
	if bubbleEnds == 0 or not currentHead then return end
	if os.clock() >= bubbleEnds then
		clearBubble()
		return
	end
	local offset = bubbleOffset(currentHead)
	if offset then bubble.SizeOffset = offset end
	bubble.Enabled = offset ~= nil
end)

player.CharacterRemoving:Connect(function()
	setTarget(nil)
	updateCartVendors(nil)
end)

-- Only inspect nearby candidates at street speed. Walkers retain their own clock and movement loop.
while script:IsDescendantOf(game) do
	updateGuide()
	updateCartVendors(characterPosition())
	local position = talkPosition()
	if not position then
		setTarget(nil)
	elseif bubbleEnds > 0 and currentHead and os.clock() < bubbleEnds
		and (talkAnchorPosition(currentHead) - position).Magnitude <= TALK.range and layoutAllows(currentHead) then
		-- Keep the current speaker while the short line finishes.
		promptAnchor.Position = talkAnchorPosition(currentHead)
	else
		clearBubble()
		setTarget(nearestHead(position))
	end
	local foodWindow = playerGui:FindFirstChild("FoodVendor")
	local actor = currentHead and currentHead.Parent
	local vendor = actor and vendorActors[actor]
	buyPrompt.Enabled = prompt.Enabled and vendor ~= nil and CARTS[vendor.index].name == "Fishball"
		and foodWindow ~= nil and foodWindow:IsA("ScreenGui") and not foodWindow.Enabled
	task.wait(TALK.updateSeconds)
end
