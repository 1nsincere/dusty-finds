-- RestorationMinigamesController.luau
-- Purpose: register Wipe/Polish once with Ace's committed step hook; adapt tested minigames to Sean's feedback.
-- Owner: Dev 2 (Dwayne). Depends on: RestorationController, RestorationUIController, ClientState, Config.Upgrades,
-- and Minigames/{SpotClear,Rub,RestorationView}. Requires the committed SetViewProvider hook (7bb90ad or later).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientState = require(script.Parent.Parent.ClientState)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Minigames = script.Parent.Parent:WaitForChild("Minigames")
local SpotClear = require(Minigames.SpotClear)
local Rub = require(Minigames.Rub)
local RestorationView = require(Minigames.RestorationView)

local Controller = {}
local DEBUG = true
local registered = false
local others
local activeRun
local activeProvider

-- Initial tuning retains the tested movement sample limits; tool upgrades affect work, never server minimum times.
local BASE_SECONDS_PER_SPOT = 1.5
local BASE_TRAVEL = 2

local function multiplier(upgradeId, effectName)
	local level = ClientState.Get("upgrades." .. upgradeId) or 0
	local values = Upgrades[upgradeId].effect[effectName]
	return if level > 0 then values[math.min(level, #values)] or 1 else 1
end

local function run(ctx)
	local token = {}
	activeRun = token
	local stopped, completed = false, false
	local detach, minigame
	local function cleanup()
		if stopped then return end
		stopped = true -- guard callbacks before destroying anything that could fire events
		if detach then detach(); detach = nil end
		if minigame then minigame:Destroy(); minigame = nil end
	end
	local function progress(fraction)
		if not stopped and not completed then ctx.setProgress(fraction) end
	end
	local function complete()
		if stopped or completed then return end
		completed = true
		if detach then detach(); detach = nil end
		ctx.complete(100) -- once; Ace owns the delay and authoritative progression
	end
	local ok, err = pcall(function()
		assert(ctx.model and type(ctx.attachPointer) == "function", "The runner must supply the registered item view")
		local config = table.clone(ctx.step)
		if config.type == "Wipe" then
			config.secondsPerSpot = BASE_SECONDS_PER_SPOT / multiplier("CleaningBrush", "wipeSpeedMult")
			minigame = SpotClear.new(ctx.model, config, progress, complete)
		else
			config.movement = {
				requiredTravel = BASE_TRAVEL / multiplier("Polisher", "polishSpeedMult"),
				minSampleTravel = 0.0005, maxSampleTravel = 0.08, maxCreditPerSample = 0.02,
			}
			minigame = Rub.new(ctx.model, config, progress, complete)
		end
		detach = ctx.attachPointer(minigame)
		assert(type(detach) == "function", "attachPointer must return cleanup")
	end)
	if not ok then
		cleanup()
		-- Defer exit until startStep has received our cleanup; never strand a half-constructed camera or pointer.
		task.defer(function()
			if activeRun ~= token then return end -- a newer resync must not be cancelled by an old setup failure
			others.RestorationController.Exit()
			others.RestorationUIController.Hide()
			if others.HudController and others.HudController.Notify then
				others.HudController.Notify("Info", "Restoration setup failed; see Output.")
			end
		end)
		if DEBUG then warn("[RestorationMinigamesController] " .. tostring(err)) end
	end
	return cleanup
end

function Controller.Init(controllers)
	if registered then return end
	others = controllers
	assert(others.RestorationController and others.RestorationUIController, "Restoration runner/UI are required")
	assert(type(others.RestorationController.SetViewProvider) == "function", "Merge Ace's committed view-provider hook (7bb90ad or later) before enabling adapters")
	others.RestorationController.SetViewProvider(function(ctx)
		local token = {}
		activeProvider = token
		local cancelled = false
		local resources = RestorationView.Provider(ctx, function()
			if cancelled or activeProvider ~= token then return end
			cancelled = true
			-- Use the runner's one Exit path; its cleanup disposes step input and then this view.
			others.RestorationController.Exit()
			others.RestorationUIController.Hide()
		end)
		local release = resources.cleanup
		resources.cleanup = function()
			cancelled = true
			release()
		end
		return resources
	end)
	others.RestorationController.RegisterMinigame("Wipe", run)
	others.RestorationController.RegisterMinigame("Polish", run)
	registered = true
	if DEBUG then print("[RestorationMinigamesController] registered Wipe and Polish") end
end

function Controller.Start()
	if DEBUG then print("[RestorationMinigamesController] Start") end
end

return Controller
