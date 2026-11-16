-- TutorialService.luau (ServerScriptService.Server.Services.TutorialService)
-- Purpose: saves tutorial progress (data.tutorial = { step, done }) when the client reports it with RequestTutorialStep.
-- The client only ASKS; this checks the step against the player's real saved data (Shared.Tutorial), so nobody can
-- mark steps done that they didn't do. Nothing else depends on tutorial data (rewards: none in MVP).
-- Owner: Dev 3 (Sean). Depends on: DataService (Get, Set), Shared.Tutorial, Shared.Remotes (RequestTutorialStep), Lib.Validate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local TutorialService = {}
local DEBUG = true
local log = Log.new("TutorialService", DEBUG)

local DataService = nil

-- stepId: one of Tutorial.Steps ids (that step is really done), "done" (every step done) or "skip" (player chose to skip).
-- Returns ok, reason.
function TutorialService.ReportStep(player: Player, stepId: string): (boolean, string?)
	local data = DataService.Get(player)
	if data == nil then
		return false, "notLoaded"
	end
	local tutorial = type(data.tutorial) == "table" and data.tutorial or { step = 0, done = false }
	if tutorial.done then
		return false, "alreadyDone"
	end

	if stepId == "skip" or stepId == "done" then
		if stepId == "done" and Tutorial.CurrentStep(data) <= #Tutorial.Steps then
			return false, "notFinished"
		end
		DataService.Set(player, "tutorial.done", true)
		log.info(player.Name, "tutorial", stepId == "skip" and "skipped" or "finished")
		return true
	end

	local index = Tutorial.IndexOf(stepId)
	if index == nil then
		return false, "unknownStep"
	end
	if not Tutorial.IsStepDone(stepId, data) then
		return false, "notDone" -- the order rule: a step only counts once the saved data shows it happened
	end
	if index > (tonumber(tutorial.step) or 0) then
		DataService.Set(player, "tutorial.step", index)
		log.info(player.Name, "tutorial step", index, stepId)
	end
	return true
end

function TutorialService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function TutorialService.Start()
	Remotes.RequestTutorialStep.OnServerEvent:Connect(function(player, stepId)
		if not Validate.rateLimit(player, "RequestTutorialStep", 2) or not Validate.isString(stepId, 20) then
			return
		end
		TutorialService.ReportStep(player, stepId)
	end)
	log.info("Start")
end

return TutorialService
