-- TownGraphCheck.luau (ServerScriptService.Server.Tests.TownGraphCheck)
-- Purpose: WP5 checks on the townsfolk waypoint graph: built from the configured routes, walks only use real edges, walks
-- are the same for the same seed (every client must agree), excluded routes add no edges, nothing enters the moat margin.
-- Owner: Dev 2 (Dwayne) / Dev 3 (Sean). Depends on: Shared.TownGraph, Shared.Config.Townsfolk.
-- Run: require(game.ServerScriptService.Server.Tests.TownGraphCheck).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TownGraph = require(ReplicatedStorage.Shared.TownGraph)
local Townsfolk = require(ReplicatedStorage.Shared.Config.Townsfolk)

local TownGraphCheck = {}
local MOAT_MARGIN = 3 -- studs between a walking line and the park moat's edge

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

local function distanceToSegment(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 == 0 then 0 else math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function TownGraphCheck.run()
	local lines = {}
	local passed, failed = 0, 0
	local function check(label: string, ok: boolean, detail: any?)
		if ok then
			passed += 1
			table.insert(lines, "PASS " .. label)
		else
			failed += 1
			table.insert(lines, "FAIL " .. label .. (if detail ~= nil then ": " .. tostring(detail) else ""))
		end
	end

	local routes = {}
	for _, text in Townsfolk.Routes do
		table.insert(routes, parseRoute(text))
	end
	local excluded = {}
	for _, n in Townsfolk.GraphExcluded do
		excluded[n] = true
	end
	local graph = TownGraph.build(routes, excluded)

	check("graph has nodes", #graph.nodes > 0, #graph.nodes)
	local used = 0
	for r in routes do
		if not excluded[r] then
			used += 1
		end
	end
	local starts = 0
	for _ in graph.routeStart do
		starts += 1
	end
	check("every non-excluded route has a start node", starts == used, `{starts} of {used}`)
	local legsOk = true
	for r, route in routes do
		if not excluded[r] then
			for k = 1, #route - 1 do
				local a, b = TownGraph.nodeAt(graph, route[k]), TownGraph.nodeAt(graph, route[k + 1])
				if not (a and b) or (a ~= b and not TownGraph.hasEdge(graph, a, b)) then
					legsOk = false
				end
			end
		end
	end
	check("every non-excluded route leg is an edge", legsOk)

	-- edges are symmetric, no self loops
	local symmetric = true
	for a, list in graph.adj do
		for _, b in list do
			if a == b or not TownGraph.hasEdge(graph, b, a) then
				symmetric = false
			end
		end
	end
	check("edges are symmetric with no self loops", symmetric)

	-- excluded routes contribute nothing: a graph built with every route excluded is empty
	local all = {}
	for r in routes do
		all[r] = true
	end
	check("excluded routes add no nodes", #TownGraph.build(routes, all).nodes == 0)

	-- walks
	local walksOk, sameOk, lenOk = true, true, true
	for r, startNode in graph.routeStart do
		local a = TownGraph.walk(graph, startNode, Random.new(r), Townsfolk.GraphLegs[1], Townsfolk.GraphLegs[2])
		local b = TownGraph.walk(graph, startNode, Random.new(r), Townsfolk.GraphLegs[1], Townsfolk.GraphLegs[2])
		if #a ~= #b then
			sameOk = false
		else
			for k = 1, #a do
				if a[k] ~= b[k] then
					sameOk = false
				end
			end
		end
		if #a > Townsfolk.GraphLegs[1] + 1 then
			lenOk = false
		end
		for k = 1, #a - 1 do
			local ia, ib = TownGraph.nodeAt(graph, a[k]), TownGraph.nodeAt(graph, a[k + 1])
			if not (ia and ib and TownGraph.hasEdge(graph, ia, ib)) then
				walksOk = false
			end
		end
	end
	check("every walk step is a graph edge", walksOk)
	check("same seed gives the same walk", sameOk)
	check("walks respect the leg limit", lenOk)

	-- WP6 data: unique ids, every kind has bubble lines, vendor call/serve pools exist, timings are sane
	local TP = require(ReplicatedStorage.Shared.Config.TownPoints)
	local seenIds, dataOk = {}, true
	for _, p in TP.Points do
		if seenIds[p.id] or not TP.Lines[p.kind] or #TP.Lines[p.kind] == 0 or p.dwell[1] > p.dwell[2] then
			dataOk = false
		end
		seenIds[p.id] = true
	end
	check("town points: unique ids, lines per kind, sane dwell", dataOk)
	check("vendor line pools exist", #TP.Lines.vendorCall > 0 and #TP.Lines.vendorServe > 0)
	check("vendor timings fit together", TP.VendorCallFor < TP.VendorCallEvery and TP.VendorServeFor > 0 and TP.VendorStandOff > 0)

	-- town points (carts, benches): each used point stops on a graph edge, within reach. Unused points are reported, not failed:
	-- they just have no scanned walking line near them yet (add a route there, or raise Reach).
	local TownPoints = require(ReplicatedStorage.Shared.Config.TownPoints)
	local targets = {}
	for _, p in TownPoints.Points do
		table.insert(targets, p.pos)
	end
	local stops = TownGraph.stopsFor(graph, targets, TownPoints.Reach)
	check("at least one town point has a walking line near it", #stops > 0, `{#stops} of {#targets}`)
	local usedIds = {}
	for _, s in stops do
		usedIds[s.index] = true
		check(`{TownPoints.Points[s.index].id} stop is within reach`, s.distance <= TownPoints.Reach, s.distance)
	end
	for index, p in TownPoints.Points do
		if not usedIds[index] then
			table.insert(lines, `NOTE {p.id} has no walking line within {TownPoints.Reach} studs: no walker will stop there`)
		end
	end

	-- the moat: only checked when the town is loaded in this place
	local town = workspace:FindFirstChild("CanalTownWow")
	local park = town and town:FindFirstChild("Park")
	local moat = park and park:FindFirstChild("Moat")
	if moat and moat:IsA("BasePart") then
		local center = Vector2.new(moat.Position.X, moat.Position.Z)
		local radius = math.max(moat.Size.Y, moat.Size.Z) / 2
		local worst = math.huge
		for a, list in graph.adj do
			for _, b in list do
				local pa, pb = graph.nodes[a], graph.nodes[b]
				worst = math.min(worst, distanceToSegment(center, Vector2.new(pa.X, pa.Z), Vector2.new(pb.X, pb.Z)) - radius)
			end
		end
		check(`graph stays {MOAT_MARGIN} studs off the moat`, worst >= MOAT_MARGIN, `closest {string.format("%.1f", worst)}`)
	else
		table.insert(lines, "SKIP moat margin (Workspace.CanalTownWow.Park.Moat not loaded)")
	end

	for _, line in lines do
		print("[TownGraphCheck] " .. line)
	end
	print("[TownGraphCheck]", passed, "passed;", failed, "failed")
	return lines, passed, failed
end

return TownGraphCheck
