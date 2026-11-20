-- CustomerNpcService.luau (ServerScriptService.Server.Services.CustomerNpcService)
-- Purpose: the BODIES of customers: spawn the model for each customer CustomerService lets in, walk it
-- Door -> Browse -> chosen shelf -> counter queue -> Exit, run the Checkout prompt (owner only, +10%) and the
-- auto checkout. All decisions (who comes, what they buy, the price) stay in CustomerService.
-- Owner: Dev 3 (Sean) (agreed with Ace: he owns CustomerService's rules, this file only reacts to it).
-- Depends on: CustomerService (SetSpawnHandler/SetRemovedHandler, ChooseItem, Checkout), PlotService.GetPlot,
-- ServerStorage.NPCs.<CustomerType>, plot CustomerPath.{Door,Browse1..N,CounterSpot,Exit}, DisplaySlots/Slot<N>,
-- Counter.CheckoutPrompt, Shared.Config.Economy.AutoCheckoutSeconds, Shared.Config.Customers (walkSpeed),
-- walk/idle animations from the model's Animate folder (Roblox defaults if missing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Customers = require(ReplicatedStorage.Shared.Config.Customers)

local CustomerNpcService = {}
local DEBUG = true
local log = Log.new("CustomerNpcService", DEBUG)

local CustomerService, PlotService = nil, nil
local CashierService = nil -- Ace: the till (counter tap opens it; auto-checkout waits while it's open)

local WALK_TIMEOUT = 6 -- seconds per waypoint; after that the NPC is placed there so it can never get stuck
local BROWSE_PAUSE = 1.5 -- looks around at each browse point
local SHELF_PAUSE = 2 -- looks at the item it picked
local QUEUE_GAP = 2.5 -- studs between customers waiting at the counter
local LIFT = Vector3.new(0, 3, 0) -- path markers sit on the floor; a placed model stands above them
local IDLE_FALLBACK = "rbxassetid://507766388" -- Roblox default R15 idle, used if a model has no Animate.idle
local WALK_FALLBACK = "rbxassetid://913402848" -- Roblox default R15 walk
local WALK_ANIM_SPEED = 16 -- the walk animation matches a WalkSpeed of 16; slower NPCs step slower so feet do not skate

type Npc = {
	id: string,
	player: Player,
	typeId: string,
	model: Model,
	humanoid: Humanoid,
	gone: boolean, -- CustomerService removed it (paid, left, timeout...): stop the visit, walk out
	leaving: boolean, -- the walk out has started (only once)
	atCounter: boolean, -- front of the queue and standing at the counter: Checkout prompt is on
}

local npcs: { [string]: Npc } = {} -- [customerId] = Npc
local queues: { [Player]: { string } } = {} -- [owner] = customer ids heading to / waiting at the counter, front first
local folder: Folder? = nil

-- ===== Helpers =====

local function pathPoint(plot: Instance, name: string): Vector3?
	local path = plot:FindFirstChild("CustomerPath")
	local part = path and path:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part.Position else nil
end

local function browsePoints(plot: Instance): { Vector3 }
	local points = {}
	local path = plot:FindFirstChild("CustomerPath")
	for i = 1, 20 do
		local part = path and path:FindFirstChild("Browse" .. i)
		if part and part:IsA("BasePart") then
			table.insert(points, part.Position)
		end
	end
	return points
end

-- Where to stand to look at a shelf slot: the aisle line through the browse points, level with the slot.
local function standPointForSlot(plot: Instance, slotIndex: number): Vector3?
	local slots = plot:FindFirstChild("DisplaySlots")
	local slot = slots and slots:FindFirstChild("Slot" .. slotIndex)
	if not (slot and slot:IsA("BasePart")) then
		return nil
	end
	local points = browsePoints(plot)
	if #points == 0 then
		return nil
	end
	local a, b = points[1], points[#points]
	local line = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	if line.Magnitude < 0.1 then
		return Vector3.new(a.X, a.Y, slot.Position.Z)
	end
	local dir = line.Unit
	local along = (Vector3.new(slot.Position.X, a.Y, slot.Position.Z) - a):Dot(dir)
	return a + dir * along
end

-- Queue spot N (1 = at the counter), stepping back away from the counter.
local function queuePoint(plot: Instance, index: number): Vector3?
	local spot = pathPoint(plot, "CounterSpot")
	local counter = plot:FindFirstChild("Counter")
	if spot == nil then
		return nil
	end
	local back = Vector3.new(0, 0, -1)
	if counter and counter:IsA("BasePart") then
		local away = Vector3.new(spot.X - counter.Position.X, 0, spot.Z - counter.Position.Z)
		if away.Magnitude > 0.1 then
			back = away.Unit
		end
	end
	return spot + back * QUEUE_GAP * (index - 1)
end

-- Walks to a point. Returns false if the visit was cancelled on the way (unless this IS the walk out).
local function walkTo(npc: Npc, target: Vector3, isExit: boolean?): boolean
	local humanoid = npc.humanoid
	if humanoid.Parent == nil or humanoid.Health <= 0 then
		return false
	end
	local reached = false
	local connection = humanoid.MoveToFinished:Connect(function()
		reached = true
	end)
	humanoid:MoveTo(target)
	local started = os.clock()
	while not reached and os.clock() - started < WALK_TIMEOUT do
		if npc.gone and not isExit then
			break
		end
		task.wait(0.1)
	end
	connection:Disconnect()
	local cancelled = npc.gone and not isExit
	if not reached and not cancelled and npc.model.Parent then
		-- Blocked (a wall, another NPC, a player): place it there instead of standing stuck forever.
		npc.model:PivotTo(CFrame.new(target + LIFT))
		log.info(npc.id, "was placed at a waypoint it couldn't reach")
	end
	return not cancelled
end

local function waitWhileHere(npc: Npc, seconds: number): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime do
		if npc.gone then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- ===== Checkout prompt (one per plot, on the counter) =====

local function frontNpc(player: Player): Npc?
	local queue = queues[player]
	local id = queue and queue[1]
	return id and npcs[id] or nil
end

local function refreshPrompt(player: Player)
	local plot = PlotService.GetPlot(player)
	local counter = plot and plot:FindFirstChild("Counter")
	local prompt = counter and counter:FindFirstChild("CheckoutPrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		return
	end
	local front = frontNpc(player)
	prompt.Enabled = front ~= nil and front.atCounter and not front.gone
	prompt.ActionText = "Checkout"
	prompt.ObjectText = if front then front.typeId else ""
end

local function removeFromQueue(npc: Npc)
	local queue = queues[npc.player]
	local index = queue and table.find(queue, npc.id)
	if index then
		table.remove(queue, index)
	end
	npc.atCounter = false
end

local function hookCheckoutPrompt(plot: Instance)
	local counter = plot:FindFirstChild("Counter")
	local prompt = counter and counter:FindFirstChild("CheckoutPrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		log.warn(plot.Name, "has no Counter.CheckoutPrompt")
		return
	end
	prompt.Enabled = false
	prompt.Triggered:Connect(function(tapper: Player)
		-- Only the shop owner can check out their own customers; visitors' taps are ignored.
		if plot:GetAttribute("OwnerUserId") ~= tapper.UserId then
			return
		end
		local front = frontNpc(tapper)
		if front == nil or not front.atCounter or front.gone then
			return
		end
		-- Cashier (Ace): open the till; the sale happens when the owner gives the right change (CashierService).
		-- Without the CashierService the old instant checkout still works.
		if CashierService then
			if not CashierService.IsOpenFor(tapper, front.id) then
				CashierService.Open(tapper, front.id)
			end
			return
		end
		front.atCounter = false
		refreshPrompt(tapper)
		local ok, reason, result = CustomerService.Checkout(tapper, front.id, true)
		log.info(`{tapper.Name} checked out {front.id}:`, ok, reason or "", result and result.total or "")
	end)
end

-- ===== One visit =====

local function walkOut(npc: Npc)
	if npc.leaving then
		return
	end
	npc.leaving = true
	removeFromQueue(npc)
	refreshPrompt(npc.player)
	local plot = PlotService.GetPlot(npc.player)
	local exit = plot and pathPoint(plot, "Exit")
	if exit and npc.model.Parent then
		walkTo(npc, exit, true)
	end
	npcs[npc.id] = nil
	if npc.model.Parent then
		npc.model:Destroy()
	end
end

local function runVisit(npc: Npc, plot: Instance)
	-- Browse: 1 or 2 random points.
	local points = browsePoints(plot)
	local rng = Random.new()
	for _ = 1, math.min(#points, rng:NextInteger(1, 2)) do
		if not walkTo(npc, points[rng:NextInteger(1, #points)]) or not waitWhileHere(npc, BROWSE_PAUSE) then
			return
		end
	end

	-- Pick an item (reserves it). nil = nothing to buy: CustomerService removes it, the removed handler walks it out.
	local choice = CustomerService.ChooseItem(npc.player, npc.id)
	if choice == nil then
		return
	end
	npc.model:SetAttribute("ItemId", choice.itemId)
	local stand = standPointForSlot(plot, choice.slot)
	if stand and (not walkTo(npc, stand) or not waitWhileHere(npc, SHELF_PAUSE)) then
		return
	end

	-- Queue at the counter, moving up as the people in front leave.
	queues[npc.player] = queues[npc.player] or {}
	table.insert(queues[npc.player], npc.id)
	local walkedToIndex = nil
	while not npc.gone do
		local index = table.find(queues[npc.player] or {}, npc.id)
		if index == nil then
			return
		end
		if index ~= walkedToIndex then
			local spot = queuePoint(plot, index)
			if spot and not walkTo(npc, spot) then
				return
			end
			walkedToIndex = index
		end
		if index == 1 then
			break
		end
		task.wait(0.25)
	end
	if npc.gone then
		return
	end

	-- At the counter: the owner can tap Checkout (+10%); otherwise it pays by itself after AutoCheckoutSeconds.
	npc.atCounter = true
	refreshPrompt(npc.player)
	-- Auto-checkout after AutoCheckoutSeconds, but never while the owner has the till open for this customer.
	local waited = 0
	local limit = Economy.AutoCheckoutSeconds or 8
	while not npc.gone do
		local serving = CashierService ~= nil and CashierService.IsOpenFor(npc.player, npc.id)
		if not serving then
			waited += 0.25
			if waited >= limit then
				break
			end
		end
		task.wait(0.25)
	end
	if not npc.gone then
		npc.atCounter = false
		refreshPrompt(npc.player)
		local ok, reason = CustomerService.Checkout(npc.player, npc.id, false)
		log.info(npc.id, "auto checkout:", ok, reason or "")
	end
end

-- ===== Animations =====
-- The NPC templates carry Roblox's standard "Animate" LocalScript, but LocalScripts never run inside a workspace
-- model, so the server plays walk/idle itself. Animations a server-owned Animator plays replicate to every player.

local function animationFrom(model: Model, folderName: string, fallbackId: string): Animation
	local animate = model:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild(folderName)
	local found = holder and holder:FindFirstChildWhichIsA("Animation")
	if found then
		return found -- whatever an artist put in the model wins
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = fallbackId
	return animation
end

local function startAnimations(model: Model, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local ok, err = pcall(function()
		local idle = animator:LoadAnimation(animationFrom(model, "idle", IDLE_FALLBACK))
		local walk = animator:LoadAnimation(animationFrom(model, "walk", WALK_FALLBACK))
		idle.Looped = true
		walk.Looped = true
		idle:Play()
		-- Running fires with the current speed whenever it changes (also 0 when MoveTo ends).
		humanoid.Running:Connect(function(speed: number)
			if speed > 0.5 then
				if not walk.IsPlaying then
					walk:Play(0.2)
				end
				walk:AdjustSpeed(speed / WALK_ANIM_SPEED)
			elseif walk.IsPlaying then
				walk:Stop(0.2)
			end
		end)
	end)
	if not ok then
		log.warn("animations failed for", model.Name, err) -- the NPC still walks, it just slides
	end
end

-- CustomerService calls this (in its own thread) when a customer arrives. An error here = customer removed ("spawnFailed").
local function onSpawn(player: Player, customer)
	local plot = PlotService.GetPlot(player)
	assert(plot, "player has no plot")
	local door = pathPoint(plot, "Door")
	assert(door, `{plot.Name} has no CustomerPath.Door`)
	local templates = ServerStorage:FindFirstChild("NPCs")
	local template = templates and templates:FindFirstChild(customer.typeId)
	assert(template and template:IsA("Model"), `no ServerStorage.NPCs.{customer.typeId}`)

	local model = template:Clone()
	model.Name = "Customer_" .. customer.id
	model:SetAttribute("CustomerId", customer.id)
	model:SetAttribute("CustomerType", customer.typeId)
	model:SetAttribute("Wish", customer.wish)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:PivotTo(CFrame.new(door + LIFT))
	model.Parent = folder
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "NPC model has no Humanoid")
	local root = model.PrimaryPart
	if root then
		root:SetNetworkOwner(nil) -- the server walks it; no player's physics should move it
	end
	local typeConfig = Customers[customer.typeId]
	if typeConfig and typeConfig.walkSpeed then
		humanoid.WalkSpeed = typeConfig.walkSpeed
	end
	startAnimations(model, humanoid)

	local npc: Npc = {
		id = customer.id,
		player = player,
		typeId = customer.typeId,
		model = model,
		humanoid = humanoid,
		gone = false,
		leaving = false,
		atCounter = false,
	}
	npcs[customer.id] = npc
	log.info(`{customer.typeId} {customer.id} walks into {plot.Name} (wants {customer.wish})`)
	runVisit(npc, plot)
end

-- CustomerService calls this (own thread) whenever a customer is gone, with the reason (see its header).
local function onRemoved(_player: Player, customerId: string, reason: string)
	local npc = npcs[customerId]
	if npc == nil then
		return
	end
	npc.gone = true
	log.info(customerId, "removed:", reason)
	if reason == "playerLeft" or reason == "spawnFailed" then
		removeFromQueue(npc)
		npcs[customerId] = nil
		if npc.model.Parent then
			npc.model:Destroy()
		end
		return
	end
	walkOut(npc)
end

-- ===== Lifecycle =====

function CustomerNpcService.Init(services)
	CustomerService = services.CustomerService
	PlotService = services.PlotService
	CashierService = services.CashierService
	log.info("Init")
end

function CustomerNpcService.Start()
	local existing = workspace:FindFirstChild("Customers")
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Customers"
	folder.Parent = workspace

	local plots = workspace:FindFirstChild("Plots")
	for _, plot in (plots and plots:GetChildren() or {}) do
		hookCheckoutPrompt(plot)
	end
	Players.PlayerRemoving:Connect(function(player)
		queues[player] = nil
	end)

	CustomerService.SetSpawnHandler(onSpawn)
	CustomerService.SetRemovedHandler(onRemoved)
	log.info("Start: customers can walk in")
end

return CustomerNpcService
