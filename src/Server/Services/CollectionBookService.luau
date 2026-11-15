-- CollectionBookService.luau
-- Purpose: collection book tracking and rewards (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local CollectionBookService = {}
local DEBUG = true

function CollectionBookService.Init(_others)
	if DEBUG then
		print("[CollectionBookService] Init")
	end
end

function CollectionBookService.Start()
	if DEBUG then
		print("[CollectionBookService] Start")
	end
end

return CollectionBookService
