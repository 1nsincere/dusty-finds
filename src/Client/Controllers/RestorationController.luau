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
local Items = require(Shared.Config:WaitForChild("Items"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local RestorationController = {}
local DEBUG = true

local player = Players.LocalPlayer
local others: { [string]: any } = {}

type Session = { uid: string, recipe: { { [string]: any } }, stepIndex: number, sessionId: number?, seed: number?, provisional: boolean? }
local requestedAt = 0 -- when the player pressed Restore (for the "how long did it take" log)
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

-- when the previous step's report is (or was) sent: the server starts timing the next step from its acceptance
local lastReportAt = 0

-- how long a restoration that started before the server answered may wait for that answer
local PROVISIONAL_SECONDS = 5

-- seconds the finished step stays on screen (chime, full bar) before the next one starts
local ADVANCE_DELAY = 0.45

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

-- ONE bench view per restoration session: built at the first step and reused for every next step (prepare()), so the
-- item keeps what earlier steps did and the camera never jumps out between steps. Rebuilt only for a new session.
local sessionView: { uid: string, view: { [string]: any } }? = nil

local function dropView()
	local v = sessionView
	sessionView = nil
	if v and type(v.view.cleanup) == "function" then
		pcall(v.view.cleanup)
	end
end

local function endSession()
	stopStep()
	dropView()
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
			-- The server times a step from the moment it ACCEPTED the previous report, not from when this client started it (the client
			-- now moves on early, see ADVANCE_DELAY). So count from the later of the two, with room for the round trip, or a quick step
			-- would be refused as "too fast", the session re-sent, and the player made to do the step again.
			local nowT = os.clock()
			local wait = (Economy.MinStepSeconds[step.type] or 0) + 0.45 - (nowT - math.max(ctx.startedAt, lastReportAt))
			lastReportAt = nowT + math.max(wait, 0)
			local function send()
				if session ~= current or session == nil then
					return -- exited while we waited (moving on to the next step does NOT cancel this report)
				end
				Remotes.ReportStepComplete:FireServer(ctx.uid, ctx.stepIndex, score, (session :: Session).sessionId or ctx.sessionId) -- the live id: a step started before the server confirmed has none yet
				log(`reported {ctx.uid} step {ctx.stepIndex} ({step.type}) score {score}`)
			end
			if wait > 0 then
				task.delay(wait, send)
			else
				send()
			end
			-- Move on to the next step AT ONCE (after a short beat for the chime and the full bar) instead of waiting for the held-back
			-- report and the server's answer: that wait was the "slow, the minigame takes a while to load" feeling. The server still
			-- checks every report in order; if it ever refuses one, it re-sends the session and onSession puts us back where it says.
			-- The last step waits for the server (the Restored card comes from it).
			local doneIndex = ctx.stepIndex
			if doneIndex < #current.recipe then
				task.delay(ADVANCE_DELAY, function()
					if session ~= current or current.stepIndex ~= doneIndex then
						return
					end
					current.stepIndex = doneIndex + 1
					local view = ui()
					if view and view.AdvanceTo then
						view.AdvanceTo(current.stepIndex)
					end
					startStep()
				end)
			end
		end,
	}
	-- Optional view (Dwayne's RestorationView): gives the minigame a local item clone and a pointer adapter.
	if viewProvider then
		local reuse = sessionView ~= nil and sessionView.uid == current.uid and type(sessionView.view.prepare) == "function"
			and sessionView.view.model ~= nil and sessionView.view.model.Parent ~= nil
		if reuse then
			local prepOk, prepErr = pcall(sessionView.view.prepare, ctx)
			if not prepOk then
				warn("[RestorationController] view prepare failed: " .. tostring(prepErr))
			end
		else
			dropView()
			local viewOk, view = pcall(viewProvider, ctx)
			if viewOk and type(view) == "table" then
				sessionView = { uid = current.uid, view = view }
			elseif not viewOk then
				warn("[RestorationController] view provider failed: " .. tostring(view))
			end
		end
		if sessionView then
			ctx.model, ctx.attachPointer = sessionView.view.model, sessionView.view.attachPointer
		end
	end
	local runner = minigames[step.type] or placeholder
	local ok, result = pcall(runner, ctx)
	local stepCleanup = if ok and type(result) == "function" then result else nil
	cleanup = stepCleanup -- the minigame only; the view lives on until the session ends
	if not ok then
		warn("[RestorationController] minigame for " .. step.type .. " failed: " .. tostring(result))
	end
	log(`step {current.stepIndex}/{#current.recipe}: {step.type}{if minigames[step.type] then "" else " (placeholder)"}`)
	if requestedAt > 0 then
		log(string.format("ready %.2f s after you pressed Restore", os.clock() - requestedAt))
		requestedAt = 0
	end
end

local function onSession(uid: any, recipe: any, stepIndex: any, seed: any, sessionId: any)
	if type(uid) ~= "string" or type(recipe) ~= "table" or type(stepIndex) ~= "number" then
		return
	end
	-- The view already started when Restore was pressed (see RequestStartRestore): the server's answer just confirms it. Same item and
	-- step = keep going without restarting the minigame; anything else (a resumed item at another step, a resync) rebuilds as before.
	if session and session.provisional and session.uid == uid and session.stepIndex == stepIndex then
		session.provisional = nil
		session.sessionId = sessionId
		session.seed = seed
		log("server confirmed the session")
		return
	end
	session = { uid = uid, recipe = recipe, stepIndex = stepIndex, sessionId = sessionId, seed = seed }
	lastReportAt = 0 -- a (re)sent session: the server starts timing this step now
	dropView() -- a (re)sent session starts from a clean view rebuilt from saved progress (also after a rejection)
	startStep()
end

-- An accepted step has no message of its own: the server saves item.stepIndex, which arrives through ClientState.
local function onInventoryChanged()
	local current = session
	if current == nil then
		return
	end
	local item = ClientState.Get("inventory." .. current.uid)
	local saved = type(item) == "table" and item.stepIndex
	if type(saved) == "number" and saved > current.stepIndex and saved >= 1 and saved <= #current.recipe and item.state == "InProgress" then
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
	requestedAt = os.clock()
	Remotes.RequestStartRestore:FireServer(uid, bench)
	log("asked to restore", uid, "at", bench)
	-- Start at once instead of waiting for the server's round trip (that wait was the pause after pressing Restore). The item and its
	-- recipe are already known here; the server's RestoreSession confirms a moment later (onSession). If it refuses (too far, bench busy)
	-- its toast arrives and we step back out (see Start); a missing answer ends it after PROVISIONAL_SECONDS.
	local item = ClientState.Get("inventory." .. uid)
	local def = type(item) == "table" and Items[item.itemId] or nil
	local recipe = def and def.recipe
	if session == nil and type(item) == "table" and type(recipe) == "table" and #recipe > 0 and (item.state == "Dirty" or item.state == "InProgress") then
		local index = if item.state == "InProgress" and type(item.stepIndex) == "number" then math.clamp(item.stepIndex, 1, #recipe) else 1
		session = { uid = uid, recipe = recipe, stepIndex = index, sessionId = nil, seed = math.random(1, 1000000), provisional = true }
		lastReportAt = 0
		local view = ui()
		if view and view.Begin then
			view.Begin(uid, recipe, index)
		end
		startStep()
		local started = session
		task.delay(PROVISIONAL_SECONDS, function()
			if session == started and started.provisional then
				warn("[RestorationController] the server never confirmed the restoration: leaving it")
				endSession()
			end
		end)
	end
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
	-- the server refused (too far, bench in use...): its toast comes instead of a session, so back out of the provisional one
	Remotes.Notify.OnClientEvent:Connect(function(kind)
		if session and session.provisional and kind == "Info" then
			endSession()
			local view = ui()
			if view and view.Hide then
				view.Hide()
			end
		end
	end)
	Remotes.ItemRestored.OnClientEvent:Connect(function()
		endSession()
	end)
	ClientState.OnChanged("inventory", onInventoryChanged)
	task.spawn(benchPromptLoop)
	log("Start")
end

return RestorationController
