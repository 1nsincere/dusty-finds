-- DiscoveryController.luau
-- Purpose: box opening and item reveal (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean) UI, Dev 2 (Dwayne) VFX. Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local DiscoveryController = {}
local DEBUG = true

function DiscoveryController.Init(_others)
	if DEBUG then
		print("[DiscoveryController] Init")
	end
end

function DiscoveryController.Start()
	if DEBUG then
		print("[DiscoveryController] Start")
	end
end

return DiscoveryController
