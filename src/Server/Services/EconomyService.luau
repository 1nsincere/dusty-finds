-- EconomyService.luau
-- Purpose: the ONLY place cash and XP change: add cash, spend cash, add XP (with level-ups and their cash reward).
-- Owner: Dev 1 (Ace). Depends on: DataService, Shared.Config.Economy, Shared.Formulas.
-- `xp` in the saved data is progress INSIDE the current level (it resets to 0 on level-up), see docs/02 §7.
-- All amounts must be whole numbers >= 0; anything else is refused, so a bug elsewhere can't mint or steal money.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local EconomyService = {}
local DEBUG = true
local log = Log.new("EconomyService", DEBUG)

local DataService = nil

-- Players can leave mid-action, so only fire to real, present players.
local function notify(player: any, kind: string, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, kind, text)
	end
end

function EconomyService.GetCash(player: Player): number?
	return DataService.GetValue(player, "cash")
end

function EconomyService.GetLevel(player: Player): number?
	return DataService.GetValue(player, "level")
end

function EconomyService.CanAfford(player: Player, amount: number): boolean
	local cash = DataService.GetValue(player, "cash")
	return Validate.isInteger(amount, 0) and type(cash) == "number" and cash >= amount
end

-- reason "Sale" also counts towards stats.earned. Returns true if the cash was added.
function EconomyService.AddCash(player: Player, amount: number, reason: string?): boolean
	if not Validate.isInteger(amount, 0) then
		log.warn("AddCash refused: bad amount", tostring(amount))
		return false
	end
	local cash = DataService.GetValue(player, "cash")
	if type(cash) ~= "number" then
		return false
	end
	if not DataService.Set(player, "cash", cash + amount) then
		return false
	end
	if reason == "Sale" and amount > 0 then
		local earned = DataService.GetValue(player, "stats.earned") or 0
		DataService.Set(player, "stats.earned", earned + amount)
	end
	return true
end

-- Takes the cash only if the player has enough. No yielding between the check and the write, so it can't double-spend.
function EconomyService.Spend(player: Player, amount: number): boolean
	if not Validate.isInteger(amount, 0) then
		log.warn("Spend refused: bad amount", tostring(amount))
		return false
	end
	local cash = DataService.GetValue(player, "cash")
	if type(cash) ~= "number" or cash < amount then
		return false
	end
	return DataService.Set(player, "cash", cash - amount)
end

-- Adds XP, levels up as often as needed (up to Economy.MaxLevel) and pays $50 x new level for each level.
-- Returns ok, levelsGained.
function EconomyService.AddXp(player: Player, amount: number): (boolean, number)
	if not Validate.isInteger(amount, 0) then
		log.warn("AddXp refused: bad amount", tostring(amount))
		return false, 0
	end
	local level = DataService.GetValue(player, "level")
	local xp = DataService.GetValue(player, "xp")
	if type(level) ~= "number" or type(xp) ~= "number" then
		return false, 0
	end

	local gained = 0
	if level >= Economy.MaxLevel then
		xp = 0 -- at the cap there is nothing to progress towards
	else
		xp += amount
		while level < Economy.MaxLevel do
			local needed = Formulas.xpToNext(level)
			if xp < needed then
				break
			end
			xp -= needed
			level += 1
			gained += 1
		end
		if level >= Economy.MaxLevel then
			xp = 0
		end
	end

	DataService.Set(player, "xp", xp)
	if gained > 0 then
		DataService.Set(player, "level", level)
		local previous = level - gained
		for newLevel = previous + 1, level do
			EconomyService.AddCash(player, Economy.LevelUpRewardPerLevel * newLevel, "LevelUp")
		end
		notify(player, "LevelUp", `Level {level}!`)
		log.info(`level up -> {level}`)
	end
	return true, gained
end

function EconomyService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function EconomyService.Start()
	log.info("Start (no remotes: other services call this one)")
end

return EconomyService
