-- TownGraph.luau (ReplicatedStorage.Shared.TownGraph)
-- Purpose: turns the scanned townsfolk routes into ONE waypoint graph (corners shared by several routes become one node,
-- every scanned leg becomes an edge) and walks it deterministically. Walkers can then switch routes at shared corners but
-- never cross ground nobody scanned. Pure functions: no Instances, no state, safe to run on every client with the same seed.
-- Owner: Dev 3 (Sean) / Dev 2 (Dwayne), WP5 of docs/13_NPC_Life_Brief.md. Depends on: nothing (reads Config/Townsfolk data
-- passed in by the caller).

local TownGraph = {}

export type Graph = {
	nodes: { Vector3 },
	adj: { { number } }, -- adj[n] = neighbour node ids, in the order the routes were read (deterministic)
	routeStart: { [number]: number }, -- routeIndex -> node id of that route's first corner (only graph routes)
	ids: { [string]: number }, -- corner key -> node id (see nodeAt)
}

local LEVEL_BAND = 6 -- studs; street (8.5), upper plaza (18) and canal (4) never share a corner, ramps stay in one band

-- Corners match on the same x, z (rounded to a stud) and level band, so 18.0 and 18.15 weld but street and plaza do not.
local function keyOf(p: Vector3): string
	return string.format("%d,%d,%d", math.floor(p.X + 0.5), math.floor(p.Z + 0.5), math.floor(p.Y / LEVEL_BAND))
end

-- routes: list of corner lists. excluded: [routeIndex] = true for routes whose legs must NOT become edges
-- (their ground check failed in places: they keep walking their old there-and-back line instead).
function TownGraph.build(routes: { { Vector3 } }, excluded: { [number]: boolean }?): Graph
	local ids: { [string]: number } = {}
	local graph: Graph = { nodes = {}, adj = {}, routeStart = {}, ids = ids }
	local function nodeFor(p: Vector3): number
		local key = keyOf(p)
		local id = ids[key]
		if id == nil then
			id = #graph.nodes + 1
			ids[key] = id
			graph.nodes[id] = p
			graph.adj[id] = {}
		end
		return id
	end
	for r, route in routes do
		if not (excluded and excluded[r]) and #route >= 2 then
			local previous = nodeFor(route[1])
			graph.routeStart[r] = previous
			for k = 2, #route do
				local current = nodeFor(route[k])
				if current ~= previous then
					if not table.find(graph.adj[previous], current) then
						table.insert(graph.adj[previous], current)
					end
					if not table.find(graph.adj[current], previous) then
						table.insert(graph.adj[current], previous)
					end
				end
				previous = current
			end
		end
	end
	return graph
end

function TownGraph.hasEdge(graph: Graph, a: number, b: number): boolean
	return graph.adj[a] ~= nil and table.find(graph.adj[a], b) ~= nil
end

-- A random walk of corners from `start`: no immediate U-turn unless the corner is a dead end, stops after maxLegs legs or
-- once minLength studs are covered. The caller walks it there and back, so it only has to be a valid chain of edges.
function TownGraph.walk(graph: Graph, start: number, rng: Random, maxLegs: number, minLength: number): { Vector3 }
	local points = { graph.nodes[start] }
	local previous, current, length = nil, start, 0
	for _ = 1, maxLegs do
		local options = graph.adj[current]
		if options == nil or #options == 0 then
			break
		end
		local pool = {}
		for _, id in options do
			if id ~= previous then
				table.insert(pool, id)
			end
		end
		if #pool == 0 then
			pool = options -- dead end: turn around
		end
		local nextId = pool[rng:NextInteger(1, #pool)]
		length += (graph.nodes[nextId] - graph.nodes[current]).Magnitude
		table.insert(points, graph.nodes[nextId])
		previous, current = current, nextId
		if length >= minLength then
			break
		end
	end
	return points
end

export type Stop = { index: number, point: Vector3, distance: number } -- index = position in the points list

-- For each point of interest, the closest spot ON a graph edge (scanned ground, so nobody walks off the map to reach it),
-- or nothing if no edge passes within `reach` studs (flat distance) and within 5 studs in height (never match across floors).
function TownGraph.stopsFor(graph: Graph, targets: { Vector3 }, reach: number): { Stop }
	local stops: { Stop } = {}
	for index, target in targets do
		local best: Stop? = nil
		for a, list in graph.adj do
			for _, b in list do
				if a < b then
					local pa, pb = graph.nodes[a], graph.nodes[b]
					local ab = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
					local len2 = ab:Dot(ab)
					local ap = Vector3.new(target.X - pa.X, 0, target.Z - pa.Z)
					local t = if len2 == 0 then 0 else math.clamp(ap:Dot(ab) / len2, 0, 1)
					local spot = pa:Lerp(pb, t)
					local distance = Vector3.new(target.X - spot.X, 0, target.Z - spot.Z).Magnitude
					if distance <= reach and math.abs(spot.Y - target.Y) <= 5 and (best == nil or distance < best.distance) then
						best = { index = index, point = spot, distance = distance }
					end
				end
			end
		end
		if best then
			table.insert(stops, best)
		end
	end
	return stops
end

-- The node a corner belongs to (welded corners share one node), nil if it is not in the graph. Used by tests.
function TownGraph.nodeAt(graph: Graph, point: Vector3): number?
	return graph.ids[keyOf(point)]
end

return TownGraph
