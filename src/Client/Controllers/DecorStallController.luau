-- DecorStallController.luau (StarterPlayerScripts.Client.Controllers.DecorStallController)
-- Purpose: the decor counters in the Warehouse Market rooms. Each counter is a part tagged "DecorStall" (Config/DecorRooms.TAG) with the
-- attribute Room = a room id and a ProximityPrompt; the prompt opens the Upgrades window on the Decor tab showing only that room's pieces
-- (ShopController.OpenDecorStall). A room with no pieces yet says it is coming soon. Walking away closes the window. The server checks every
-- purchase again (UpgradeService: near the room's counter, market open, in stock), so this file only opens and closes the window.
-- Owner: Dev 1 (Ace). Depends on: ShopController, HudController (toasts), Shared.Config.DecorRooms / Upgrades.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DecorRooms = require(Shared:WaitForChild("Config"):WaitForChild("DecorRooms"))
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))

local DecorStallController = {}
local DEBUG = true
local others = nil
local counters: { [BasePart]: string } = {} -- [counter part] = room id
local openRoom: string? = nil

local function log(...)
	if DEBUG then
		print("[DecorStallController]", ...)
	end
end

local function hasPieces(room: string): boolean
	for _, def in Upgrades do
		if def.tab == DecorRooms.TAB and def.room == room then
			return true
		end
	end
	return false
end

local function toast(text: string)
	local hud = others and others.HudController
	if hud and hud.Notify then
		hud.Notify("Info", text)
	end
end

local function hook(part: Instance)
	if not part:IsA("BasePart") or counters[part] ~= nil then
		return
	end
	local room = part:GetAttribute("Room")
	if type(room) ~= "string" or DecorRooms.ROOMS[room] == nil then
		warn(`[DecorStallController] {part:GetFullName()} needs an attribute Room = one of Config/DecorRooms.ROOMS`)
		return
	end
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt == nil then
		warn(`[DecorStallController] {part:GetFullName()} has no ProximityPrompt`)
		return
	end
	counters[part] = room
	prompt.Triggered:Connect(function()
		if not hasPieces(room) then
			toast(`{DecorRooms.ROOMS[room].name} opens soon!`)
			return
		end
		local shop = others and others.ShopController
		if shop and shop.OpenDecorStall then
			openRoom = room
			shop.OpenDecorStall(room)
		end
	end)
	log("counter hooked:", room, part:GetFullName())
end

function DecorStallController.Init(controllers)
	others = controllers
end

function DecorStallController.Start()
	for _, part in CollectionService:GetTagged(DecorRooms.TAG) do
		hook(part)
	end
	CollectionService:GetInstanceAddedSignal(DecorRooms.TAG):Connect(hook)
	-- walking away from the counter closes the window (a little slack so it does not flicker)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local shop = others and others.ShopController
			if shop and shop.IsDecorStallOpen and shop.IsDecorStallOpen() and openRoom then
				local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				local near = false
				for part, room in counters do
					if room == openRoom and root and part.Parent and (part.Position - (root :: BasePart).Position).Magnitude <= DecorRooms.BuyMaxStuds + 8 then
						near = true
					end
				end
				if not near then
					shop.CloseUpgrades()
					openRoom = nil
				end
			end
		end
	end)
	log("Start")
end

return DecorStallController
