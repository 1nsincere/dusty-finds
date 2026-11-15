-- PlotService.luau
-- Purpose: assign and release shop plots (empty skeleton: Init/Start only print for now).
-- Owner: Dev 1 (Ace). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local PlotService = {}
local DEBUG = true

function PlotService.Init(_others)
	if DEBUG then
		print("[PlotService] Init")
	end
end

function PlotService.Start()
	if DEBUG then
		print("[PlotService] Start")
	end
end

return PlotService
