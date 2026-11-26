-- AccessGroups.luau (ServerScriptService.Server.Lib.AccessGroups)
-- Purpose: the physics collision groups that decide who can walk through which gate, in ONE place (a part can only be in one group, so
-- "VIP", "owner of shop 3" and "VIP who owns shop 3" each get their own character group). Gates: the VIP Lounge gate (VipGate: only VIPs
-- pass) and each shop's shutter (ShopShutterN: only the owner of shop N passes). Everybody else collides with them as normal.
-- Owner: Dev 1 (Ace). Used by: VipLoungeService (puts characters in groups), HoursService (puts shutters in groups).

local PhysicsService = game:GetService("PhysicsService")

local AccessGroups = {}

AccessGroups.PLOT_COUNT = 6
AccessGroups.VIP_GATE = "VipGate"
AccessGroups.VIP_MEMBER = "VipMember"

function AccessGroups.shutterGroup(plotIndex: number): string
	return "ShopShutter" .. plotIndex
end

-- The group for a character: isVip passes the VIP gate; plotIndex (1-6, or nil) passes that shop's shutter.
function AccessGroups.characterGroup(isVip: boolean, plotIndex: number?): string
	if plotIndex == nil then
		return if isVip then AccessGroups.VIP_MEMBER else "Default"
	end
	return (if isVip then "VipOwner" else "ShopOwner") .. plotIndex
end

local function ensure(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Safe to call many times.
function AccessGroups.register()
	ensure(AccessGroups.VIP_GATE)
	ensure(AccessGroups.VIP_MEMBER)
	PhysicsService:CollisionGroupSetCollidable(AccessGroups.VIP_GATE, AccessGroups.VIP_MEMBER, false)
	for j = 1, AccessGroups.PLOT_COUNT do
		ensure(AccessGroups.shutterGroup(j))
	end
	for k = 1, AccessGroups.PLOT_COUNT do
		local shopOwner = AccessGroups.characterGroup(false, k)
		local vipOwner = AccessGroups.characterGroup(true, k)
		ensure(shopOwner)
		ensure(vipOwner)
		PhysicsService:CollisionGroupSetCollidable(AccessGroups.VIP_GATE, vipOwner, false)
		for j = 1, AccessGroups.PLOT_COUNT do
			local passes = j == k
			PhysicsService:CollisionGroupSetCollidable(AccessGroups.shutterGroup(j), shopOwner, not passes)
			PhysicsService:CollisionGroupSetCollidable(AccessGroups.shutterGroup(j), vipOwner, not passes)
		end
	end
end

return AccessGroups
