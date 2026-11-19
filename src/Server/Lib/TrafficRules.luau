-- TrafficRules.luau (ServerScriptService.Server.Lib.TrafficRules)
-- Purpose: the shared driving rules for every ambient vehicle (jeepneys, tricycles): waypoint paths with arc-length
-- sampling and curve speed, "stop for a player in front", "keep a gap to the vehicle ahead on my route", and
-- "stop for any vehicle ahead in my lane from another route" (detection grows with speed; never pass).
-- Owner: Dev 1 (Ace). Depends on: nothing (pure helpers + a registry). Used by JeepneyService and TricycleService.
-- Why one module: the jeepney and tricycle share roads near the roundabout; one rule set means they treat each other
-- the same way and nobody drives through anybody.

local Players = game:GetService("Players")

local TrafficRules = {}

-- ===== Paths =====
export type Stop = { s: number, seconds: number, name: string? }
export type GiveWay = { s: number, pos: Vector3, radius: number }
export type Path = {
	name: string,
	points: { Vector3 },
	cumulative: { number },
	length: number,
	stops: { Stop },
	giveWays: { GiveWay },
}

-- Build a closed loop from a folder of waypoint parts sorted by name. A part with a number attribute StopSeconds is a stop;
-- one with a number attribute GiveWay is a give-way line (merges/crossings): wait there while another route's vehicle is
-- within that radius of it and coming toward it.
function TrafficRules.newPath(folder: Instance): Path?
	local list = folder:GetChildren()
	table.sort(list, function(a, b) return a.Name < b.Name end)
	local path: Path = { name = folder.Name, points = {}, cumulative = {}, length = 0, stops = {}, giveWays = {} }
	for i, w in list do
		if w:IsA("BasePart") then
			local nxt = list[i % #list + 1] :: BasePart
			table.insert(path.points, w.Position)
			table.insert(path.cumulative, path.length)
			local seconds = w:GetAttribute("StopSeconds")
			if type(seconds) == "number" then
				table.insert(path.stops, { s = path.length, seconds = seconds, name = w:GetAttribute("StopName") })
			end
			local giveWay = w:GetAttribute("GiveWay")
			if type(giveWay) == "number" and giveWay > 0 then
				table.insert(path.giveWays, { s = path.length, pos = w.Position, radius = giveWay })
			end
			-- distance along the ground (flat), so ramps don't make stops/spacing drift
			path.length += (Vector3.new(nxt.Position.X, 0, nxt.Position.Z) - Vector3.new(w.Position.X, 0, w.Position.Z)).Magnitude
		end
	end
	if #path.points < 3 or path.length <= 0 then
		return nil
	end
	return path
end

function TrafficRules.wrap(path: Path, s: number): number
	return s % path.length
end

-- Path distance from `fromS` forward to `toS` (0 .. length).
function TrafficRules.ahead(path: Path, fromS: number, toS: number): number
	return (toS - fromS) % path.length
end

-- Position at path distance s (linear between waypoints, Y included so ramps are followed).
function TrafficRules.sample(path: Path, s: number): Vector3
	s = s % path.length
	local points, cumulative = path.points, path.cumulative
	local lo, hi = 1, #points
	while lo < hi do -- last index with cumulative <= s
		local mid = (lo + hi + 1) // 2
		if cumulative[mid] <= s then lo = mid else hi = mid - 1 end
	end
	local a = points[lo]
	local b = points[lo % #points + 1]
	local segStart = cumulative[lo]
	local segLen = (lo == #points) and (path.length - segStart) or (cumulative[lo + 1] - segStart)
	local t = segLen > 0 and (s - segStart) / segLen or 0
	return a:Lerp(b, t)
end

-- Flat heading (unit, Y = 0) around s, averaged over +/- look studs so turns are smooth.
function TrafficRules.heading(path: Path, s: number, look: number): Vector3
	local d = TrafficRules.sample(path, s + look) - TrafficRules.sample(path, s - look)
	d = Vector3.new(d.X, 0, d.Z)
	return d.Magnitude > 1e-3 and d.Unit or Vector3.new(1, 0, 0)
end

-- Slower in curves: compare the heading now with the heading `lookAhead` studs on (a 50 degree change = minSpeed).
function TrafficRules.curveSpeed(path: Path, s: number, maxSpeed: number, minSpeed: number, look: number, lookAhead: number?): number
	local h1 = TrafficRules.heading(path, s, look)
	local h2 = TrafficRules.heading(path, s + (lookAhead or 10), look)
	local angle = math.deg(math.acos(math.clamp(h1:Dot(h2), -1, 1)))
	local f = math.clamp(1 - angle / 50, 0, 1)
	return minSpeed + (maxSpeed - minSpeed) * f
end

-- ===== Vehicles =====
-- A vehicle registers once: { id, model, path, s, speed, accel, halfLength, halfWidth, blockAhead }.
-- Every service updates s/speed itself; the registry only lets vehicles see each other.
export type Vehicle = {
	id: number,
	model: Model,
	path: Path,
	s: number,
	speed: number,
	accel: number,
	halfLength: number,
	halfWidth: number,
	blockAhead: number,
}

local registry: { Vehicle } = {}
local nextId = 0

function TrafficRules.register(vehicle: any): Vehicle
	nextId += 1
	vehicle.id = nextId
	table.insert(registry, vehicle)
	return vehicle
end

-- How far ahead of the front bumper a vehicle looks: its stopping distance plus a margin (grows with speed).
local function reachOf(v: Vehicle): number
	return v.blockAhead + (v.speed * v.speed) / (2 * v.accel * 2) + 1
end

-- True if a standing (not seated) player is in front of the vehicle within its stopping reach.
function TrafficRules.playerBlocking(v: Vehicle): boolean
	local cf = v.model:GetPivot()
	local front = cf.Position + cf.LookVector * v.halfLength
	local reach = reachOf(v)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.SeatPart == nil then
			local rel = root.Position - front
			local along = rel:Dot(cf.LookVector)
			local lateral = (Vector3.new(rel.X, 0, rel.Z) - cf.LookVector * along).Magnitude
			if along > -1 and along < reach and lateral < v.halfWidth + 0.35 and math.abs(rel.Y) < 8 then
				return true
			end
		end
	end
	return false
end

-- True if `other` sits inside v's lane box ahead (other's footprint overlaps v's width, within v's reach + gap).
local function sees(v: Vehicle, other: Vehicle, gap: number): boolean
	local cf = v.model:GetPivot()
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 1e-3 then return false end
	look = look.Unit
	local front = cf.Position + look * v.halfLength
	local rel = other.model:GetPivot().Position - front
	if math.abs(rel.Y) > 5 then return false end
	local along = rel:Dot(look)
	local lateral = (Vector3.new(rel.X, 0, rel.Z) - look * along).Magnitude
	-- from beside me (its front past my rear bumper) to my stopping reach ahead: covers following, merging and
	-- side-by-side; the lower-id rule in vehicleBlocking decides who goes when both see each other
	return along > -(2 * v.halfLength + other.halfLength) + 0.5 and along < reachOf(v) + gap + other.halfLength
		and lateral < v.halfWidth + other.halfWidth - 0.5
end

-- Same route: true if the vehicle ahead on my path is closer than minGap (path distance). Jeepneys rely on this.
function TrafficRules.pathGapBlocking(v: Vehicle, minGap: number): boolean
	for _, other in registry do
		if other ~= v and other.path == v.path and TrafficRules.ahead(v.path, v.s, other.s) < minGap then
			return true
		end
	end
	return false
end

-- Give way: true if I'm about to cross a give-way line on my path while a vehicle from another route is near it
-- (inside its radius) and not driving away from it. The line holds me until the way is clear.
function TrafficRules.giveWayBlocking(v: Vehicle): boolean
	local stopping = (v.speed * v.speed) / (2 * v.accel * 2) + 2.5
	for _, gw in v.path.giveWays do
		local toLine = TrafficRules.ahead(v.path, v.s, gw.s)
		if toLine < stopping then
			for _, other in registry do
				-- stopped vehicles don't count: they are often waiting for me (no standoff); if one is stopped right in
				-- my lane, vehicleBlocking still holds me back
				if other ~= v and other.path ~= v.path and other.speed > 0.5 then
					local ocf = other.model:GetPivot()
					local toGw = gw.pos - ocf.Position
					local flat = Vector3.new(toGw.X, 0, toGw.Z)
					if flat.Magnitude < gw.radius and math.abs(toGw.Y) < 5 then
						local look = Vector3.new(ocf.LookVector.X, 0, ocf.LookVector.Z)
						-- coming toward the line, or already on it (within its own length)
						if look:Dot(flat) > 0 or flat.Magnitude < other.halfLength + v.halfWidth + 1 then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

-- Other routes: true if any vehicle from a different route is in my lane ahead. If two vehicles see each other
-- (crossing, merging), the one with the lower id goes first so they never wait for each other forever.
function TrafficRules.vehicleBlocking(v: Vehicle, gap: number): boolean
	for _, other in registry do
		if other ~= v and other.path ~= v.path and sees(v, other, gap) then
			if not sees(other, v, gap) or v.id > other.id then
				return true
			end
		end
	end
	return false
end

return TrafficRules
