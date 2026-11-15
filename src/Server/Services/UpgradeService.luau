-- UpgradeService.luau
-- Purpose: validate and apply upgrade purchases (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local UpgradeService = {}
local DEBUG = true

function UpgradeService.Init(_others)
	if DEBUG then
		print("[UpgradeService] Init")
	end
end

function UpgradeService.Start()
	if DEBUG then
		print("[UpgradeService] Start")
	end
end

return UpgradeService
