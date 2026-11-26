-- VipLoungeCheck.luau (ServerScriptService.Server.Tests.VipLoungeCheck)
-- Purpose: tests the VIP Lounge gate (VipLoungeService): the collision groups let VIP members through and stop everyone else, a VIP's
-- parts (also accessories) change group, and a lost VIP puts them back. Pure: a fake character, nothing real is touched.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.VipLoungeCheck).run()
-- Also part of DevTools testAll.

local PhysicsService = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local VipLoungeCheck = {}

function VipLoungeCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0
	local function check(name: string, cond: boolean, detail: any?)
		if cond then
			passCount += 1
			table.insert(lines, "PASS " .. name)
		else
			failCount += 1
			table.insert(lines, `FAIL {name}{if detail ~= nil then " -> " .. tostring(detail) else ""}`)
		end
	end

	local Service = require(ServerScriptService.Server.Services.VipLoungeService)
	check("groups: the gate and member groups are registered", PhysicsService:IsCollisionGroupRegistered("VipGate") and PhysicsService:IsCollisionGroupRegistered("VipMember"))
	check("groups: a VIP member does NOT collide with the gate", PhysicsService:CollisionGroupsAreCollidable("VipGate", "VipMember") == false)
	check("groups: everyone else (Default) DOES collide with the gate", PhysicsService:CollisionGroupsAreCollidable("VipGate", "Default") == true)
	check("groups: a VIP member still collides with the world and other players", PhysicsService:CollisionGroupsAreCollidable("VipMember", "Default") == true and PhysicsService:CollisionGroupsAreCollidable("VipMember", "VipMember") == true)

	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	local accessory = Instance.new("Accessory")
	accessory.Parent = character
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Parent = accessory
	character.Parent = Workspace

	Service.ApplyToCharacter(character, true)
	check("apply: a VIP's parts, accessories included, join the member group", root.CollisionGroup == "VipMember" and handle.CollisionGroup == "VipMember")
	Service.ApplyToCharacter(character, false)
	check("apply: a player who is no longer VIP goes back to the normal group", root.CollisionGroup == "Default" and handle.CollisionGroup == "Default")
	character:Destroy()

	local lounge = Workspace:FindFirstChild("VIPLounge")
	local gate = lounge and lounge:FindFirstChild("Gate")
	check("studio: the VIP Lounge has a gate part tagged VipGate (Studio-only model)", gate ~= nil and CollectionService:HasTag(gate, "VipGate"))
	check("studio: the gate blocks (solid) and is invisible", gate ~= nil and (gate :: BasePart).CanCollide == true and (gate :: BasePart).Transparency == 1)
	local holder = lounge and lounge:FindFirstChild("GatePrompt")
	check("studio: the gate has a friendly prompt tagged VipGatePrompt", holder ~= nil and CollectionService:HasTag(holder, "VipGatePrompt") and holder:FindFirstChildWhichIsA("ProximityPrompt") ~= nil)
	local seats = 0
	for _, d in if lounge then lounge:GetDescendants() else {} do
		if d:IsA("Seat") then
			seats += 1
		end
	end
	check("studio: the lounge has seats to sit on", seats >= 3, seats)

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[VipLoungeCheck]", line)
		end
	end
	print(`[VipLoungeCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return VipLoungeCheck
