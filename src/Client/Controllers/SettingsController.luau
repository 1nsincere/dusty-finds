-- SettingsController.luau
-- Purpose: settings screen (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local SettingsController = {}
local DEBUG = true

function SettingsController.Init(_others)
	if DEBUG then
		print("[SettingsController] Init")
	end
end

function SettingsController.Start()
	if DEBUG then
		print("[SettingsController] Start")
	end
end

return SettingsController
