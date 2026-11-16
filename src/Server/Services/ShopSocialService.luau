-- ShopSocialService.luau (ServerScriptService.Server.Services.ShopSocialService)
-- Purpose: social features between shops on the same server. Now: visiting (RequestVisit puts your character at
-- another shop's Spawn, or back home). Later: likes, invites (announcements already go through EconomyService/Notify).
-- Owner: Dev 3 (Sean). Depends on: Shared.Remotes (RequestVisit, Notify), PlotService.GetPlot, RestorationService.GetSession,
-- Lib.Validate, plot part "Spawn" (docs/03 §2). No teleporting between servers in MVP (docs/01 E).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ShopSocialService = {}
local DEBUG = true
local log = Log.new("ShopSocialService", DEBUG)

local PlotService, RestorationService = nil, nil

local SPAWN_LIFT = Vector3.new(0, 3, 0) -- same as PlotService: stand above the Spawn part, not inside it

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, "Info", text)
end

-- Returns true if the visitor was moved. Every refusal is silent for spam, a toast for honest mistakes.
function ShopSocialService.Visit(visitor: Player, ownerUserId: number): (boolean, string?)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if owner == nil then
		notify(visitor, "That shopkeeper has left the server.")
		return false, "ownerGone"
	end
	local plot = PlotService.GetPlot(owner)
	local spawnPart = plot and plot:FindFirstChild("Spawn")
	if spawnPart == nil or not spawnPart:IsA("BasePart") then
		return false, "noPlot"
	end
	if RestorationService and RestorationService.GetSession and RestorationService.GetSession(visitor) then
		-- Leaving mid-minigame would strand the session at your bench.
		notify(visitor, "Finish restoring first!")
		return false, "restoring"
	end
	local character = visitor.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 or not character:FindFirstChild("HumanoidRootPart") then
		return false, "noCharacter"
	end
	if humanoid.Sit then
		humanoid.Sit = false -- PivotTo while seated would drag the seat along
	end
	character:PivotTo(spawnPart.CFrame + SPAWN_LIFT)
	if owner == visitor then
		notify(visitor, "Welcome back to your shop! 🏠")
	else
		notify(visitor, `Visiting {owner.DisplayName}'s shop 👋`)
	end
	log.info(visitor.Name, "->", plot.Name, `({owner.Name}'s shop)`)
	return true
end

function ShopSocialService.Init(services)
	PlotService = services.PlotService
	RestorationService = services.RestorationService
	log.info("Init")
end

function ShopSocialService.Start()
	Remotes.RequestVisit.OnServerEvent:Connect(function(player, ownerUserId)
		if not Validate.rateLimit(player, "RequestVisit", 1) then
			return
		end
		if not Validate.isInteger(ownerUserId) then
			return
		end
		ShopSocialService.Visit(player, ownerUserId)
	end)
	log.info("Start")
end

return ShopSocialService
