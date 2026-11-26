-- CustomerNpcService.luau (ServerScriptService.Server.Services.CustomerNpcService)
-- Purpose: the BODIES of customers: spawn the model for each customer CustomerService lets in, walk it
-- Door -> Browse -> chosen shelf -> counter queue -> Exit, run the Checkout prompt (owner only, +10%) and the
-- auto checkout. All decisions (who comes, what they buy, the price) stay in CustomerService.
-- Town life (Dev 3, 2026-11-24): if the plot has CustomerPath.StreetEntry + Approach, the customer fades in out on the
-- street, walks StreetEntry -> Approach -> Door, and on leaving walks back out the same way and fades away (no popping
-- in at the door). Plots without them still start at the Door.
-- Owner: Dev 3 (Sean) (agreed with Ace: he owns CustomerService's rules, this file only reacts to it).
-- Depends on: CustomerService (SetSpawnHandler/SetRemovedHandler, ChooseItem, Checkout), PlotService.GetPlot,
-- ServerStorage.NPCs.<CustomerType>, plot CustomerPath.{StreetEntry?,Approach?,Door,Browse1..N,CounterSpot,Exit}, DisplaySlots/Slot<N>,
-- Counter.CheckoutPrompt, Shared.Config.Economy (QueuePatienceSeconds, Think*), Shared.Config.Customers (walkSpeed),
-- walk/idle animations from the model's Animate folder (Roblox defaults if missing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")

local Log = require(script.Parent.Parent.Lib.Log)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Customers = require(ReplicatedStorage.Shared.Config.Customers)
local Lines = require(ReplicatedStorage.Shared.Config.CustomerLines)

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
local FADE_TIME = 0.6 -- customers fade in/out on the street instead of popping
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
	haggle: number?, -- the discount (fraction) this customer asks for at the till, if it haggles
	haggleOpen: boolean?, -- asked, waiting for the owner's Accept / Decline: the Checkout prompt is replaced by those two
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

-- Where customers stand to look at each shelf: the StandSpot attachment on every shelf (it moves with the shelf in edit mode).
local function shelfSpots(plot: Instance): { Vector3 }
	local out = {}
	local shelves = plot:FindFirstChild("Shelves")
	for _, shelf in if shelves then shelves:GetChildren() else {} do
		local spot = shelf:FindFirstChild("StandSpot")
		if shelf:IsA("BasePart") and spot and spot:IsA("Attachment") then
			table.insert(out, Vector3.new(spot.WorldPosition.X, shelf.Position.Y - shelf.Size.Y / 2, spot.WorldPosition.Z))
		end
	end
	return out
end

-- Where to stand to look at a shelf slot: the aisle line through the browse points, level with the slot.
local function standPointForSlot(plot: Instance, slotIndex: number): Vector3?
	local slots = plot:FindFirstChild("DisplaySlots")
	local slot = slots and slots:FindFirstChild("Slot" .. slotIndex)
	if not (slot and slot:IsA("BasePart")) then
		return nil
	end
	-- the slot belongs to a shelf piece: stand at that shelf's StandSpot, wherever edit mode put it
	local shelfId = slot:GetAttribute("Piece")
	local shelf = plot:FindFirstChild("Shelves") and plot.Shelves:FindFirstChild(tostring(shelfId))
	local spot = shelf and shelf:FindFirstChild("StandSpot")
	if shelf and shelf:IsA("BasePart") and spot and spot:IsA("Attachment") then
		return Vector3.new(spot.WorldPosition.X, shelf.Position.Y - shelf.Size.Y / 2, spot.WorldPosition.Z)
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

-- One straight MoveTo with a timeout. Returns reached, cancelled.
local function moveStep(npc: Npc, target: Vector3, isExit: boolean?): (boolean, boolean)
	local humanoid = npc.humanoid
	local finished, success = false, false
	local connection = humanoid.MoveToFinished:Connect(function(ok)
		finished, success = true, ok
	end)
	humanoid:MoveTo(target)
	local started = os.clock()
	while not finished and os.clock() - started < WALK_TIMEOUT do
		if npc.gone and not isExit then
			break
		end
		task.wait(0.1)
	end
	connection:Disconnect()
	return finished and success, npc.gone and not isExit
end

-- Walks around furniture with the Roblox pathfinder (shelves can stand anywhere since edit mode, upstairs too). Returns
-- "reached", "cancelled" or "failed" (no path / blocked): the caller then falls back to the straight walk.
local function followPath(npc: Npc, target: Vector3, isExit: boolean?): string
	local root = npc.model.PrimaryPart
	if root == nil then
		return "failed"
	end
	local path = PathfindingService:CreatePath({ AgentRadius = 1.8, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
	local ok = pcall(function()
		path:ComputeAsync(root.Position, target)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return "failed"
	end
	local waypoints = path:GetWaypoints()
	for i = 2, #waypoints do
		local reached, cancelled = moveStep(npc, waypoints[i].Position, isExit)
		if cancelled then
			return "cancelled"
		end
		if not reached then
			return "failed"
		end
	end
	return "reached"
end

-- Walks to a point. Returns false if the visit was cancelled on the way (unless this IS the walk out).
local function walkTo(npc: Npc, target: Vector3, isExit: boolean?): boolean
	local humanoid = npc.humanoid
	if humanoid.Parent == nil or humanoid.Health <= 0 then
		return false
	end
	local pathResult = followPath(npc, target, isExit)
	if pathResult == "reached" then
		return true
	elseif pathResult == "cancelled" then
		return false
	end
	-- no path (or it got stuck): the old straight walk, and as a last resort the customer is placed at the point
	local reached, cancelled = moveStep(npc, target, isExit)
	if not reached and not cancelled and npc.model.Parent then
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
	local ready = front ~= nil and front.atCounter and not front.gone
	local haggling = ready and front.haggleOpen == true
	prompt.Enabled = ready and not haggling
	prompt.ActionText = "Checkout"
	prompt.ObjectText = if front then front.typeId else ""
	-- a haggler asks first: Accept / Decline instead of Checkout until the owner answers
	for _, name in { "HaggleYes", "HaggleNo" } do
		local answer = counter and counter:FindFirstChild(name)
		if answer and answer:IsA("ProximityPrompt") then
			answer.Enabled = haggling
			answer.ObjectText = if front then front.typeId else ""
			if name == "HaggleYes" and front and front.haggle then
				answer.ActionText = string.format("Accept -%d%%", math.floor(front.haggle * 100 + 0.5))
			end
		end
	end
end

local resolveHaggle: (Player, boolean) -> () -- set below, once `say` exists

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
	-- Haggling (2026-11-25): two extra prompts on the same counter, only on while the customer at the front is asking for a discount.
	for _, spec in { { "HaggleYes", "Accept", Enum.KeyCode.F, Enum.KeyCode.ButtonX, -80, true }, { "HaggleNo", "Decline", Enum.KeyCode.G, Enum.KeyCode.ButtonY, 80, false } } do
		local answer = prompt:Clone()
		answer.Name = spec[1]
		answer.ActionText = spec[2]
		answer.KeyboardKeyCode = spec[3]
		answer.GamepadKeyCode = spec[4]
		answer.UIOffset = Vector2.new(spec[5], 0)
		answer.Enabled = false
		answer.Parent = counter
		answer.Triggered:Connect(function(tapper: Player)
			if plot:GetAttribute("OwnerUserId") == tapper.UserId then
				resolveHaggle(tapper, spec[6])
			end
		end)
	end
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

-- Fades the whole body in (visible = true) or out. Each part remembers its own look (BaseTransparency) so glasses,
-- hair and the invisible root part come back exactly as they were. The server's tween replicates to everyone.
local function fade(model: Model, visible: boolean)
	for _, d in model:GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			local base = d:GetAttribute("BaseTransparency")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			if visible then
				d.Transparency = 1
			end
			TweenService:Create(d, TweenInfo.new(FADE_TIME), { Transparency = if visible then base else 1 }):Play()
		end
	end
end

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
	-- back out to the street the way they came, then fade away
	local approach = plot and pathPoint(plot, "Approach")
	local street = plot and pathPoint(plot, "StreetEntry")
	if approach and street and npc.model.Parent then
		walkTo(npc, approach, true)
		walkTo(npc, street, true)
		fade(npc.model, false)
		task.wait(FADE_TIME)
	end
	npcs[npc.id] = nil
	if npc.model.Parent then
		npc.model:Destroy()
	end
end

-- Turns the customer smoothly to look at a point (flat), so it never faces the wrong way at a shelf or the till.
local function faceToward(npc: Npc, target: Vector3)
	local root = npc.model.PrimaryPart
	if not (root and npc.model.Parent) then
		return
	end
	local from = root.Position
	local flat = Vector3.new(target.X, from.Y, target.Z)
	if (flat - from).Magnitude < 0.1 then
		return
	end
	TweenService:Create(root, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(from, flat) }):Play()
end

-- A speech bubble line for a moment (the UI shows the "Say" attribute); cleared after `seconds`.
local function say(npc: Npc, group: { string }?, seconds: number?)
	if not (group and #group > 0 and npc.model.Parent) then
		return
	end
	local line = group[Random.new():NextInteger(1, #group)]
	npc.model:SetAttribute("Say", line)
	task.delay(seconds or 2.4, function()
		if npc.model.Parent and npc.model:GetAttribute("Say") == line then
			npc.model:SetAttribute("Say", "")
		end
	end)
end

local function randomIn(range: { number }): number
	return Random.new():NextNumber(range[1], range[2])
end

-- The owner answered a haggle. Accept: the sale is at the lower price (till and payment both use it). Decline: the customer may
-- leave without buying (chance = discount x HaggleLeaveFactor), otherwise it pays full price but never tips.
function resolveHaggle(owner: Player, accept: boolean)
	local front = frontNpc(owner)
	if not (front and front.atCounter and not front.gone and front.haggleOpen) then
		return
	end
	front.haggleOpen = false
	local ask = front.haggle or 0
	if accept then
		CustomerService.SetPriceMult(owner, front.id, 1 - ask)
		say(front, Lines.deal, 2.5)
		log.info(front.id, "haggle accepted:", ask)
	elseif Random.new():NextNumber() < ask * Economy.HaggleLeaveFactor then
		say(front, Lines.refused, 2.5)
		front.atCounter = false
		refreshPrompt(owner)
		log.info(front.id, "haggle declined: the customer left")
		CustomerService.Leave(owner, front.id, "haggled")
		return
	else
		CustomerService.SetNoTip(owner, front.id)
		say(front, Lines.grumble, 2.5)
		log.info(front.id, "haggle declined: the customer pays full price")
	end
	refreshPrompt(owner)
end

-- Browse the shelves, choose an item and decide (buy / think / pass). Returns true when the customer wants to pay.
local function shopForItem(npc: Npc, plot: Instance, returning: boolean): boolean
	local points = shelfSpots(plot)
	if #points == 0 then
		points = browsePoints(plot)
	end
	local rng = Random.new()
	local personality = Customers[npc.typeId] or {}
	local browseMult = personality.browseMult or 1
	-- a window shopper looks at more shelves for longer, a kid rushes through
	for _ = 1, math.min(#points, rng:NextInteger(1, if browseMult > 1.2 then 3 else 2)) do
		if not walkTo(npc, points[rng:NextInteger(1, #points)]) or not waitWhileHere(npc, BROWSE_PAUSE * browseMult) then
			return false
		end
	end
	-- Pick an item (reserves it). nil = nothing to buy: CustomerService removes it, the removed handler walks it out.
	local choice = CustomerService.ChooseItem(npc.player, npc.id)
	if choice == nil then
		return false
	end
	npc.model:SetAttribute("ItemId", choice.itemId)
	local stand = standPointForSlot(plot, choice.slot)
	if stand and not walkTo(npc, stand) then
		return false
	end
	-- look at the item (turn to the shelf slot), say something, take a moment: never an instant sale
	local slots = plot:FindFirstChild("DisplaySlots")
	local slotPart = slots and slots:FindFirstChild("Slot" .. choice.slot)
	if slotPart and slotPart:IsA("BasePart") then
		faceToward(npc, slotPart.Position)
	end
	say(npc, Lines.look, SHELF_PAUSE)
	if not waitWhileHere(npc, SHELF_PAUSE + 1) then
		return false
	end
	local outcome, reason = CustomerService.Judge(npc.player, npc.id, nil, returning)
	if outcome == "buy" then
		say(npc, if returning then Lines.back else Lines.buy, 2)
		waitWhileHere(npc, 1.2)
		if npc.gone then
			return false
		end
		-- some customers will ask for a discount once they get to the till (see Customers.<type>.haggleChance)
		npc.haggle = CustomerService.HaggleOffer(npc.typeId)
		npc.haggleOpen = npc.haggle ~= nil
		return true
	end
	if outcome == "think" then
		-- "let me think about it": puts the item back, wanders off, may come back
		say(npc, Lines.think, 2.6)
		waitWhileHere(npc, 1.4)
		npc.model:SetAttribute("ItemId", nil)
		CustomerService.Reconsider(npc.player, npc.id)
		local wander = points[rng:NextInteger(1, math.max(1, #points))]
		if wander and not walkTo(npc, wander) then
			return false
		end
		if not waitWhileHere(npc, randomIn(Economy.ThinkAwaySeconds)) then
			return false
		end
		if rng:NextNumber() < Economy.ThinkReturnChance then
			return shopForItem(npc, plot, true)
		end
		say(npc, Lines.gone, 2.5)
		waitWhileHere(npc, 1.5)
		CustomerService.Leave(npc.player, npc.id, "passed")
		return false
	end
	local lines = Lines.critique[reason or "notWanted"] or Lines.critique.notWanted
	say(npc, lines, 3)
	waitWhileHere(npc, 2.2)
	CustomerService.Leave(npc.player, npc.id, "passed")
	return false
end

local function runVisit(npc: Npc, plot: Instance)
	-- Walk in from the street (only if this plot has the street markers).
	local approach = pathPoint(plot, "Approach")
	local door = pathPoint(plot, "Door")
	if pathPoint(plot, "StreetEntry") and approach and door then
		if not walkTo(npc, approach) or not walkTo(npc, door) then
			return
		end
	end

	if not shopForItem(npc, plot, false) or npc.gone then
		return
	end

	-- Queue at the counter, moving up as the people in front are served.
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

	-- At the counter: face the till and WAIT for the owner (no auto-pay any more). Hellos while waiting; after the patience
	-- limit the customer leaves without buying and the item goes back on the shelf.
	npc.atCounter = true
	npc.model:SetAttribute("AtCounter", true) -- lets the tests (and anything else) see who is waiting at the till
	local counter = plot:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		faceToward(npc, counter.Position)
	end
	refreshPrompt(npc.player)
	local waited, nextHello = 0, randomIn(Economy.QueueHelloSeconds)
	local patience = (Economy.QueuePatienceSeconds or 90) * ((Customers[npc.typeId] or {}).patienceMult or 1)
	local nextAsk = 0.5 -- a haggler asks right away, then repeats until answered
	local function ask()
		local pct = math.floor((npc.haggle or 0) * 100 + 0.5)
		local template = Lines.haggle[Random.new():NextInteger(1, #Lines.haggle)]
		say(npc, { string.format(template, pct) }, 4)
	end
	while not npc.gone do
		if CashierService ~= nil and CashierService.IsOpenFor(npc.player, npc.id) then
			waited = 0 -- the owner is on it
		else
			waited += 0.25
			if waited >= patience then
				say(npc, Lines.gone, 2.5)
				npc.atCounter = false
				refreshPrompt(npc.player)
				log.info(npc.id, "gave up waiting at the till")
				CustomerService.Leave(npc.player, npc.id, "impatient")
				return
			elseif npc.haggleOpen then
				if waited >= nextAsk then
					ask()
					nextAsk = waited + randomIn(Economy.HaggleRepeatSeconds)
				end
			elseif waited >= nextHello then
				say(npc, Lines.hello, 2.5)
				nextHello = waited + randomIn(Economy.QueueHelloSeconds)
			end
		end
		task.wait(0.25)
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
	-- start out on the street (facing the shop) if the plot has a StreetEntry, else at the door as before
	local street = pathPoint(plot, "StreetEntry")
	if street then
		model:PivotTo(CFrame.lookAt(street + LIFT, Vector3.new(door.X, street.Y + LIFT.Y, door.Z)))
	else
		model:PivotTo(CFrame.new(door + LIFT))
	end
	model.Parent = folder
	if street then
		fade(model, true)
	end
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

-- ===== Cash register bubbles (called by CashierService) =====
-- Attributes on the NPC model, shown by CustomerUIController for everyone: CashierPaid = what the customer handed over
-- while the till is open (nil = closed), Mood = "Delighted" | "Happy" | "Upset" | "Angry" (kept while they walk out).
function CustomerNpcService.SetCashierState(customerId: string, paid: number?, mood: string?)
	local npc = npcs[customerId]
	if npc == nil or npc.model.Parent == nil then
		return
	end
	npc.model:SetAttribute("CashierPaid", paid)
	if mood ~= nil then
		npc.model:SetAttribute("Mood", mood)
	end
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
