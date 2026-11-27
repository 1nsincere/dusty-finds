-- TownPoints.luau (ReplicatedStorage.Shared.Config.TownPoints)
-- Purpose: named places townsfolk stop at (WP5 step B, docs/13): food carts on the upper plaza, park benches. A walker that
-- passes within `Reach` studs of a point on a graph edge may stop on that edge, face the point and wait (and say a line).
-- Owner: Dev 2 (Dwayne) / Dev 3 (Sean). Depends on: nothing. Read by TownsfolkController via Shared.TownGraph.stopsFor.
-- `pos` is the thing the walker looks at (cart / bench), read from the Studio map 2026-11-27. Add a point = add a row. Stops
-- are cosmetic only: no money, no economy. WP6 reuses the vendor rows (kind = "vendor") for the cart loops.

local TownPoints = {
	Reach = 14, -- studs: the closest scanned walking line must pass this near the point, else the point is unused
	Chance = 0.6, -- chance a walker stops when it passes a point
	Points = {
		-- upper plaza food carts (y 18): Workspace.CanalTownAssembly.FoodCarts.<Name>
		{ id = "BananaCue", kind = "vendor", pos = Vector3.new(-21, 18, 24), dwell = { 3, 6 } },
		{ id = "Barbecue", kind = "vendor", pos = Vector3.new(-56, 18, 59), dwell = { 3, 6 } },
		{ id = "Taho", kind = "vendor", pos = Vector3.new(-139, 18, 24), dwell = { 3, 6 } },
		{ id = "HaloHalo", kind = "vendor", pos = Vector3.new(-139, 18, -24), dwell = { 3, 6 } },
		{ id = "Fishball", kind = "vendor", pos = Vector3.new(-104, 18, -59), dwell = { 3, 6 } },
		{ id = "Pandesal", kind = "vendor", pos = Vector3.new(-104, 18, 59), dwell = { 3, 6 } },
		-- WP7 (light version): town STORES with a shopkeeper inside, walkers stop out front as customers. `vendorPos` = where the
		-- shopkeeper stands (inside, behind the window / door), because a store front is not a cart you can walk around.
		-- Workspace.CanalTownWow.BlenderBuildings.SariSari (open grilled front facing +X) and .Bakery ("Panaderia", door facing +Z).
		{ id = "SariSari", kind = "vendor", pos = Vector3.new(-39.7, 8.7, -268), vendorPos = Vector3.new(-42.5, 8.7, -268), dwell = { 3, 6 } },
		{ id = "Panaderia", kind = "vendor", pos = Vector3.new(-116.9, 8.7, -228), vendorPos = Vector3.new(-116.9, 8.7, -230.5), dwell = { 3, 6 } },
		-- park benches: Workspace.Environment.Districts.Park.BenchSeat
		{ id = "ParkBench1", kind = "bench", pos = Vector3.new(-200, 11, 270), dwell = { 5, 10 } },
		{ id = "ParkBench2", kind = "bench", pos = Vector3.new(-207, 11, 232), dwell = { 5, 10 } },
	},
	-- Short bubble lines per kind (subtle Filipino flavour, kid friendly). Shown only to close, animating walkers.
	Lines = {
		vendor = { "Isang order po!", "Ang bango naman!", "Kuya, isa nga!", "Magkano po?" },
		bench = { "Pahinga muna.", "Ang ganda ng hangin.", "Ang sarap umupo." },
		-- what the VENDOR says (WP6): calling out to the plaza, and while a walker is stopped at the cart
		vendorCall = { "Mainit pa po!", "Tara, bili na!", "Sariwa po dito!", "Dito na po kayo!" },
		vendorServe = { "Heto na po!", "Salamat po!", "Eto po ang sukli!" },
	},
	CustomerClearance = 3.5, -- studs: a walker waiting at a point stands at least this far from it (a walking line can run right through a cart)
	VendorStandOff = 2.5, -- studs: the vendor stands this far past the cart's centre, on the side away from the customer
	VendorCallEvery = 18, -- seconds between a vendor's calls (each vendor has its own phase)
	VendorCallFor = 3, -- seconds a call stays up
	VendorServeFor = 2.5, -- seconds the "Heto na po!" line stays up after a customer arrives
}

return TownPoints
