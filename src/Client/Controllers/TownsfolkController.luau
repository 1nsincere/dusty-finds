-- TownsfolkController.luau (StarterPlayerScripts.Client.Controllers.TownsfolkController)
-- Purpose: ambient townspeople walking the streets so the town feels alive. Pure decoration, drawn on each client, but
-- SHARED: every walker's position is a pure function of the server clock (workspace:GetServerTimeNow()) and a fixed
-- seed, so every player sees the same person in the same place at the same moment, with no server work and nothing
-- sent over the network. Walkers follow Config.Townsfolk.Routes there and back, sometimes pausing at a corner. They
-- never collide and can't be clicked. Close ones animate every frame, far ones update rarely, very far ones are hidden.
-- Phones / "Reduce effects" show the first CountReduced walkers (the same people, just fewer).
-- Owner: Dev 3 (Sean). Depends on: Shared.Config.Townsfolk, ReplicatedStorage.Assets.Townsfolk (R15 look models,
-- classic Roblox outfits), ClientState (settings.reduceEffects). Customers are NOT townsfolk: they are server NPCs
-- (CustomerNpcService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Townsfolk = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Townsfolk"))
local TownPoints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("TownPoints"))
local Hours = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Hours"))
local TownGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TownGraph"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local TownsfolkController = {}
local DEBUG = true

local IDLE_FALLBACK = "rbxassetid://507766388" -- Roblox default R15 idle
local WALK_FALLBACK = "rbxassetid://913402848" -- Roblox default R15 walk
local WALK_ANIM_SPEED = 16 -- the default walk animation matches WalkSpeed 16
local FAR_UPDATE = 0.3 -- seconds between position updates for walkers outside AnimateWithin
local SEED_BASE = 20261124 -- change this (on purpose) to reshuffle everyone; must be the same on every client

-- One stretch of a walker's day: walk from `from` to `to` in `walk` seconds, then stand still for `pause` seconds.
-- `face` / `say` are set on legs that end at a town point (cart, bench): the walker turns to `face` and shows `say` while it waits.
type Leg = { from: Vector3, to: Vector3, walk: number, pause: number, face: Vector3?, say: string?, stopId: string? }

-- A place a walker may stop: a spot on a graph edge, what to look at, how long to wait, what to say (WP5 step B).
type TownStop = { id: string, point: Vector3, stand: Vector3, target: Vector3, kind: string, dwell: { number }, vendorPos: Vector3? }

local BUBBLE_RANGE = 50 -- studs from the camera: only close walkers show a speech bubble

-- A cart vendor (WP6): a townsfolk body that stands behind the cart during market hours, calls out, and serves walkers that stop.
type Vendor = { id: string, walker: Walker, pos: Vector3, phase: number, servedAt: number }

type Walker = {
	model: Model,
	legs: { Leg },
	cycle: number, -- seconds for one full there-and-back loop (walking + pauses)
	offset: number, -- where in the loop this walker is at server time 0
	speed: number,
	side: number, -- studs to the right of the route line, so people on one route don't overlap
	rootOffset: number, -- root height above the ground
	walkTrack: AnimationTrack?,
	idleTrack: AnimationTrack?,
	animating: boolean,
	bubble: BillboardGui?,
	lastUpdate: number,
	shown: boolean,
}

local walkers: { Walker } = {}
local bubblesEnabled = false
local vendors: { Vendor } = {} -- WP6: cosmetic cart vendors, only at carts a walker can stop at
local vendorsById: { [string]: Vendor } = {}
local folder: Folder? = nil

local function log(...)
	if DEBUG then
		print("[TownsfolkController]", ...)
	end
end

local function parseRoute(text: string): { Vector3 }
	local points = {}
	for _, triple in string.split(text, ";") do
		local x, y, z = string.match(triple, "(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)")
		if x then
			table.insert(points, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
		end
	end
	return points
end

local function animationFrom(model: Model, folderName: string, fallbackId: string): Animation
	local animate = model:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild(folderName)
	local found = holder and holder:FindFirstChildWhichIsA("Animation")
	if found then
		return found
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = fallbackId
	return animation
end

-- A cheap, harmless copy of a look: no collisions, no clicks, no name tag, no physics state machine; only the root is
-- anchored (the limbs hang off it with their joints, so animations still move them).
local function makeBody(template: Model): (Model?, number)
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil, 0
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d == root
			d.CastShadow = d ~= root
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Enabled = false
		end
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	model.PrimaryPart = root
	model.WorldPivot = root.CFrame -- PivotTo must move the ROOT to the target, whatever pivot the template kept
	-- how high the root sits above the feet: Roblox's own rule (HipHeight + half the root) when the rig has one
	if humanoid.HipHeight > 0 then
		return model, humanoid.HipHeight + root.Size.Y / 2
	end
	local cf, size = model:GetBoundingBox()
	return model, root.Position.Y - (cf.Position.Y - size.Y / 2)
end

local function startAnimations(walker: Walker)
	local humanoid = walker.model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local ok = pcall(function()
		walker.walkTrack = animator:LoadAnimation(animationFrom(walker.model, "walk", WALK_FALLBACK))
		walker.idleTrack = animator:LoadAnimation(animationFrom(walker.model, "idle", IDLE_FALLBACK))
		walker.walkTrack.Looped = true
		walker.idleTrack.Looped = true
	end)
	if not ok then
		walker.walkTrack, walker.idleTrack = nil, nil
	end
end

local function setAnimating(walker: Walker, on: boolean, paused: boolean)
	local walk, idle = walker.walkTrack, walker.idleTrack
	if not (walk and idle) then
		return
	end
	if not on then
		if walk.IsPlaying then walk:Stop(0.2) end
		if idle.IsPlaying then idle:Stop(0.2) end
		walker.animating = false
		return
	end
	walker.animating = true
	if paused then
		if walk.IsPlaying then walk:Stop(0.25) end
		if not idle.IsPlaying then idle:Play(0.25) end
	else
		if idle.IsPlaying then idle:Stop(0.25) end
		if not walk.IsPlaying then
			walk:Play(0.25)
			walk:AdjustSpeed(walker.speed / WALK_ANIM_SPEED * 1.6) -- a little brisker than real time so short steps don't slide
		end
	end
end

-- The fixed "day" of walker i: same seed on every client = same route, look, speed, pauses and starting point.
-- Is point p (flat) within 0.6 studs of the segment a-b, at about the same height?
local function onSegment(p: Vector3, a: Vector3, b: Vector3): boolean
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len2 = ab:Dot(ab)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local t = if len2 == 0 then 0 else math.clamp(ap:Dot(ab) / len2, 0, 1)
	local nearest = a:Lerp(b, t)
	return Vector3.new(p.X - nearest.X, 0, p.Z - nearest.Z).Magnitude < 0.6 and math.abs(p.Y - nearest.Y) < 2
end

local function planWalker(i: number, routes: { { Vector3 } }, templateCount: number, graph: TownGraph.Graph, stops: { TownStop })
	local rng = Random.new(SEED_BASE + i * 7919)
	local routeIndex = (i - 1) % #routes + 1 -- spread evenly: every route gets someone before any gets two
	local route = routes[routeIndex]
	local startNode = graph.routeStart[routeIndex]
	if startNode then
		-- WP5: start where this route starts, then wander the graph (switching routes at shared corners)
		route = TownGraph.walk(graph, startNode, rng, Townsfolk.GraphLegs[1], Townsfolk.GraphLegs[2])
		if #route < 2 then
			route = routes[routeIndex]
		end
	end
	local look = rng:NextInteger(1, templateCount)
	local speed = rng:NextNumber(Townsfolk.WalkSpeed[1], Townsfolk.WalkSpeed[2])
	local side = rng:NextNumber(-1.2, 1.2)
	local legs: { Leg } = {}
	local cycle = 0
	local function push(a: Vector3, b: Vector3, pause: number, face: Vector3?, say: string?, stopId: string?)
		local walk = (b - a).Magnitude / speed
		table.insert(legs, { from = a, to = b, walk = walk, pause = pause, face = face, say = say, stopId = stopId })
		cycle += walk + pause
	end
	local function addLeg(a: Vector3, b: Vector3)
		-- a town point lying on this leg: maybe stop there (split the leg), facing the cart / bench
		local stop: TownStop? = nil
		for _, s in stops do
			if onSegment(s.point, a, b) and rng:NextNumber() < TownPoints.Chance then
				stop = s
				break
			end
		end
		if stop then
			local lines = TownPoints.Lines[stop.kind]
			local say = if lines then lines[rng:NextInteger(1, #lines)] else nil
			push(a, stop.stand, rng:NextNumber(stop.dwell[1], stop.dwell[2]), stop.target, say, stop.id)
			push(stop.stand, b, 0)
			return
		end
		push(a, b, if rng:NextNumber() < Townsfolk.PauseChance then rng:NextNumber(Townsfolk.PauseSeconds[1], Townsfolk.PauseSeconds[2]) else 0)
	end
	for k = 1, #route - 1 do -- there...
		addLeg(route[k], route[k + 1])
	end
	for k = #route, 2, -1 do -- ...and back
		addLeg(route[k], route[k - 1])
	end
	return look, speed, side, legs, cycle, rng:NextNumber(0, cycle)
end

-- Where walker w is at server time t (pure: no state). Returns ground point, facing direction, paused?
local function positionAt(walker: Walker, t: number): (Vector3, Vector3, boolean, string?, string?)
	local tt = (t + walker.offset) % walker.cycle
	for _, leg in walker.legs do
		local dir = leg.to - leg.from
		if tt < leg.walk then
			return leg.from + dir * (tt / leg.walk), dir, false, nil, nil
		end
		tt -= leg.walk
		if tt < leg.pause then
			-- waiting at a cart / bench: turn toward it
			return leg.to, if leg.face then leg.face - leg.to else dir, true, leg.say, leg.stopId
		end
		tt -= leg.pause
	end
	local last = walker.legs[#walker.legs]
	return last.to, last.to - last.from, true, nil, nil
end

-- Moves the walker to where it is at time t. Returns paused?, the bubble line, and the town point it waits at (both nil unless
-- it is waiting at a cart / bench).
local function place(walker: Walker, t: number): (boolean, string?, string?)
	local ground, dir, paused, say, stopId = positionAt(walker, t)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return paused, say, stopId
	end
	local unit = flat.Unit
	local p = ground + unit:Cross(Vector3.yAxis) * walker.side
	local at = Vector3.new(p.X, p.Y + walker.rootOffset, p.Z)
	walker.model:PivotTo(CFrame.lookAt(at, at + unit))
	return paused, say, stopId
end

-- A small speech bubble over the head, made on first use and only for close walkers (see BUBBLE_RANGE). nil text hides it.
local function setBubble(walker: Walker, text: string?)
	local gui = walker.bubble
	if text == nil then
		if gui and gui.Enabled then
			gui.Enabled = false
		end
		return
	end
	if gui == nil then
		local head = walker.model:FindFirstChild("Head")
		if not (head and head:IsA("BasePart")) then
			return
		end
		gui = Instance.new("BillboardGui")
		gui.Name = "TownBubble"
		gui.Adornee = head
		gui.Size = UDim2.fromOffset(150, 30)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = BUBBLE_RANGE + 10
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 250, 238)
		label.BackgroundTransparency = 0.1
		label.TextColor3 = Color3.fromRGB(70, 50, 40)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		gui.Parent = head
		walker.bubble = gui
	end
	gui.Text.Text = text
	gui.Enabled = true
end

local function reducedCount(): boolean
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return touchOnly or ClientState.Get("settings.reduceEffects") == true
end

local function spawnWalkers()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local looks = assets and assets:WaitForChild("Townsfolk", 10)
	local templates = {}
	for _, m in (looks and looks:GetChildren() or {}) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(templates, m)
		end
	end
	if #templates == 0 then
		warn("[TownsfolkController] no looks in ReplicatedStorage.Assets.Townsfolk: no townsfolk")
		return
	end
	table.sort(templates, function(a, b) -- same order on every client, so look N is the same person everywhere
		return a.Name < b.Name
	end)
	local routes = {}
	for _, text in Townsfolk.Routes do
		local route = parseRoute(text)
		if #route >= 2 then
			table.insert(routes, route)
		end
	end
	if #routes == 0 then
		return
	end
	local excluded = {}
	for _, n in Townsfolk.GraphExcluded do
		excluded[n] = true
	end
	local graph = TownGraph.build(routes, excluded)
	-- WP5 step B: the carts and benches that sit near a scanned walking line become stops on that line
	local targets = {}
	for _, p in TownPoints.Points do
		table.insert(targets, p.pos)
	end
	local stops: { TownStop } = {}
	for _, s in TownGraph.stopsFor(graph, targets, TownPoints.Reach) do
		local p = TownPoints.Points[s.index]
		-- a walking line can run right through a cart: wait a few studs off it, on the line's side of the cart
		local away = Vector3.new(s.point.X - p.pos.X, 0, s.point.Z - p.pos.Z)
		local stand = s.point
		if away.Magnitude < TownPoints.CustomerClearance then
			local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
			stand = Vector3.new(p.pos.X, s.point.Y, p.pos.Z) + dir * TownPoints.CustomerClearance
		end
		table.insert(stops, { id = p.id, point = s.point, stand = stand, target = p.pos, kind = p.kind, dwell = p.dwell, vendorPos = p.vendorPos })
	end
	local bubblesOn = not reducedCount() -- phones / Reduce effects: no bubbles, the walkers still stop
	folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = workspace

	local count = if reducedCount() then Townsfolk.CountReduced else Townsfolk.Count
	local now = workspace:GetServerTimeNow()
	for i = 1, count do
		local look, speed, side, legs, cycle, offset = planWalker(i, routes, #templates, graph, stops)
		local model, rootOffset = makeBody(templates[look])
		if model and cycle > 0 then
			model.Name = "Townsperson" .. i
			local walker: Walker = {
				model = model,
				legs = legs,
				cycle = cycle,
				offset = offset,
				speed = speed,
				side = side,
				rootOffset = rootOffset,
				walkTrack = nil,
				idleTrack = nil,
				animating = false,
				bubble = nil,
				lastUpdate = 0,
				shown = true,
			}
			place(walker, now)
			model.Parent = folder
			startAnimations(walker)
			table.insert(walkers, walker)
		end
	end
	bubblesEnabled = bubblesOn

	-- WP6: one vendor per cart that has a stop (the vendor stands on the far side from where customers stop, facing them).
	-- Same on every client: look, spot and phase come from the cart's position in the list, not from chance.
	for _, s in stops do
		if s.kind == "vendor" and vendorsById[s.id] == nil then
			local toCart = Vector3.new(s.target.X - s.stand.X, 0, s.target.Z - s.stand.Z)
			local model, rootOffset = makeBody(templates[(#vendors) % #templates + 1])
			if model and toCart.Magnitude > 0.1 then
				local spot = s.vendorPos or (s.target + toCart.Unit * TownPoints.VendorStandOff)
				local at = Vector3.new(spot.X, s.target.Y + rootOffset, spot.Z)
				model.Name = "Vendor_" .. s.id
				model:PivotTo(CFrame.lookAt(at, Vector3.new(s.stand.X, at.Y, s.stand.Z)))
				local walker: Walker = {
					model = model, legs = {}, cycle = 1, offset = 0, speed = 0, side = 0, rootOffset = rootOffset,
					walkTrack = nil, idleTrack = nil, animating = false, bubble = nil, lastUpdate = 0, shown = false,
				}
				startAnimations(walker)
				local vendor: Vendor = {
					id = s.id, walker = walker, pos = spot, phase = (#vendors + 1) * 5.3, servedAt = -100,
				}
				table.insert(vendors, vendor)
				vendorsById[s.id] = vendor
			end
		end
	end
	log(`{#walkers} townsfolk on {#routes} routes, graph of {#graph.nodes} corners, {#stops} stops, {#vendors} vendors ({#templates} looks), shared clock`)
end

local function update()
	local camera = workspace.CurrentCamera
	if camera == nil or folder == nil then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	local t = workspace:GetServerTimeNow()
	local near2 = Townsfolk.AnimateWithin ^ 2
	local hide2 = Townsfolk.HideBeyond ^ 2
	local marketOpen = Hours.marketOpen() -- vendors set up in the morning and pack up at night
	for _, walker in walkers do
		-- distance from where the walker IS now (cheap: no need to move a hidden model to know where it is)
		local ground = positionAt(walker, t)
		local d2 = (ground.X - eye.X) ^ 2 + (ground.Z - eye.Z) ^ 2
		if d2 > hide2 then
			if walker.shown then
				walker.shown = false
				setAnimating(walker, false, false)
				setBubble(walker, nil)
				walker.model.Parent = nil
			end
		else
			if not walker.shown then
				walker.shown = true
				walker.model.Parent = folder
				walker.lastUpdate = 0 -- place it right away
			end
			if d2 <= near2 then
				local paused, say, stopId = place(walker, t)
				walker.lastUpdate = now
				local vendor = if stopId then vendorsById[stopId] else nil
				if vendor then
					if marketOpen then
						vendor.servedAt = now -- a customer is at the cart: the vendor serves
					else
						say = nil -- a closed cart: the walker just waits quietly
					end
				end
				setAnimating(walker, true, paused)
				setBubble(walker, if bubblesEnabled and say and d2 <= BUBBLE_RANGE ^ 2 then say else nil)
			elseif now - walker.lastUpdate >= FAR_UPDATE then
				place(walker, t)
				walker.lastUpdate = now
				if walker.animating then
					setAnimating(walker, false, false)
					setBubble(walker, nil)
				end
			end
		end
	end

	-- WP6: cart vendors. Present during market hours, idle when close, call out every VendorCallEvery seconds, serve walkers.
	local calls, serves = TownPoints.Lines.vendorCall, TownPoints.Lines.vendorServe
	for _, vendor in vendors do
		local w = vendor.walker
		local d2 = (vendor.pos.X - eye.X) ^ 2 + (vendor.pos.Z - eye.Z) ^ 2
		local visible = marketOpen and d2 <= hide2
		if visible ~= w.shown then
			w.shown = visible
			w.model.Parent = if visible then folder else nil
			if not visible then
				setAnimating(w, false, true)
				setBubble(w, nil)
			end
		end
		if visible then
			local near = d2 <= near2
			if near ~= w.animating then
				setAnimating(w, near, true) -- a vendor only ever idles
			end
			local text = nil
			if bubblesEnabled and d2 <= BUBBLE_RANGE ^ 2 then
				if now - vendor.servedAt < TownPoints.VendorServeFor then
					text = serves[math.floor(vendor.servedAt) % #serves + 1]
				else
					local cycle = (t + vendor.phase) / TownPoints.VendorCallEvery
					if (cycle % 1) * TownPoints.VendorCallEvery < TownPoints.VendorCallFor then
						text = calls[math.floor(cycle) % #calls + 1]
					end
				end
			end
			setBubble(w, text)
		end
	end
end

function TownsfolkController.Init(_others) end

function TownsfolkController.Start()
	task.spawn(function()
		spawnWalkers()
		if #walkers > 0 then
			RunService.Heartbeat:Connect(update)
		end
	end)
end

return TownsfolkController
