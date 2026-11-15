-- ShipmentService.luau
-- Purpose: deliveries, crate purchases and rolls (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local ShipmentService = {}
local DEBUG = true

function ShipmentService.Init(_others)
	if DEBUG then
		print("[ShipmentService] Init")
	end
end

function ShipmentService.Start()
	if DEBUG then
		print("[ShipmentService] Start")
	end
end

return ShipmentService
