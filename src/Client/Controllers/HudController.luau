-- HudController.luau
-- Purpose: HUD: money, level, buttons (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local HudController = {}
local DEBUG = true

function HudController.Init(_others)
	if DEBUG then
		print("[HudController] Init")
	end
end

function HudController.Start()
	if DEBUG then
		print("[HudController] Start")
	end
end

return HudController
