-- DisplayService.luau
-- Purpose: display and exhibit slots (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local DisplayService = {}
local DEBUG = true

function DisplayService.Init(_others)
	if DEBUG then
		print("[DisplayService] Init")
	end
end

function DisplayService.Start()
	if DEBUG then
		print("[DisplayService] Start")
	end
end

return DisplayService
