-- ShopSocialService.luau (ServerScriptService.Server.Services.ShopSocialService)
-- Purpose: social features between shops on the same server: visiting (RequestVisit puts your character at another
-- shop's Spawn, or back home) and likes (a visitor's Counter.LikePrompt: +1 like for the owner, small capped cash).
-- Later: invites (announcements already go through EconomyService/Notify).
-- Owner: Dev 3 (Sean). Depends on: Shared.Remotes (RequestVisit, Notify), Shared.Config.Economy (LikeReward,
-- LikeRewardMaxPerDay), DataService (likes = {received, givenToday, rewardedToday, day}), EconomyService.AddCash,
-- PlotService.GetPlot, RestorationService.GetSession, Lib.Validate, plot "Spawn" + "Counter.LikePrompt" (docs/03 §2).
-- Likes come from the prompt's Triggered on the server (Roblox checks the distance); RequestLikeShop stays unused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local ShopSocialService = {}
local DEBUG = true
local log = Log.new("ShopSocialService", DEBUG)

local PlotService, RestorationService, DataService, EconomyService = nil, nil, nil, nil

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

-- ===== Likes =====

local function utcDay(now: number?): number
	return (now or os.time()) // 86400 -- os.time() is UTC on Roblox servers
end

-- A fresh copy of `likes` for today: a new day clears the daily lists (givenToday, rewardedToday).
local function likesForToday(likes: any, today: number)
	local fresh = {
		received = 0,
		givenToday = {},
		rewardedToday = 0,
		day = today,
	}
	if type(likes) == "table" then
		fresh.received = tonumber(likes.received) or 0
		if likes.day == today then
			fresh.givenToday = if type(likes.givenToday) == "table" then table.clone(likes.givenToday) else {}
			fresh.rewardedToday = tonumber(likes.rewardedToday) or 0
		end
	end
	return fresh
end

-- The rule, with no game objects so it can be checked on its own (see the STATUS entry for the checks).
-- Returns ok, reason, newGiverLikes, newOwnerLikes, cashForOwner.
function ShopSocialService._decideLike(giverUserId: number, ownerUserId: number, giverLikes: any, ownerLikes: any, now: number?)
	if giverUserId == ownerUserId then
		return false, "ownShop"
	end
	local today = utcDay(now)
	local giver = likesForToday(giverLikes, today)
	local owner = likesForToday(ownerLikes, today)
	local key = tostring(ownerUserId) -- data keys are strings (docs/03 §9)
	if giver.givenToday[key] then
		return false, "alreadyLiked"
	end
	giver.givenToday[key] = true
	owner.received += 1
	local cash = 0
	if owner.rewardedToday < Economy.LikeRewardMaxPerDay then
		owner.rewardedToday += 1
		cash = Economy.LikeReward
	end
	return true, nil, giver, owner, cash
end

local function likePromptOf(plot: Instance): ProximityPrompt?
	local counter = plot:FindFirstChild("Counter")
	local prompt = counter and counter:FindFirstChild("LikePrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Everyone sees the shop's total on the prompt ("❤️ 12 likes"); empty plots show nothing.
local function refreshLikeText(plot: Instance)
	local prompt = likePromptOf(plot)
	if prompt == nil then
		return
	end
	local owner = Players:GetPlayerByUserId(plot:GetAttribute("OwnerUserId") or 0)
	local received = owner and DataService.GetValue(owner, "likes.received")
	prompt.ObjectText = if type(received) == "number" then `❤️ {received} like{received == 1 and "" or "s"}` else ""
end

function ShopSocialService.Like(giver: Player, plot: Instance, now: number?): (boolean, string?)
	local owner = Players:GetPlayerByUserId(plot:GetAttribute("OwnerUserId") or 0)
	if owner == nil then
		return false, "noOwner"
	end
	if not (DataService.IsLoaded(giver) and DataService.IsLoaded(owner)) then
		return false, "notLoaded"
	end
	local ok, reason, giverLikes, ownerLikes, cash = ShopSocialService._decideLike(
		giver.UserId,
		owner.UserId,
		DataService.GetValue(giver, "likes"),
		DataService.GetValue(owner, "likes"),
		now
	)
	if not ok then
		if reason == "alreadyLiked" then
			notify(giver, `You already liked {owner.DisplayName}'s shop today ❤️`)
		end
		return false, reason
	end
	-- Whole `likes` tables are written at once so a day change resets every field together.
	DataService.Set(giver, "likes", giverLikes)
	DataService.Set(owner, "likes", ownerLikes)
	if cash > 0 then
		EconomyService.AddCash(owner, cash, "Like")
		notify(owner, `{giver.DisplayName} liked your shop! ❤️ +${cash}`)
	else
		notify(owner, `{giver.DisplayName} liked your shop! ❤️`)
	end
	notify(giver, `You liked {owner.DisplayName}'s shop ❤️`)
	refreshLikeText(plot)
	log.info(giver.Name, "liked", owner.Name, `(total {ownerLikes.received}, cash {cash})`)
	return true
end

local function hookLikePrompt(plot: Instance)
	local prompt = likePromptOf(plot)
	if prompt == nil then
		log.warn(plot.Name, "has no Counter.LikePrompt")
		return
	end
	prompt.Triggered:Connect(function(giver: Player)
		if not Validate.rateLimit(giver, "LikeShop", 1) then
			return
		end
		ShopSocialService.Like(giver, plot)
	end)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshLikeText(plot)
	end)
	refreshLikeText(plot)
end

function ShopSocialService.Init(services)
	PlotService = services.PlotService
	RestorationService = services.RestorationService
	DataService = services.DataService
	EconomyService = services.EconomyService
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
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			hookLikePrompt(plot)
		end
	else
		log.warn("Workspace.Plots not found: likes are off")
	end
	log.info("Start")
end

return ShopSocialService
