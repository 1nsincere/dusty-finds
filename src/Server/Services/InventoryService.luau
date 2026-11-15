-- InventoryService.luau
-- Purpose: add/remove/move items and capacity (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local InventoryService = {}
local DEBUG = true

function InventoryService.Init(_others)
	if DEBUG then
		print("[InventoryService] Init")
	end
end

function InventoryService.Start()
	if DEBUG then
		print("[InventoryService] Start")
	end
end

return InventoryService
