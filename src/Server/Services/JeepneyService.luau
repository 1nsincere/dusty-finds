-- JeepneyService.luau
-- Purpose: drives the ambient jeepneys around the entrance-level loop (south road, roundabout, east turnaround),
-- stops them at the terminal bay with a horn, and seats players who use the "Sakay" prompt.
-- Owner: Dev 1 (Ace). Server only, no remotes.
-- Depends on: Lib/TrafficRules (paths + shared traffic rules), Workspace.TownT2.Transit.Waypoints (JeepPath_### parts, one with
-- attribute StopSeconds) and Workspace.TownT2.Transit.Jeepneys.JeepneyN (PrimaryPart Root facing forward, Seats folder,
-- BoardingPoint.SakayPrompt, Root.Horn).
-- Why anchored + PivotTo instead of physics: no VehicleSeat, no network ownership fights, and the server stays the timer.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TrafficRules = require(script.Parent.Parent.Lib.TrafficRules)

local JeepneyService = {}
local DEBUG = true

local MAX_SPEED = 14 -- studs per second on the straights
local MIN_CURVE_SPEED = 6 -- slowest speed in the tightest curve
local ACCEL = 6 -- studs/s^2, speeding up and slowing down
local LOOK = 5 -- studs behind/ahead used to aim the jeep (smooth turns)
local HALF_LENGTH = 10.6 -- front bumper distance from the jeep centre
local HALF_WIDTH = 4.25 -- with TrafficRules' 0.35 margin this is the old 4.6 player-blocking half width
local BLOCK_AHEAD = 4 -- stop if a standing player is this close in front of the bumper
local FOLLOW_GAP = 34 -- never drive closer than this to the jeep ahead (path distance)
local VEHICLE_GAP = 4 -- extra space kept behind a vehicle from another route (a tricycle) in the same lane
local PROMPT_COOLDOWN = 1

local function log(...)
	if DEBUG then
		print("[JeepneyService]", ...)
	end
end

local path: TrafficRules.Path
local jeeps = {}
local lastPrompt: { [Player]: number } = {}

local function place(jeep)
	local pos = TrafficRules.sample(path, jeep.s)
	local dir = TrafficRules.heading(path, jeep.s, LOOK)
	local p = Vector3.new(pos.X, jeep.y, pos.Z)
	jeep.model:PivotTo(CFrame.lookAt(p, p + dir))
end

-- Riders: a jump (replicated from the rider's client) or a lost sit releases the seat on the server too,
-- so a rider who got off is never still counted as seated (and the seat frees up for the next passenger).
local function checkRiders(jeep)
	for _, seat in jeep.model.Seats:GetChildren() do
		local humanoid = seat:IsA("Seat") and seat.Occupant
		if humanoid and (humanoid.Jump or not humanoid.Sit or humanoid.Health <= 0) then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then weld:Destroy() end
		end
	end
end

-- Put a rider who just got off on the kerb side (the jeep's right), not inside the cabin or under the next jeep.
local function dropOff(jeep, humanoid: Humanoid)
	local character = humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cf = jeep.model:GetPivot()
	local spot = cf.Position + cf.RightVector * 7 - cf.LookVector * 2
	character:PivotTo(CFrame.lookAt(Vector3.new(spot.X, jeep.y + 3.5, spot.Z), Vector3.new(spot.X, jeep.y + 3.5, spot.Z) + cf.LookVector))
	log(character.Name, "got off", jeep.model.Name)
end

local function step(dt: number)
	local now = os.clock()
	for _, jeep in jeeps do
		checkRiders(jeep)
		if jeep.waitUntil and now < jeep.waitUntil then
			continue
		end
		jeep.waitUntil = nil
		local target = TrafficRules.curveSpeed(path, jeep.s, MAX_SPEED, MIN_CURVE_SPEED, LOOK)
		-- ease into the next stop
		local stop = path.stops[jeep.nextStop]
		if stop then
			local toStop = TrafficRules.ahead(path, jeep.s, stop.s)
			target = math.min(target, math.max(2, toStop * 1.1))
		end
		-- keep a gap to the jeep ahead, stop for players and for vehicles of other routes in my lane
		if TrafficRules.pathGapBlocking(jeep, FOLLOW_GAP) or TrafficRules.playerBlocking(jeep)
			or TrafficRules.vehicleBlocking(jeep, VEHICLE_GAP) then
			target = 0
		end
		-- smooth speed change
		if jeep.speed < target then jeep.speed = math.min(target, jeep.speed + ACCEL * dt)
		else jeep.speed = math.max(target, jeep.speed - ACCEL * 2 * dt) end
		local move = jeep.speed * dt
		if stop and move >= TrafficRules.ahead(path, jeep.s, stop.s) then
			-- arrive at the stop: snap, honk, wait
			jeep.s = TrafficRules.wrap(path, stop.s + 0.01) -- just past the stop, so it is not "arrived" again when it pulls away
			jeep.speed = 0
			jeep.waitUntil = now + stop.seconds
			jeep.nextStop = jeep.nextStop % #path.stops + 1
			local horn = jeep.model.PrimaryPart:FindFirstChild("Horn")
			if horn then horn:Play() end
			log(jeep.model.Name, "stopped at the bay for", stop.seconds, "s")
		else
			jeep.s = TrafficRules.wrap(path, jeep.s + move)
		end
		place(jeep)
	end
end

local function onSakay(player: Player, jeep)
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < PROMPT_COOLDOWN then return end
	lastPrompt[player] = now
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart then return end
	for _, seat in jeep.model.Seats:GetChildren() do
		if seat:IsA("Seat") and seat.Occupant == nil then
			seat:Sit(humanoid)
			log(player.Name, "rides", jeep.model.Name, seat.Name)
			return
		end
	end
	log(player.Name, "found", jeep.model.Name, "full")
end

function JeepneyService.Init(_services)
	-- nothing to wire: no other service depends on the jeepneys
end

function JeepneyService.Start()
	local transit = workspace:FindFirstChild("TownT2") and workspace.TownT2:FindFirstChild("Transit")
	local wpFolder = transit and transit:FindFirstChild("Waypoints")
	local jeepFolder = transit and transit:FindFirstChild("Jeepneys")
	if not wpFolder or not jeepFolder then
		warn("[JeepneyService] Workspace.TownT2.Transit.Waypoints / Jeepneys missing: no jeepneys")
		return
	end
	local built = TrafficRules.newPath(wpFolder)
	if not built then
		warn("[JeepneyService] not enough waypoints")
		return
	end
	path = built
	local models = jeepFolder:GetChildren()
	table.sort(models, function(a, b) return (a:GetAttribute("Jeepney") or 0) < (b:GetAttribute("Jeepney") or 0) end)
	local startS = path.stops[1] and path.stops[1].s or 0
	for i, model in models do
		if model:IsA("Model") and model.PrimaryPart then
			local jeep = TrafficRules.register({
				model = model,
				path = path,
				s = TrafficRules.wrap(path, startS + (i - 1) * path.length / #models), -- spaced evenly around the loop
				speed = 0,
				accel = ACCEL,
				halfLength = HALF_LENGTH,
				halfWidth = HALF_WIDTH,
				blockAhead = BLOCK_AHEAD,
				y = model.PrimaryPart.Position.Y,
				nextStop = 1,
			})
			if i == 1 and path.stops[1] then
				-- jeepney #1 starts parked at the bay: wait out the stop, then the next stop is one lap on
				jeep.s = TrafficRules.wrap(path, startS + 0.01)
				jeep.waitUntil = os.clock() + path.stops[1].seconds
				jeep.nextStop = 1 % #path.stops + 1
			else
				-- the nearest stop ahead of this jeep
				local best, bestK = math.huge, 1
				for k, st in path.stops do
					local d = TrafficRules.ahead(path, jeep.s, st.s)
					if d > 0.01 and d < best then best, bestK = d, k end
				end
				jeep.nextStop = bestK
			end
			table.insert(jeeps, jeep)
			place(jeep)
			local prompt = model:FindFirstChild("SakayPrompt", true)
			if prompt then
				prompt.Triggered:Connect(function(player) onSakay(player, jeep) end)
			end
			for _, seat in model.Seats:GetChildren() do
				if seat:IsA("Seat") then
					-- no touch-to-sit: otherwise a moving jeep scoops up anyone standing on the road. Sit() still works.
					seat.CanTouch = false
					local current: Humanoid? = nil
					seat:GetPropertyChangedSignal("Occupant"):Connect(function()
						local previous = current
						current = seat.Occupant
						if previous and current == nil then dropOff(jeep, previous) end
					end)
				end
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player) lastPrompt[player] = nil end)
	RunService.Heartbeat:Connect(step)
	log(string.format("Start: %d jeepneys on a %.0f-stud loop, %d waypoints, %d stop(s)", #jeeps, path.length, #path.points, #path.stops))
end

return JeepneyService
