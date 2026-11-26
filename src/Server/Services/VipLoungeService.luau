-- VipLoungeService.luau (ServerScriptService.Server.Services.VipLoungeService)
-- Purpose: the VIP Lounge in the Warehouse Market (docs/12 Stage 5, "VIP corner"): a cosy room whose doorway is closed by an invisible gate
-- that only VIP owners can walk through. Looks and hanging out only: no cash, XP, speed, odds or anything else (docs/11 §2 and §11).
-- How: two collision groups. Gate parts (tag "VipGate") are in group VipGate; the character parts of players whose attribute DF_VIP is true
-- (MonetizationService.PublishCosmetics) are in group VipMember; those two groups do not collide, everything else collides as normal.
-- The gate's ProximityPrompt (tag "VipGatePrompt") tells everyone else how to get in (a friendly toast, never a pay prompt).
-- Owner: Dev 1 (Ace). Depends on: MonetizationService (DF_VIP attribute), Remotes.Notify, Workspace.VIPLounge (Studio-only: parts tagged VipGate / VipGatePrompt).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local AccessGroups = require(script.Parent.Parent.Lib.AccessGroups)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local VipLoungeService = {}
local DEBUG = true
local log = Log.new("VipLoungeService", DEBUG)

local GATE_TAG, PROMPT_TAG = "VipGate", "VipGatePrompt"
local GATE_GROUP = AccessGroups.VIP_GATE

-- Which shop (1-6) this player owns, or nil. A shop owner also needs their own character group so their shop's shutter lets them in.
local function ownedPlotIndex(player: Player): number?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for k = 1, AccessGroups.PLOT_COUNT do
		local plot = plots:FindFirstChild("Plot" .. k)
		if plot and plot:GetAttribute("OwnerUserId") == player.UserId then
			return k
		end
	end
	return nil
end

-- Puts every part of a character in the right group (VIP / shop owner / both / neither). Parts added later are handled by the caller.
function VipLoungeService.ApplyToCharacter(character: Instance, isVip: boolean, plotIndex: number?)
	local group = AccessGroups.characterGroup(isVip, plotIndex)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function isVip(player: Player): boolean
	return player:GetAttribute("DF_VIP") == true
end

local watchers: { [Player]: () -> () } = {}

local function watchPlayer(player: Player)
	local function refresh()
		local character = player.Character
		if character then
			VipLoungeService.ApplyToCharacter(character, isVip(player), ownedPlotIndex(player))
		end
	end
	watchers[player] = refresh
	player.CharacterAdded:Connect(function(character)
		task.defer(refresh)
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = AccessGroups.characterGroup(isVip(player), ownedPlotIndex(player))
			end
		end)
	end)
	player:GetAttributeChangedSignal("DF_VIP"):Connect(refresh)
	refresh()
end

local function hookGate(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = GATE_GROUP
	end
end

local lastToast: { [Player]: number } = {}

local function hookPrompt(part: Instance)
	local prompt = if part:IsA("ProximityPrompt") then part else part:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt == nil then
		return
	end
	prompt.Triggered:Connect(function(player)
		if not Validate.isPlayer(player) then
			return
		end
		local nowTime = os.clock()
		if lastToast[player] and nowTime - lastToast[player] < 3 then
			return
		end
		lastToast[player] = nowTime
		if isVip(player) then
			Remotes.Notify:FireClient(player, "Info", "Welcome to the VIP Lounge! Make yourself comfortable.")
		else
			Remotes.Notify:FireClient(player, "Info", "The VIP Lounge is for VIP members. You can get VIP at the Collector's Corner.")
		end
	end)
end

function VipLoungeService.Init(_services)
	AccessGroups.register()
	log.info("Init")
end

function VipLoungeService.Start()
	for _, part in CollectionService:GetTagged(GATE_TAG) do
		hookGate(part)
	end
	CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(hookGate)
	for _, part in CollectionService:GetTagged(PROMPT_TAG) do
		hookPrompt(part)
	end
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(hookPrompt)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastToast[player] = nil
		watchers[player] = nil
	end)
	-- a player who buys / loses a shop changes group, so their shop's shutter lets them in (HoursService)
	local plots = Workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			for _, refresh in watchers do
				refresh()
			end
		end)
	end
	log.info("Start")
end

return VipLoungeService
