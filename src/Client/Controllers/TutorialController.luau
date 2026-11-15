-- TutorialController.luau
-- Purpose: tutorial arrows and hints (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local TutorialController = {}
local DEBUG = true

function TutorialController.Init(_others)
	if DEBUG then
		print("[TutorialController] Init")
	end
end

function TutorialController.Start()
	if DEBUG then
		print("[TutorialController] Start")
	end
end

return TutorialController
