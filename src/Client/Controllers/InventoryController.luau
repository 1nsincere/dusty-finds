-- InventoryController.luau
-- Purpose: inventory screen (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local InventoryController = {}
local DEBUG = true

function InventoryController.Init(_others)
	if DEBUG then
		print("[InventoryController] Init")
	end
end

function InventoryController.Start()
	if DEBUG then
		print("[InventoryController] Start")
	end
end

return InventoryController
