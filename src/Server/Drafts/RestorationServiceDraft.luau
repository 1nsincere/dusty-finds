-- RestorationServiceDraft.luau  (DRAFT by Ace for Dwayne: not loaded by Main, so it changes nothing until you adopt it)
-- Purpose: the SERVER rules of restoration (docs/01 B8, docs/03 §5/§7): start a session, check each reported step
-- (order, minimum duration, score 0-100), work out quality stars, and finish the item.
-- Owner: Dev 2 (Dwayne) decides. Written by Dev 1 (validation is Dev 1's half of B8). Depends on: DataService,
-- InventoryService, CollectionBookService, EconomyService, PlotService, Shared.Config, Shared.Formulas.
-- To adopt: copy the functions you want into Services/RestorationService.luau (or rename this file) and tell Ace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local RestorationService = {}
local DEBUG = true
local log = Log.new("RestorationService", DEBUG)

local DataService, InventoryService, CollectionBookService, EconomyService, PlotService = nil, nil, nil, nil, nil

-- One active session per player (docs/06 U5: one restoration at a time). Held only in memory: progress itself is
-- saved in the item (stepIndex, stepScores) after every step, so leaving mid-restore loses nothing but the current step.
type Session = { uid: string, benchName: string, stepIndex: number, stepStartedAt: number, scores: { number } }
local sessions: { [Player]: Session } = {}

local BENCHES = { Bench1 = true, Bench2 = true }

-- Quality bonus from owned tools: sum of every owned upgrade's qualityBonus (Formulas caps it at 10).
local function toolBonus(upgrades: { [string]: number }): number
	local total = 0
	for id, level in upgrades do
		local def = Upgrades[id]
		local bonus = def and def.effect.qualityBonus
		if level > 0 and type(bonus) == "table" then
			total += bonus[math.min(level, #bonus)] or 0
		end
	end
	return total
end

local function endSession(player: Player)
	sessions[player] = nil
end

function RestorationService.GetSession(player: Player): Session?
	return sessions[player]
end

-- Starts or resumes restoring an item. Returns ok, reason, info = { stepIndex, recipe }.
-- Reasons: noItem, notRestorable, alreadyRestoring, badBench, noBackRoom.
-- `now` is optional (tests pass a fake clock).
function RestorationService.StartRestore(player: Player, uid: string, benchName: string, now: number?): (boolean, string?, { [string]: any }?)
	local item = InventoryService.Get(player, uid)
	if item == nil then
		return false, "noItem", nil
	end
	if item.state ~= "Dirty" and item.state ~= "InProgress" then
		return false, "notRestorable", nil
	end
	if sessions[player] ~= nil then
		return false, "alreadyRestoring", nil
	end
	if type(benchName) ~= "string" or not BENCHES[benchName] then
		return false, "badBench", nil
	end
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	if benchName == "Bench2" and (upgrades.BackRoom or 0) < 1 then
		return false, "noBackRoom", nil
	end

	local recipe = Items[item.itemId].recipe
	local stepIndex = math.clamp(item.stepIndex, 1, #recipe)
	if item.state == "Dirty" then
		InventoryService.Update(player, uid, { state = "InProgress" })
	end
	sessions[player] = {
		uid = uid,
		benchName = benchName,
		stepIndex = stepIndex,
		stepStartedAt = now or os.clock(),
		scores = table.clone(item.stepScores),
	}

	if Validate.isPlayer(player) then
		-- the seed only decides which dirt spots are enabled: cosmetic (docs/03 §5)
		Remotes.RestoreSession:FireClient(player, uid, recipe, stepIndex, math.random(1, 1e6))
	end
	return true, nil, { stepIndex = stepIndex, recipe = recipe }
end

-- Checks one reported step. Returns ok, reason, result. result.finished = true on the last step (then result.stars,
-- result.xp, result.value are set). Reasons: noSession, wrongItem, wrongStep, tooFast, badScore.
function RestorationService.ReportStepComplete(player: Player, uid: string, stepIndex: number, score: number, now: number?): (boolean, string?, { [string]: any }?)
	local session = sessions[player]
	if session == nil then
		return false, "noSession", nil
	end
	if session.uid ~= uid then
		return false, "wrongItem", nil
	end
	if not Validate.isInteger(stepIndex) or stepIndex ~= session.stepIndex then
		return false, "wrongStep", nil
	end
	if not Validate.isNumber(score) then
		return false, "badScore", nil
	end
	local item = InventoryService.Get(player, uid)
	if item == nil then
		endSession(player)
		return false, "noItem", nil
	end
	local recipe = Items[item.itemId].recipe
	local step = recipe[session.stepIndex]
	local time = now or os.clock()
	if time - session.stepStartedAt < (Economy.MinStepSeconds[step.type] or 0) then
		log.warn(`{player.Name} reported {step.type} in {string.format("%.1f", time - session.stepStartedAt)}s: too fast`)
		return false, "tooFast", nil
	end

	table.insert(session.scores, math.clamp(score, 0, 100))

	if session.stepIndex < #recipe then
		session.stepIndex += 1
		session.stepStartedAt = time
		InventoryService.Update(player, uid, { stepIndex = session.stepIndex, stepScores = session.scores })
		return true, nil, { finished = false, stepIndex = session.stepIndex }
	end

	-- last step: quality, then pay out
	local sum = 0
	for _, s in session.scores do
		sum += s
	end
	local average = sum / #session.scores
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	local stars = Formulas.qualityStars(average, toolBonus(upgrades))
	local def = Items[item.itemId]
	local xp = Rarities[def.rarity].xpPerRestore * (if def.tier == 2 then Economy.Tier2XpMult else 1)
	local value = Formulas.sellPrice(item.itemId, stars, item.golden, false)

	InventoryService.Update(player, uid, { state = "Restored", stars = stars, stepScores = session.scores, stepIndex = #recipe })
	CollectionBookService.RecordRestored(player, item.itemId, stars, item.golden)
	EconomyService.AddXp(player, xp)
	local restored = DataService.GetValue(player, "stats.restored") or 0
	DataService.Set(player, "stats.restored", restored + 1)
	endSession(player)

	if Validate.isPlayer(player) then
		Remotes.ItemRestored:FireClient(player, uid, stars, value)
	end
	return true, nil, { finished = true, stars = stars, xp = xp, value = value, average = average }
end

-- Leaves the bench; progress so far is already saved in the item.
function RestorationService.ExitRestore(player: Player, uid: string): boolean
	local session = sessions[player]
	if session == nil or session.uid ~= uid then
		return false
	end
	endSession(player)
	return true
end

function RestorationService.Init(services)
	DataService = services.DataService
	InventoryService = services.InventoryService
	CollectionBookService = services.CollectionBookService
	EconomyService = services.EconomyService
	PlotService = services.PlotService
	log.info("Init (draft)")
end

function RestorationService.Start()
	Remotes.RequestStartRestore.OnServerEvent:Connect(function(player, uid, benchName)
		if not Validate.rateLimit(player, "RequestStartRestore", 3) or type(uid) ~= "string" or type(benchName) ~= "string" then
			return
		end
		-- the bench must be in the player's own plot and close by
		local plot = PlotService.GetPlot(player)
		local benches = plot and plot:FindFirstChild("Benches")
		local bench = benches and benches:FindFirstChild(benchName)
		if bench == nil or not Validate.withinDistance(player, bench, Economy.InteractMaxStuds) then
			return
		end
		RestorationService.StartRestore(player, uid, benchName)
	end)

	Remotes.ReportStepComplete.OnServerEvent:Connect(function(player, uid, stepIndex, score)
		if not Validate.rateLimit(player, "ReportStepComplete", 2) or type(uid) ~= "string" then
			return
		end
		RestorationService.ReportStepComplete(player, uid, stepIndex, score)
	end)

	Remotes.RequestExitRestore.OnServerEvent:Connect(function(player, uid)
		if not Validate.rateLimit(player, "RequestExitRestore", 3) or type(uid) ~= "string" then
			return
		end
		RestorationService.ExitRestore(player, uid)
	end)

	game:GetService("Players").PlayerRemoving:Connect(endSession)
	log.info("Start (draft)")
end

return RestorationService
