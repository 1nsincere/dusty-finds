-- CustomerUIController.luau
-- Purpose: customer thought bubbles and checkout UI (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local CustomerUIController = {}
local DEBUG = true

function CustomerUIController.Init(_others)
	if DEBUG then
		print("[CustomerUIController] Init")
	end
end

function CustomerUIController.Start()
	if DEBUG then
		print("[CustomerUIController] Start")
	end
end

return CustomerUIController
