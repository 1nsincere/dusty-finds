-- EconomyService.luau
-- Purpose: add/spend cash, XP and levels (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local EconomyService = {}
local DEBUG = true

function EconomyService.Init(_others)
	if DEBUG then
		print("[EconomyService] Init")
	end
end

function EconomyService.Start()
	if DEBUG then
		print("[EconomyService] Start")
	end
end

return EconomyService
