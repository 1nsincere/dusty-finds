-- Validate.luau (ServerScriptService.Server.Lib.Validate)
-- Purpose: the server-side checks every remote handler uses (docs/03_Architecture.md §7): types, rate limit, distance.
-- Owner: Dev 1 (Ace). Depends on: nothing (uses the Players service).
-- Never trust anything a client sends. Handlers call these first and `return` on false. Example:
--   if not Validate.rateLimit(player, "RequestBuyCrate", 3) then return end
--   if not Validate.isString(crateId, 50) then return end

local Players = game:GetService("Players")

local Validate = {}

local DEFAULT_MAX_PER_SECOND = 5 -- docs/03 §6: default rate limit

-- ===== Type checks (all return true/false, never error) =====

function Validate.isString(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	return maxLength == nil or #value <= maxLength
end

-- A real number: rejects nil, NaN and infinity (exploiters can send those). min/max are optional bounds.
function Validate.isNumber(value: any, min: number?, max: number?): boolean
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if min ~= nil and value < min then
		return false
	end
	if max ~= nil and value > max then
		return false
	end
	return true
end

function Validate.isInteger(value: any, min: number?, max: number?): boolean
	return Validate.isNumber(value, min, max) and value == math.floor(value)
end

function Validate.isBoolean(value: any): boolean
	return type(value) == "boolean"
end

function Validate.isTable(value: any): boolean
	return type(value) == "table"
end

function Validate.isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

-- True if `id` is a string that is a key in a Config table, e.g. Validate.isConfigId(crateId, Crates).
function Validate.isConfigId(id: any, configTable: { [string]: any }): boolean
	return type(id) == "string" and configTable[id] ~= nil
end

-- ===== Rate limiter =====
-- Allows at most `maxPerSecond` calls per player per remote name in any 1-second window.
local windows: { [Player]: { [string]: { start: number, count: number } } } = {}

function Validate.rateLimit(player: Player, remoteName: string, maxPerSecond: number?): boolean
	if not Validate.isPlayer(player) or type(remoteName) ~= "string" then
		return false
	end
	local limit = maxPerSecond or DEFAULT_MAX_PER_SECOND
	local now = os.clock()

	local perPlayer = windows[player]
	if perPlayer == nil then
		perPlayer = {}
		windows[player] = perPlayer
	end
	local window = perPlayer[remoteName]
	if window == nil or now - window.start >= 1 then
		perPlayer[remoteName] = { start = now, count = 1 }
		return limit >= 1
	end

	window.count += 1
	return window.count <= limit
end

-- Forget a player's counters when they leave, so the table doesn't grow forever.
Players.PlayerRemoving:Connect(function(player)
	windows[player] = nil
end)

-- ===== Distance check =====
-- True if the player's character is within `maxStuds` of `target` (a Vector3 or a BasePart).
-- False if the player has no character, or the target is invalid.
function Validate.withinDistance(player: Player, target: any, maxStuds: number): boolean
	if not Validate.isPlayer(player) or not Validate.isNumber(maxStuds, 0) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end

	local targetPosition: Vector3
	if typeof(target) == "Vector3" then
		targetPosition = target
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		targetPosition = target.Position
	else
		return false
	end

	return (root.Position - targetPosition).Magnitude <= maxStuds
end

return Validate
