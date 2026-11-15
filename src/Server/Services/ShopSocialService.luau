-- ShopSocialService.luau
-- Purpose: likes, announcements, visits and invites (empty skeleton: Init/Start only print for now).
-- Owner: Dev 3 (Sean). Depends on: nothing yet.
-- Init = set up and grab other modules (no waiting); Start = connect events. Real code comes with its feature.

local ShopSocialService = {}
local DEBUG = true

function ShopSocialService.Init(_others)
	if DEBUG then
		print("[ShopSocialService] Init")
	end
end

function ShopSocialService.Start()
	if DEBUG then
		print("[ShopSocialService] Start")
	end
end

return ShopSocialService
