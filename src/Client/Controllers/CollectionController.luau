-- CollectionController.luau
-- Purpose: collection book screen (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local CollectionController = {}
local DEBUG = true

function CollectionController.Init(_others)
	if DEBUG then
		print("[CollectionController] Init")
	end
end

function CollectionController.Start()
	if DEBUG then
		print("[CollectionController] Start")
	end
end

return CollectionController
