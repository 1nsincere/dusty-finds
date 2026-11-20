-- TravelService.luau
-- Purpose: the Travel menu's teleports. RequestTravel(placeId) moves the player's character to a known place
-- (Config.Travel), after checks: known id, cooldown, alive, not riding a vehicle, not mid-restoration.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Travel, PlotService.GetPlot (MyShop), RestorationService.GetSession,
-- Remotes RequestTravel / Notify, Lib/Validate, Lib/Log. The client never sends a position: only a place id.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Travel = require(Shared.Config:WaitForChild("Travel"))
local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)

local TravelService = {}
local DEBUG = true
local log = Log.new("TravelService", DEBUG)

local PlotService, RestorationService
local lastTravel: { [Player]: number } = {}
local byId: { [string]: { [string]: any } } = {}
for _, place in Travel.PLACES do
	byId[place.id] = place
end

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, "Info", text)
end

-- Clear standing spot near `center`: walkable ground (upward face) with head room, tried in rings around the point.
local function safeSpot(center: Vector3, ignore: { Instance }): Vector3?
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	-- `center` is a point on the floor: land 4-10 studs away (never on the counter/pedestal itself), on floor within
	-- 2.5 studs of that height (so never on a roof, ledge or awning), with head room.
	for _, radius in { 4, 6, 8, 10 } do
		local steps = 8
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local p = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), rp)
			if hit and hit.Normal.Y > 0.7 and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - center.Y) < 2.5 then
				local feet = hit.Position
				local blocked = false
				for _, part in workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 3, 0)), Vector3.new(2.5, 4.6, 2.5), op) do
					if part.CanCollide and part.Transparency < 1 then
						blocked = true
						break
					end
				end
				if not blocked then
					return feet
				end
			end
		end
	end
	return nil
end

local function destination(player: Player, place: { [string]: any }): Vector3?
	if place.id == "MyShop" then
		local plot = PlotService.GetPlot(player)
		local door = plot and plot:FindFirstChild("Door", true)
		local floor = plot and plot:FindFirstChild("Floor")
		if door and door:IsA("BasePart") then
			return door.Position
		elseif floor and floor:IsA("BasePart") then
			return floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
		end
		return nil
	end
	return place.at
end

local function travel(player: Player, placeId: string)
	local place = byId[placeId]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not place or not humanoid or humanoid.Health <= 0 or not root then
		return
	end
	local now = os.clock()
	if lastTravel[player] and now - lastTravel[player] < Travel.COOLDOWN then
		notify(player, "Wait a moment before travelling again.")
		return
	end
	if humanoid.SeatPart then
		notify(player, "Hop off first, then travel.")
		return
	end
	if RestorationService and RestorationService.GetSession(player) then
		notify(player, "Finish or exit the restoration first.")
		return
	end
	local target = destination(player, place)
	local spot = target and safeSpot(target, { character })
	if not spot then
		notify(player, "Can't travel there right now.")
		return
	end
	lastTravel[player] = now
	local look = target - spot
	look = Vector3.new(look.X, 0, look.Z)
	local at = spot + Vector3.new(0, 3, 0)
	character:PivotTo(if look.Magnitude > 0.5 then CFrame.lookAt(at, at + look.Unit) else CFrame.new(at))
	log.info(player.Name, "travelled to", place.name)
end

function TravelService.Init(services)
	PlotService = services.PlotService
	RestorationService = services.RestorationService
	log.info("Init")
end

function TravelService.Start()
	Remotes.RequestTravel.OnServerEvent:Connect(function(player, placeId)
		if not Validate.rateLimit(player, "RequestTravel", 2) or type(placeId) ~= "string" or #placeId > 32 then
			return
		end
		travel(player, placeId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
	log.info("Start")
end

return TravelService
