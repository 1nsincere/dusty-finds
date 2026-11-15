-- DataService.luau
-- Purpose: load/save player data and push state to clients (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local DataService = {}
local DEBUG = true

function DataService.Init(_others)
	if DEBUG then
		print("[DataService] Init")
	end
end

function DataService.Start()
	if DEBUG then
		print("[DataService] Start")
	end
end

return DataService
