-- RestorationService.luau
-- Purpose: validate restoration steps and quality (empty skeleton: Init/Start only print for now).
-- Owner: Dev 2 (Dwayne). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local RestorationService = {}
local DEBUG = true

function RestorationService.Init(_others)
	if DEBUG then
		print("[RestorationService] Init")
	end
end

function RestorationService.Start()
	if DEBUG then
		print("[RestorationService] Start")
	end
end

return RestorationService
