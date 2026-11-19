-- JeepneyService.luau
-- Purpose: drives the ambient jeepneys around the entrance-level loop (south road, roundabout, east turnaround),
-- stops them at the terminal bay with a horn, and seats players who use the "Sakay" prompt.
-- Owner: Dev 1 (Ace). Server only, no remotes.
-- Depends on: Workspace.TownT2.Transit.Waypoints (JeepPath_### parts, one with attribute StopSeconds) and
-- Workspace.TownT2.Transit.Jeepneys.JeepneyN (PrimaryPart Root facing forward, Seats folder, BoardingPoint.SakayPrompt, Root.Horn).
-- Why anchored + PivotTo instead of physics: no VehicleSeat, no network ownership fights, and the server stays the timer.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local JeepneyService = {}
local DEBUG = true

local MAX_SPEED = 14 -- studs per second on the straights
local MIN_CURVE_SPEED = 6 -- slowest speed in the tightest curve
local ACCEL = 6 -- studs/s^2, speeding up and slowing down
local LOOK = 5 -- studs behind/ahead used to aim the jeep (smooth turns)
local HALF_LENGTH = 10.6 -- front bumper distance from the jeep centre
local BLOCK_AHEAD = 4 -- stop if a standing player is this close in front of the bumper
local BLOCK_HALF_WIDTH = 4.6
local FOLLOW_GAP = 34 -- never drive closer than this to the jeep ahead (path distance)
local PROMPT_COOLDOWN = 1

local function log(...)
	if DEBUG then
		print("[JeepneyService]", ...)
	end
end

local points: { Vector3 } = {}
local cumulative: { number } = {} -- cumulative[i] = path distance at points[i]
local loopLength = 0
local stops: { { s: number, seconds: number } } = {}
local jeeps = {}
local lastPrompt: { [Player]: number } = {}

local function wrap(s: number): number
	return s % loopLength
end

-- Position on the loop at path distance s (linear between waypoints).
local function sample(s: number): Vector3
	s = wrap(s)
	local lo, hi = 1, #points
	while lo < hi do -- last index with cumulative <= s
		local mid = (lo + hi + 1) // 2
		if cumulative[mid] <= s then lo = mid else hi = mid - 1 end
	end
	local a = points[lo]
	local b = points[lo % #points + 1]
	local segStart = cumulative[lo]
	local segLen = (lo == #points) and (loopLength - segStart) or (cumulative[lo + 1] - segStart)
	local t = segLen > 0 and (s - segStart) / segLen or 0
	return a:Lerp(b, t)
end

local function heading(s: number): Vector3
	local d = sample(s + LOOK) - sample(s - LOOK)
	d = Vector3.new(d.X, 0, d.Z)
	return d.Magnitude > 1e-3 and d.Unit or Vector3.new(1, 0, 0)
end

-- Slower in curves: compare the heading now with the heading a little further on.
local function curveSpeed(s: number): number
	local h1, h2 = heading(s), heading(s + 10)
	local angle = math.deg(math.acos(math.clamp(h1:Dot(h2), -1, 1)))
	local f = math.clamp(1 - angle / 50, 0, 1)
	return MIN_CURVE_SPEED + (MAX_SPEED - MIN_CURVE_SPEED) * f
end

local function ahead(fromS: number, toS: number): number
	return wrap(toS - fromS)
end

local function playerBlocking(jeep): boolean
	local cf = jeep.model:GetPivot()
	local front = cf.Position + cf.LookVector * HALF_LENGTH
	-- look further ahead the faster we go, so the jeep comes to rest about BLOCK_AHEAD short of the player
	local reach = BLOCK_AHEAD + (jeep.speed * jeep.speed) / (2 * ACCEL * 2) + 1
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.SeatPart == nil then
			local rel = root.Position - front
			local along = rel:Dot(cf.LookVector)
			local lateral = (Vector3.new(rel.X, 0, rel.Z) - cf.LookVector * along).Magnitude
			if along > -1 and along < reach and lateral < BLOCK_HALF_WIDTH and math.abs(rel.Y) < 8 then
				return true
			end
		end
	end
	return false
end

local function place(jeep)
	local pos = sample(jeep.s)
	local dir = heading(jeep.s)
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
		local target = curveSpeed(jeep.s)
		-- ease into the next stop
		local stop = stops[jeep.nextStop]
		if stop then
			local toStop = ahead(jeep.s, stop.s)
			target = math.min(target, math.max(2, toStop * 1.1))
		end
		-- keep a gap to the jeep ahead
		for _, other in jeeps do
			if other ~= jeep then
				local gap = ahead(jeep.s, other.s)
				if gap < FOLLOW_GAP then target = 0 end
			end
		end
		if playerBlocking(jeep) then
			target = 0
		end
		-- smooth speed change
		if jeep.speed < target then jeep.speed = math.min(target, jeep.speed + ACCEL * dt)
		else jeep.speed = math.max(target, jeep.speed - ACCEL * 2 * dt) end
		local move = jeep.speed * dt
		if stop and move >= ahead(jeep.s, stop.s) then
			-- arrive at the stop: snap, honk, wait
			jeep.s = wrap(stop.s + 0.01) -- just past the stop, so it is not "arrived" again when it pulls away
			jeep.speed = 0
			jeep.waitUntil = now + stop.seconds
			jeep.nextStop = jeep.nextStop % #stops + 1
			local horn = jeep.model.PrimaryPart:FindFirstChild("Horn")
			if horn then horn:Play() end
			log(jeep.model.Name, "stopped at the bay for", stop.seconds, "s")
		else
			jeep.s = wrap(jeep.s + move)
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
	local list = wpFolder:GetChildren()
	table.sort(list, function(a, b) return a.Name < b.Name end)
	for i, w in list do
		points[i] = w.Position
		cumulative[i] = loopLength
		local nxt = list[i % #list + 1]
		if w:GetAttribute("StopSeconds") then table.insert(stops, { s = loopLength, seconds = w:GetAttribute("StopSeconds") }) end
		loopLength += (Vector3.new(nxt.Position.X, 0, nxt.Position.Z) - Vector3.new(w.Position.X, 0, w.Position.Z)).Magnitude
	end
	if #points < 3 or loopLength <= 0 then
		warn("[JeepneyService] not enough waypoints")
		return
	end
	local models = jeepFolder:GetChildren()
	table.sort(models, function(a, b) return (a:GetAttribute("Jeepney") or 0) < (b:GetAttribute("Jeepney") or 0) end)
	local startS = stops[1] and stops[1].s or 0
	for i, model in models do
		if model:IsA("Model") and model.PrimaryPart then
			local jeep = {
				model = model,
				s = wrap(startS + (i - 1) * loopLength / #models), -- spaced evenly around the loop
				speed = 0,
				y = model.PrimaryPart.Position.Y,
				nextStop = 1,
			}
			if i == 1 and stops[1] then
				-- jeepney #1 starts parked at the bay: wait out the stop, then the next stop is one lap on
				jeep.s = wrap(startS + 0.01)
				jeep.waitUntil = os.clock() + stops[1].seconds
				jeep.nextStop = 1 % #stops + 1
			else
				-- the nearest stop ahead of this jeep
				local best, bestK = math.huge, 1
				for k, st in stops do local d = ahead(jeep.s, st.s); if d > 0.01 and d < best then best, bestK = d, k end end
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
	log(string.format("Start: %d jeepneys on a %.0f-stud loop, %d waypoints, %d stop(s)", #jeeps, loopLength, #points, #stops))
end

return JeepneyService
