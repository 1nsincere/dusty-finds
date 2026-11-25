-- RestorationService.luau
-- Purpose: the SERVER rules of restoration (docs/01 B8, docs/03 §5/§7, docs/Restoration_Contract.md): start a session,
-- check each reported step (session, order, minimum duration, score 0-100), work out quality stars, finish the item.
-- Owner: Dev 1 (Ace) for these rules (agreed with Dwayne); the minigames and RestorationController are Dev 2 (Dwayne).
-- Depends on: DataService, InventoryService, CollectionBookService, EconomyService, PlotService, Shared.Config, Shared.Formulas.
-- Rejections reach the client through `Notify` (Info text) plus a fresh `RestoreSession` (resync). All of it goes through
-- one function (`reply`), so switching to a dedicated RestoreResult remote later, if the team approves it, is a one-place change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
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
-- `id` is unique per session: the client sends it back so a late message from an old session is dropped.
type Session = { id: number, uid: string, benchName: string, stepIndex: number, stepStartedAt: number, scores: { number } }
local sessions: { [Player]: Session } = {}
local nextSessionId = 0

local BENCHES = { Bench1 = true, Bench2 = true }

-- Player-facing text per rejection reason (shown with Notify "Info").
local REASON_TEXT: { [string]: string } = {
	noItem = "That item isn't in your inventory.",
	notRestorable = "That item can't be restored right now.",
	alreadyRestoring = "Finish or leave your current restoration first.",
	badBench = "That bench doesn't exist.",
	noBackRoom = "You need the Back Room for that bench.",
	tooFar = "Move closer to the bench.",
	saveFailed = "Couldn't save, try that step again.",
	tooFast = "That was too fast, try the step again.",
	wrongStep = "Out of sync, resuming your restoration.",
	staleSession = "Out of sync, resuming your restoration.",
	noSession = "Start the restoration again.",
	wrongItem = "Out of sync, resuming your restoration.",
	badScore = "Out of sync, resuming your restoration.",
}

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

-- The bench Instance a player is restoring at: its "InUse" attribute hides the bench's Restore prompt for everyone
-- (clients read it) and is cleared however the session ends (finished, exit, player left).
local busyBench: { [Player]: Instance } = {}

local function endSession(player: Player)
	sessions[player] = nil
	local bench = busyBench[player]
	if bench then
		busyBench[player] = nil
		if bench.Parent then
			bench:SetAttribute("InUse", nil)
		end
	end
end

local function sendSession(player: Player, session: Session, recipe: any)
	if Validate.isPlayer(player) then
		-- the seed only decides which dirt spots are enabled: cosmetic (docs/03 §5). The session id is the 5th argument.
		Remotes.RestoreSession:FireClient(player, session.uid, recipe, session.stepIndex, math.random(1, 1e6), session.id)
	end
end

-- The ONE place a rejection reaches the client: text, and for an active session a fresh RestoreSession so the
-- minigame can reset to the server's current step.
local function reply(player: Player, ok: boolean, reason: string?)
	if ok or not Validate.isPlayer(player) then
		return
	end
	local text = REASON_TEXT[reason or ""]
	if text then
		Remotes.Notify:FireClient(player, "Info", text)
	end
	local session = sessions[player]
	if session and reason ~= "alreadyRestoring" then
		local item = InventoryService.Get(player, session.uid)
		if item then
			sendSession(player, session, Items[item.itemId].recipe)
		end
	end
end

function RestorationService.GetSession(player: Player): Session?
	return sessions[player]
end

-- Starts or resumes restoring an item. Returns ok, reason, info = { stepIndex, recipe, sessionId }.
-- Reasons: noItem, notRestorable, alreadyRestoring, badBench, noBackRoom, saveFailed.
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
		local saved = InventoryService.Update(player, uid, { state = "InProgress" })
		if not saved then
			return false, "saveFailed", nil
		end
	end
	-- Keep only the scores of steps that are really finished (a failed save could have left one extra).
	local scores = {}
	for i = 1, math.min(#item.stepScores, stepIndex - 1) do
		scores[i] = item.stepScores[i]
	end
	nextSessionId += 1
	local session: Session = {
		id = nextSessionId,
		uid = uid,
		benchName = benchName,
		stepIndex = stepIndex,
		stepStartedAt = now or os.clock(),
		scores = scores,
	}
	sessions[player] = session
	sendSession(player, session, recipe)
	return true, nil, { stepIndex = stepIndex, recipe = recipe, sessionId = session.id }
end

-- Checks one reported step. Returns ok, reason, result. result.finished = true on the last step (then result.stars,
-- result.xp, result.value are set). Reasons: noSession, staleSession, wrongItem, wrongStep, tooFast, badScore, noItem,
-- saveFailed. A failed save changes nothing: the session stays on the same step and nothing is awarded.
function RestorationService.ReportStepComplete(player: Player, uid: string, stepIndex: number, score: number, sessionId: number, now: number?): (boolean, string?, { [string]: any }?)
	local session = sessions[player]
	if session == nil then
		return false, "noSession", nil
	end
	if sessionId ~= session.id then
		return false, "staleSession", nil
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

	-- Work on a copy: the session only changes after the save worked.
	local scores = table.clone(session.scores)
	table.insert(scores, math.clamp(score, 0, 100))

	if session.stepIndex < #recipe then
		-- scores first, then the index: if only the first lands, StartRestore trims the extra score on resume
		local savedScores = InventoryService.Update(player, uid, { stepScores = scores })
		local savedIndex = savedScores and InventoryService.Update(player, uid, { stepIndex = session.stepIndex + 1 })
		if not savedIndex then
			log.warn(`{player.Name}: saving step {session.stepIndex} of {uid} failed`)
			return false, "saveFailed", nil
		end
		session.scores = scores
		session.stepIndex += 1
		session.stepStartedAt = time
		return true, nil, { finished = false, stepIndex = session.stepIndex }
	end

	-- last step: quality, then pay out
	local sum = 0
	for _, s in scores do
		sum += s
	end
	local average = sum / #scores
	local upgrades = DataService.GetValue(player, "upgrades") or {}
	local stars = Formulas.qualityStars(average, toolBonus(upgrades))
	local def = Items[item.itemId]
	local xp = Rarities[def.rarity].xpPerRestore * (if def.tier == 2 then Economy.Tier2XpMult else 1)
	local value = Formulas.sellPrice(item.itemId, stars, item.golden, false)

	-- The item becoming Restored is the one write that must succeed, so it goes LAST: if an earlier write fails the item is
	-- still InProgress, nothing is awarded and the player can repeat the final step.
	local savedDetails = InventoryService.Update(player, uid, { stars = stars, stepScores = scores, stepIndex = #recipe })
	local savedState = savedDetails and InventoryService.Update(player, uid, { state = "Restored" })
	if not savedState then
		log.warn(`{player.Name}: finishing {uid} failed to save`)
		return false, "saveFailed", nil
	end
	endSession(player)

	-- The item is Restored for good (it can't be restored twice), so these are best effort: a failure is logged, never retried.
	local okRecord = pcall(CollectionBookService.RecordRestored, player, item.itemId, stars, item.golden)
	if not okRecord then
		log.warn(`{player.Name}: RecordRestored failed for {item.itemId}`)
	end
	local okXp = pcall(EconomyService.AddXp, player, xp)
	if not okXp then
		log.warn(`{player.Name}: AddXp failed after restoring {item.itemId}`)
	end
	local restored = DataService.GetValue(player, "stats.restored") or 0
	if not DataService.Set(player, "stats.restored", restored + 1) then
		log.warn(`{player.Name}: stats.restored not saved`)
	end

	Analytics.Step(player, Analytics.STEP.RestoredItem)
	Analytics.Event(player, "RestoreFinished", stars, item.itemId)
	if Validate.isPlayer(player) then
		Remotes.ItemRestored:FireClient(player, uid, stars, value)
	end
	return true, nil, { finished = true, stars = stars, xp = xp, value = value, average = average }
end

-- Leaves the bench; progress so far is already saved in the item.
-- Events from one client arrive in order, and saving is not yielding, so a step reported before this exit is already
-- decided (accepted or refused) by the time the exit runs: nothing to wait for.
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
	log.info("Init")
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
			reply(player, false, "tooFar")
			return
		end
		if bench:GetAttribute("InUse") and busyBench[player] ~= bench then
			reply(player, false, "alreadyRestoring")
			return
		end
		local ok, reason = RestorationService.StartRestore(player, uid, benchName)
		if ok then
			busyBench[player] = bench
			bench:SetAttribute("InUse", player.UserId)
		end
		reply(player, ok, reason)
	end)

	Remotes.ReportStepComplete.OnServerEvent:Connect(function(player, uid, stepIndex, score, sessionId)
		if not Validate.rateLimit(player, "ReportStepComplete", 2) or type(uid) ~= "string" then
			return
		end
		local ok, reason = RestorationService.ReportStepComplete(player, uid, stepIndex, score, sessionId)
		reply(player, ok, reason)
	end)

	Remotes.RequestExitRestore.OnServerEvent:Connect(function(player, uid)
		if not Validate.rateLimit(player, "RequestExitRestore", 3) or type(uid) ~= "string" then
			return
		end
		RestorationService.ExitRestore(player, uid)
	end)

	Players.PlayerRemoving:Connect(endSession)
	log.info("Start")
end

return RestorationService
