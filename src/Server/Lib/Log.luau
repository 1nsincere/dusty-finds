-- Log.luau (ServerScriptService.Server.Lib.Log)
-- Purpose: tagged debug printing, so Output lines look like "[ShipmentService] ..." (CLAUDE.md §6.3).
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Usage: local log = Log.new("ShipmentService", DEBUG); log.info("opened box") prints only when DEBUG is true,
-- log.warn("bad crate id") always prints as a yellow warning.

local Log = {}

function Log.new(tag: string, debugEnabled: boolean?)
	local prefix = "[" .. tostring(tag) .. "]"
	local logger = {}

	function logger.info(...)
		if debugEnabled == true then
			print(prefix, ...)
		end
	end

	function logger.warn(...)
		warn(prefix, ...)
	end

	return logger
end

return Log
