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
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local TownsfolkController = {}
local DEBUG = true

local IDLE_FALLBACK = "rbxassetid://507766388" -- Roblox default R15 idle
local WALK_FALLBACK = "rbxassetid://913402848" -- Roblox default R15 walk
local WALK_ANIM_SPEED = 16 -- the default walk animation matches WalkSpeed 16
local FAR_UPDATE = 0.3 -- seconds between position updates for walkers outside AnimateWithin
local SEED_BASE = 20261124 -- change this (on purpose) to reshuffle everyone; must be the same on every client

-- One stretch of a walker's day: walk from `from` to `to` in `walk` seconds, then stand still for `pause` seconds.
type Leg = { from: Vector3, to: Vector3, walk: number, pause: number }

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
	lastUpdate: number,
	shown: boolean,
}

local walkers: { Walker } = {}
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
local function planWalker(i: number, routes: { { Vector3 } }, templateCount: number)
	local rng = Random.new(SEED_BASE + i * 7919)
	local route = routes[(i - 1) % #routes + 1] -- spread evenly: every route gets someone before any gets two
	local look = rng:NextInteger(1, templateCount)
	local speed = rng:NextNumber(Townsfolk.WalkSpeed[1], Townsfolk.WalkSpeed[2])
	local side = rng:NextNumber(-1.2, 1.2)
	local legs: { Leg } = {}
	local cycle = 0
	local function addLeg(a: Vector3, b: Vector3)
		local walk = (b - a).Magnitude / speed
		local pause = if rng:NextNumber() < Townsfolk.PauseChance then rng:NextNumber(Townsfolk.PauseSeconds[1], Townsfolk.PauseSeconds[2]) else 0
		table.insert(legs, { from = a, to = b, walk = walk, pause = pause })
		cycle += walk + pause
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
local function positionAt(walker: Walker, t: number): (Vector3, Vector3, boolean)
	local tt = (t + walker.offset) % walker.cycle
	for _, leg in walker.legs do
		local dir = leg.to - leg.from
		if tt < leg.walk then
			return leg.from + dir * (tt / leg.walk), dir, false
		end
		tt -= leg.walk
		if tt < leg.pause then
			return leg.to, dir, true
		end
		tt -= leg.pause
	end
	local last = walker.legs[#walker.legs]
	return last.to, last.to - last.from, true
end

local function place(walker: Walker, t: number): boolean
	local ground, dir, paused = positionAt(walker, t)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return paused
	end
	local unit = flat.Unit
	local p = ground + unit:Cross(Vector3.yAxis) * walker.side
	local at = Vector3.new(p.X, p.Y + walker.rootOffset, p.Z)
	walker.model:PivotTo(CFrame.lookAt(at, at + unit))
	return paused
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
	folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = workspace

	local count = if reducedCount() then Townsfolk.CountReduced else Townsfolk.Count
	local now = workspace:GetServerTimeNow()
	for i = 1, count do
		local look, speed, side, legs, cycle, offset = planWalker(i, routes, #templates)
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
				lastUpdate = 0,
				shown = true,
			}
			place(walker, now)
			model.Parent = folder
			startAnimations(walker)
			table.insert(walkers, walker)
		end
	end
	log(`{#walkers} townsfolk on {#routes} routes ({#templates} looks), shared clock`)
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
	for _, walker in walkers do
		-- distance from where the walker IS now (cheap: no need to move a hidden model to know where it is)
		local ground = positionAt(walker, t)
		local d2 = (ground.X - eye.X) ^ 2 + (ground.Z - eye.Z) ^ 2
		if d2 > hide2 then
			if walker.shown then
				walker.shown = false
				setAnimating(walker, false, false)
				walker.model.Parent = nil
			end
		else
			if not walker.shown then
				walker.shown = true
				walker.model.Parent = folder
				walker.lastUpdate = 0 -- place it right away
			end
			if d2 <= near2 then
				local paused = place(walker, t)
				walker.lastUpdate = now
				setAnimating(walker, true, paused)
			elseif now - walker.lastUpdate >= FAR_UPDATE then
				place(walker, t)
				walker.lastUpdate = now
				if walker.animating then
					setAnimating(walker, false, false)
				end
			end
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
