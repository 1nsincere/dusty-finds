-- RestorationController.luau
-- Purpose: bench view, camera and minigame step runner (empty skeleton: Init/Start only print for now).
-- Owner: Dev 2 (Dwayne). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local RestorationController = {}
local DEBUG = true

function RestorationController.Init(_others)
	if DEBUG then
		print("[RestorationController] Init")
	end
end

function RestorationController.Start()
	if DEBUG then
		print("[RestorationController] Start")
	end
end

return RestorationController
