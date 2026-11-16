-- RestorationController.luau
-- Purpose: the restoration STEP RUNNER on the client: starts a session at the bench, runs the minigame for the current
-- step, reports it to the server, follows the saved step to the next one, and handles Exit. The server decides everything
-- (docs/Restoration_Contract.md); this file only plays the steps and reports them.
-- Owner: Dev 2 (Dwayne); first version written by Dev 1 (Ace) so the loop is playable by hand. Depends on: Shared.Remotes,
-- Shared.Config.Economy (MinStepSeconds), ClientState, RestorationUIController (chips, hint, progress bar, finish card).
--
-- MINIGAMES PLUG IN HERE (Dwayne): RestorationController.RegisterMinigame(stepType, function(ctx) ... return cleanup end)
--   ctx = { uid, stepIndex, step, seed, sessionId, setProgress(0..1), complete(score 0-100) }
--   call ctx.complete(100) once when the step is finished; return a cleanup function that removes your UI / connections.
-- A step type with no registered minigame uses the PLACEHOLDER below (hold a button until the bar is full).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Economy = require(Shared.Config:WaitForChild("Economy"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local RestorationController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}

type Session = { uid: string, recipe: { { [string]: any } }, stepIndex: number, sessionId: number?, seed: number? }
local session: Session? = nil
local cleanup: (() -> ())? = nil
local minigames: { [string]: (any) -> (() -> ())? } = {}

local function log(...)
	if DEBUG then
		print("[RestorationController]", ...)
	end
end

local function ui()
	return others.RestorationUIController
end

local function stopStep()
	if cleanup then
		local fn = cleanup
		cleanup = nil
		pcall(fn)
	end
end

local function endSession()
	stopStep()
	session = nil
end

-- ===== Placeholder minigame: hold the button until the bar is full (real minigames replace it per step type) =====
local function placeholder(ctx): () -> ()
	local fillSeconds = math.max((Economy.MinStepSeconds[ctx.step.type] or 3) * 1.3, 2.5) -- never faster than the server's minimum
	local gui = Instance.new("ScreenGui")
	gui.Name = "RestorationWork"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.IgnoreGuiInset = true
	local button = Instance.new("TextButton")
	button.Name = "WorkButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.fromScale(0.5, 0.86)
	button.Size = UDim2.fromScale(0.34, 0.13)
	button.BackgroundColor3 = Color3.fromHex("F2784B")
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Font = Enum.Font.FredokaOne
	button.Text = "Hold to work"
	button.AutoButtonColor = false
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.3, 0)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(200, 64)
	limit.MaxSize = Vector2.new(420, 110)
	limit.Parent = button
	gui.Parent = player:WaitForChild("PlayerGui")

	local holding = false
	local progress = 0
	local done = false
	local function isPress(input: InputObject)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	local began = button.InputBegan:Connect(function(input)
		if isPress(input) then
			holding = true
		end
	end)
	local ended = button.InputEnded:Connect(function(input)
		if isPress(input) then
			holding = false
		end
	end)
	local beat = RunService.Heartbeat:Connect(function(dt)
		if done then
			return
		end
		progress = math.clamp(progress + (if holding then dt / fillSeconds else -dt / fillSeconds * 0.4), 0, 1)
		ctx.setProgress(progress)
		button.Text = if holding then "Working..." else "Hold to work"
		button.BackgroundColor3 = if holding then Color3.fromHex("0E7C7B") else Color3.fromHex("F2784B")
		if progress >= 1 then
			done = true
			button.Text = "Done!"
			ctx.complete(100) -- the contract: every step reports 100 for now
		end
	end)
	return function()
		began:Disconnect()
		ended:Disconnect()
		beat:Disconnect()
		gui:Destroy()
	end
end

-- ===== Step runner =====
local function startStep()
	stopStep()
	local current = session
	if current == nil then
		return
	end
	local step = current.recipe[current.stepIndex]
	if type(step) ~= "table" or type(step.type) ~= "string" then
		warn("[RestorationController] bad step", current.stepIndex)
		return
	end
	local reported = false
	local ctx
	ctx = {
		uid = current.uid,
		stepIndex = current.stepIndex,
		step = step,
		seed = current.seed,
		sessionId = current.sessionId,
		setProgress = function(fraction: number)
			local view = ui()
			if view and not reported then
				view.SetProgress(fraction)
			end
		end,
		complete = function(score: number)
			if reported or session ~= current or session == nil or session.stepIndex ~= ctx.stepIndex then
				return -- one report per step, and only for the step that is still current
			end
			reported = true
			local view = ui()
			if view then
				view.SetProgress(1)
			end
			Remotes.ReportStepComplete:FireServer(ctx.uid, ctx.stepIndex, score, ctx.sessionId)
			log(`reported {ctx.uid} step {ctx.stepIndex} ({step.type}) score {score}`)
		end,
	}
	local runner = minigames[step.type] or placeholder
	local ok, result = pcall(runner, ctx)
	if ok and type(result) == "function" then
		cleanup = result
	elseif not ok then
		warn("[RestorationController] minigame for " .. step.type .. " failed: " .. tostring(result))
	end
	log(`step {current.stepIndex}/{#current.recipe}: {step.type}{if minigames[step.type] then "" else " (placeholder)"}`)
end

local function onSession(uid: any, recipe: any, stepIndex: any, seed: any, sessionId: any)
	if type(uid) ~= "string" or type(recipe) ~= "table" or type(stepIndex) ~= "number" then
		return
	end
	session = { uid = uid, recipe = recipe, stepIndex = stepIndex, sessionId = sessionId, seed = seed }
	startStep() -- also after a rejection: the server resends the session and the step starts clean
end

-- An accepted step has no message of its own: the server saves item.stepIndex, which arrives through ClientState.
local function onInventoryChanged()
	local current = session
	if current == nil then
		return
	end
	local item = ClientState.Get("inventory." .. current.uid)
	local saved = type(item) == "table" and item.stepIndex
	if type(saved) == "number" and saved ~= current.stepIndex and saved >= 1 and saved <= #current.recipe and item.state == "InProgress" then
		current.stepIndex = saved
		startStep()
	end
end

-- ===== Public API =====

function RestorationController.RegisterMinigame(stepType: string, runner: (any) -> (() -> ())?)
	minigames[stepType] = runner
end

-- The nearest bench in MY shop (Bench1, or Bench2 once the Back Room exists).
local function nearestBench(): string?
	local plots = workspace:FindFirstChild("Plots")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if plots == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local benches = plot:FindFirstChild("Benches")
			local list = if benches then benches:GetChildren() else {}
			for _, bench in list do
				local position = if bench:IsA("BasePart") then bench.Position elseif bench:IsA("Model") then bench:GetPivot().Position else nil
				if position and (position - root.Position).Magnitude < bestDistance then
					best, bestDistance = bench.Name, (position - root.Position).Magnitude
				end
			end
		end
	end
	return best
end

-- The Restore / Continue button in the Inventory calls this. The server checks the item, the bench and the distance.
function RestorationController.RequestStartRestore(uid: string)
	local bench = nearestBench()
	if bench == nil then
		warn("[RestorationController] no bench found in my shop")
		return
	end
	Remotes.RequestStartRestore:FireServer(uid, bench)
	log("asked to restore", uid, "at", bench)
end

-- The Exit button (RestorationUIController) calls this instead of sending the remote itself.
function RestorationController.Exit()
	local current = session
	if current then
		Remotes.RequestExitRestore:FireServer(current.uid)
	end
	endSession()
end

function RestorationController.Init(others_: { [string]: any })
	others = others_
	log("Init")
end

function RestorationController.Start()
	Remotes.RestoreSession.OnClientEvent:Connect(onSession)
	Remotes.ItemRestored.OnClientEvent:Connect(function()
		endSession()
	end)
	ClientState.OnChanged("inventory", onInventoryChanged)
	log("Start")
end

return RestorationController
