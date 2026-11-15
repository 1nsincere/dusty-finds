-- ShopController.luau
-- Purpose: upgrades and supply board UI (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local ShopController = {}
local DEBUG = true

function ShopController.Init(_others)
	if DEBUG then
		print("[ShopController] Init")
	end
end

function ShopController.Start()
	if DEBUG then
		print("[ShopController] Start")
	end
end

return ShopController
