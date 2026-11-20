-- RestorationController.luau
-- Purpose: the restoration STEP RUNNER on the client: starts a session at the bench, runs the minigame for the current
-- step, reports it to the server, follows the saved step to the next one, and handles Exit. The server decides everything
-- (docs/Restoration_Contract.md); this file only plays the steps and reports them.
-- Owner: Dev 2 (Dwayne); first version written by Dev 1 (Ace) so the loop is playable by hand. Depends on: Shared.Remotes,
-- Shared.Config.Economy (MinStepSeconds), ClientState, RestorationUIController (chips, hint, progress bar, finish card).
--
-- MINIGAMES PLUG IN HERE (Dwayne): RestorationController.RegisterMinigame(stepType, function(ctx) ... return cleanup end)
--   ctx = { uid, stepIndex, step, seed, sessionId, benchName, bench (Instance), startedAt, setProgress(0..1), complete(score 0-100) }
--   complete() is safe to call as fast as the player is: the runner holds the report until the server minimum time has passed.
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
local activeBench: string? = nil -- the bench the player asked to restore at (Bench1 / Bench2)
local cleanup: (() -> ())? = nil
local minigames: { [string]: (any) -> (() -> ())? } = {}
local viewProvider: ((any) -> { [string]: any }?)? = nil

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
	activeBench = nil
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
-- The bench Instance of MY shop by name (Dwayne: use ctx.bench for the camera / item clone).
local function findBench(name: string?): Instance?
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil or name == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local benches = plot:FindFirstChild("Benches")
			return benches and benches:FindFirstChild(name)
		end
	end
	return nil
end

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
	local lastFraction = 0
	local sound = others.SoundController -- optional: work loop while progressing, a chime when the step is done
	local ctx
	ctx = {
		uid = current.uid,
		stepIndex = current.stepIndex,
		step = step,
		seed = current.seed,
		sessionId = current.sessionId,
		benchName = activeBench, -- "Bench1" / "Bench2"; nil if the session was resumed without asking from this client
		bench = findBench(activeBench), -- the bench Instance in my shop (nil if not found)
		startedAt = os.clock(),
		setProgress = function(fraction: number)
			local view = ui()
			if view and not reported then
				view.SetProgress(fraction)
			end
			if sound and not reported and fraction > lastFraction then
				sound.Work(step.type)
			end
			lastFraction = math.max(lastFraction, fraction)
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
			if sound then
				sound.Play("stepDone")
			end
			-- The server rejects a step finished faster than Economy.MinStepSeconds. Hold the report back until that time has
			-- passed, so a fast player is never refused: minigames just call complete() whenever they are done.
			local wait = (Economy.MinStepSeconds[step.type] or 0) + 0.25 - (os.clock() - ctx.startedAt)
			local function send()
				if session ~= current or session == nil or session.stepIndex ~= ctx.stepIndex then
					return -- exited or moved on while we waited
				end
				Remotes.ReportStepComplete:FireServer(ctx.uid, ctx.stepIndex, score, ctx.sessionId)
				log(`reported {ctx.uid} step {ctx.stepIndex} ({step.type}) score {score}`)
			end
			if wait > 0 then
				task.delay(wait, send)
			else
				send()
			end
		end,
	}
	-- Optional view (Dwayne's RestorationView): gives the minigame a local item clone and a pointer adapter.
	local viewCleanup: (() -> ())? = nil
	if viewProvider then
		local viewOk, view = pcall(viewProvider, ctx)
		if viewOk and type(view) == "table" then
			ctx.model, ctx.attachPointer, viewCleanup = view.model, view.attachPointer, view.cleanup
		elseif not viewOk then
			warn("[RestorationController] view provider failed: " .. tostring(view))
		end
	end
	local runner = minigames[step.type] or placeholder
	local ok, result = pcall(runner, ctx)
	local stepCleanup = if ok and type(result) == "function" then result else nil
	cleanup = if stepCleanup or viewCleanup then function()
		if stepCleanup then
			pcall(stepCleanup)
		end
		if viewCleanup then
			pcall(viewCleanup)
		end
	end else nil
	if not ok then
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

-- Dwayne's RestorationView registers ONE provider: fn(ctx) -> { model = local item clone, attachPointer = function(minigameObject) -> cleanup, cleanup = function }
-- Minigames that need a model (Scrape, Reassemble, Replace) read ctx.model / ctx.attachPointer; without a provider they use the placeholder.
function RestorationController.SetViewProvider(provider: ((any) -> { [string]: any }?)?)
	viewProvider = provider
end

-- The hold-the-button fallback, so an adapter without its model can still let the player finish the step.
function RestorationController.RunPlaceholder(ctx): () -> ()
	return placeholder(ctx)
end

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
	activeBench = bench
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

-- Bench "Restore" prompts: shown only on benches in MY shop, only while nobody is restoring there (server attribute
-- InUse) and I'm not mid-session. E opens my inventory on the "Needs restoring" tab; picking an item starts restoring.
local function benchPromptLoop()
	local plots = workspace:WaitForChild("Plots", 30)
	if not plots then
		return
	end
	local myId = Players.LocalPlayer.UserId
	local hooked: { [ProximityPrompt]: boolean } = {}
	while true do
		for _, plot in plots:GetChildren() do
			local benches = plot:FindFirstChild("Benches")
			if benches then
				local mine = plot:GetAttribute("OwnerUserId") == myId
				for _, bench in benches:GetChildren() do
					local prompt = bench:FindFirstChild("Prompt")
					if prompt and prompt:IsA("ProximityPrompt") then
						if not hooked[prompt] then
							hooked[prompt] = true
							prompt.Triggered:Connect(function()
								local inventory = others.InventoryController
								if inventory and inventory.Open and session == nil then
									inventory.Open("NeedsRestoring")
								end
							end)
						end
						prompt.Enabled = mine and session == nil and bench:GetAttribute("InUse") == nil
					end
				end
			end
		end
		task.wait(0.3)
	end
end

function RestorationController.Start()
	Remotes.RestoreSession.OnClientEvent:Connect(onSession)
	Remotes.ItemRestored.OnClientEvent:Connect(function()
		endSession()
	end)
	ClientState.OnChanged("inventory", onInventoryChanged)
	task.spawn(benchPromptLoop)
	log("Start")
end

return RestorationController
