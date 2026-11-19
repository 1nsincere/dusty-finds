-- TricycleService.luau
-- Purpose: drives the ambient tricycles on their routes (TODA stand -> "West" loop through the strip, or -> "Pantalan"
-- by the entrance square), stops them at each stop with a small horn, and seats players who use the "Sakay" prompt.
-- Owner: Dev 1 (Ace). Server only, no remotes.
-- Depends on: Lib/TrafficRules, Workspace.TownT2.Transit.TrikeRoutes.<Route> (WP_### parts; StopSeconds/StopName on stops),
-- Workspace.TownT2.Transit.Tricycles.TricycleN (attribute Route; PrimaryPart Root at ground level facing forward,
-- Seats folder, BoardingPoint.SakayPrompt on the sidecar, Root.Horn).
-- Same approach as JeepneyService: anchored PivotTo on Heartbeat, server is the timer, shared TrafficRules so tricycles
-- and jeepneys stop for each other and for players. Tricycles follow slopes (the strip ramp), jeepneys stay flat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TrafficRules = require(script.Parent.Parent.Lib.TrafficRules)

local TricycleService = {}
local DEBUG = true

local MAX_SPEED = 10 -- studs per second on the straights
local MIN_CURVE_SPEED = 4 -- slowest in the tightest turns
local ACCEL = 5
local LOOK = 3 -- shorter than the jeep: a tricycle turns tighter
local HALF_LENGTH = 5
local HALF_WIDTH = 2.5
local BLOCK_AHEAD = 3
local FOLLOW_GAP = 18 -- path distance to the tricycle ahead on the same route
local VEHICLE_GAP = 3 -- space kept behind a vehicle from another route (the TODA queue forms from this)
local ROOT_HEIGHT = 0.1 -- Root sits on the road
local PROMPT_COOLDOWN = 1

local function log(...)
	if DEBUG then
		print("[TricycleService]", ...)
	end
end

local trikes = {}
local lastPrompt: { [Player]: number } = {}

local function place(trike)
	local path = trike.path
	local pos = TrafficRules.sample(path, trike.s)
	local dir = TrafficRules.sample(path, trike.s + LOOK) - TrafficRules.sample(path, trike.s - LOOK)
	if Vector3.new(dir.X, 0, dir.Z).Magnitude < 1e-3 then
		dir = TrafficRules.heading(path, trike.s, LOOK)
	end
	local p = pos + Vector3.new(0, ROOT_HEIGHT, 0)
	trike.model:PivotTo(CFrame.lookAt(p, p + dir.Unit))
end

local function checkRiders(trike)
	for _, seat in trike.model.Seats:GetChildren() do
		local humanoid = seat:IsA("Seat") and seat.Occupant
		if humanoid and (humanoid.Jump or not humanoid.Sit or humanoid.Health <= 0) then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then weld:Destroy() end
		end
	end
end

-- Off on the sidecar (kerb) side: the tricycle's right.
local function dropOff(trike, humanoid: Humanoid)
	local character = humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- the kerb spot is fixed at the moment the rider leaves; it is applied a moment later because the rider's own client
	-- moves the character out of the seat in the same frame and would overwrite an instant teleport
	local cf = trike.model:GetPivot()
	local spot = cf.Position + cf.RightVector * 5 - cf.LookVector * 1
	local at = Vector3.new(spot.X, cf.Position.Y + 3.2, spot.Z)
	local facing = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	task.delay(0.15, function()
		if character.Parent and humanoid.SeatPart == nil then
			character:PivotTo(CFrame.lookAt(at, at + facing))
		end
	end)
	log(character.Name, "got off", trike.model.Name)
end

local function step(dt: number)
	local now = os.clock()
	for _, trike in trikes do
		checkRiders(trike)
		if trike.waitUntil and now < trike.waitUntil then
			continue
		end
		trike.waitUntil = nil
		local path = trike.path
		local target = TrafficRules.curveSpeed(path, trike.s, MAX_SPEED, MIN_CURVE_SPEED, LOOK, 6)
		local stop = path.stops[trike.nextStop]
		if stop then
			target = math.min(target, math.max(1.5, TrafficRules.ahead(path, trike.s, stop.s) * 1.1))
		end
		if TrafficRules.pathGapBlocking(trike, FOLLOW_GAP) or TrafficRules.playerBlocking(trike)
			or TrafficRules.vehicleBlocking(trike, VEHICLE_GAP) or TrafficRules.giveWayBlocking(trike) then
			target = 0
		end
		if trike.speed < target then trike.speed = math.min(target, trike.speed + ACCEL * dt)
		else trike.speed = math.max(target, trike.speed - ACCEL * 2 * dt) end
		local move = trike.speed * dt
		if stop and move >= TrafficRules.ahead(path, trike.s, stop.s) then
			trike.s = TrafficRules.wrap(path, stop.s + 0.01)
			trike.speed = 0
			trike.waitUntil = now + stop.seconds
			trike.nextStop = trike.nextStop % #path.stops + 1
			local horn = trike.model.PrimaryPart:FindFirstChild("Horn")
			if horn then horn:Play() end
			log(trike.model.Name, "stopped at", stop.name or "stop", "for", stop.seconds, "s")
		else
			trike.s = TrafficRules.wrap(path, trike.s + move)
		end
		place(trike)
	end
end

local function onSakay(player: Player, trike)
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < PROMPT_COOLDOWN then return end
	lastPrompt[player] = now
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then return end
	for _, seat in trike.model.Seats:GetChildren() do
		if seat:IsA("Seat") and seat.Occupant == nil then
			seat:Sit(humanoid)
			log(player.Name, "rides", trike.model.Name, seat.Name)
			return
		end
	end
	log(player.Name, "found", trike.model.Name, "full")
end

-- Where the n-th of `count` tricycles on a route starts. #1 of the first route waits at the TODA stop; the others are
-- spread over their loop, and the second route is offset a quarter lap so the two routes don't start on top of each other.
local function startS(path: TrafficRules.Path, n: number, count: number, routeIndex: number): number
	local base = path.stops[1] and path.stops[1].s or 0
	local offset = if routeIndex == 1 then 0 else path.length * 0.25
	return TrafficRules.wrap(path, base + offset + (n - 1) * path.length / count)
end

function TricycleService.Init(_services)
	-- nothing to wire: no other service depends on the tricycles
end

function TricycleService.Start()
	local transit = workspace:FindFirstChild("TownT2") and workspace.TownT2:FindFirstChild("Transit")
	local routesFolder = transit and transit:FindFirstChild("TrikeRoutes")
	local trikeFolder = transit and transit:FindFirstChild("Tricycles")
	if not routesFolder or not trikeFolder then
		warn("[TricycleService] Workspace.TownT2.Transit.TrikeRoutes / Tricycles missing: no tricycles")
		return
	end
	local paths, order = {}, {}
	for _, folder in routesFolder:GetChildren() do
		local path = TrafficRules.newPath(folder)
		if path then
			paths[folder.Name] = path
			table.insert(order, folder.Name)
		else
			warn("[TricycleService] route", folder.Name, "has too few waypoints")
		end
	end
	table.sort(order)
	local byRoute: { [string]: { Model } } = {}
	for _, model in trikeFolder:GetChildren() do
		local route = model:GetAttribute("Route")
		if model:IsA("Model") and model.PrimaryPart and type(route) == "string" and paths[route] then
			byRoute[route] = byRoute[route] or {}
			table.insert(byRoute[route], model)
		end
	end
	for routeIndex, route in order do
		local models = byRoute[route] or {}
		table.sort(models, function(a, b) return a.Name < b.Name end)
		local path = paths[route]
		for n, model in models do
			local trike = TrafficRules.register({
				model = model, path = path, s = startS(path, n, #models, routeIndex), speed = 0, accel = ACCEL,
				halfLength = HALF_LENGTH, halfWidth = HALF_WIDTH, blockAhead = BLOCK_AHEAD, nextStop = 1,
			})
			if routeIndex == 1 and n == 1 and path.stops[1] then
				-- parked at the TODA stop: wait it out, the next stop is the one after it
				trike.s = TrafficRules.wrap(path, path.stops[1].s + 0.01)
				trike.waitUntil = os.clock() + path.stops[1].seconds
				trike.nextStop = 1 % #path.stops + 1
			else
				local best, bestK = math.huge, 1
				for k, st in path.stops do
					local d = TrafficRules.ahead(path, trike.s, st.s)
					if d > 0.01 and d < best then best, bestK = d, k end
				end
				trike.nextStop = bestK
			end
			table.insert(trikes, trike)
			place(trike)
			local prompt = model:FindFirstChild("SakayPrompt", true)
			if prompt then
				prompt.Triggered:Connect(function(player) onSakay(player, trike) end)
			end
			for _, seat in model.Seats:GetChildren() do
				if seat:IsA("Seat") then
					seat.CanTouch = false -- a moving tricycle must not scoop up people on the road; Sit() still works
					local current: Humanoid? = nil
					seat:GetPropertyChangedSignal("Occupant"):Connect(function()
						local previous = current
						current = seat.Occupant
						if previous and current == nil then dropOff(trike, previous) end
					end)
				end
			end
		end
		log(string.format("route %s: %d tricycles, %.0f-stud loop, %d waypoints, %d stops", route, #models, path.length, #path.points, #path.stops))
	end
	Players.PlayerRemoving:Connect(function(player) lastPrompt[player] = nil end)
	RunService.Heartbeat:Connect(step)
end

return TricycleService
