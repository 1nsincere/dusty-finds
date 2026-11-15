-- CustomerService.luau
-- Purpose: spawn customers and handle checkout (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local CustomerService = {}
local DEBUG = true

function CustomerService.Init(_others)
	if DEBUG then
		print("[CustomerService] Init")
	end
end

function CustomerService.Start()
	if DEBUG then
		print("[CustomerService] Start")
	end
end

return CustomerService
