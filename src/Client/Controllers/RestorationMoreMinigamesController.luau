-- RestorationMoreMinigamesController.luau
-- Purpose: registers the Test, Scrape, Reassemble and Replace minigames with RestorationController.RegisterMinigame
-- (Wipe and Polish are registered by Dwayne's RestorationMinigamesController: different file on purpose, so we never edit the same one).
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: RestorationController (RegisterMinigame, RunPlaceholder), Client/Minigames/*,
-- Shared.Config.Items (rarity for the Test green zone), ClientState (to find the item being restored).
--
-- Test needs no model: it draws its own bar and works right now.
-- Scrape / Reassemble / Replace need ctx.model (a local clone of Assets/Items/<ItemId>) and ctx.attachPointer(minigameObject) -> cleanup,
-- which Dwayne's RestorationView supplies through RestorationController.SetViewProvider. Without them the step falls back to the
-- hold-the-button placeholder, so the loop never gets stuck.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config:WaitForChild("Items"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Minigames = script.Parent.Parent:WaitForChild("Minigames")
local TestGame = require(Minigames:WaitForChild("Test"))
local ScrapeGame = require(Minigames:WaitForChild("Scrape"))
local ReassembleGame = require(Minigames:WaitForChild("Reassemble"))
local ReplaceGame = require(Minigames:WaitForChild("Replace"))

local RestorationMoreMinigamesController = {}
local DEBUG = true
local player = Players.LocalPlayer
local controller: any = nil

local TEST_LABELS = { Switch = "Flip the switch!", Wind = "Wind it up!", Shake = "Give it a shake!", Play = "Press play!" }

local function log(...)
	if DEBUG then
		print("[RestorationMoreMinigames]", ...)
	end
end

local function rarityOf(uid: string): string?
	local item = ClientState.Get("inventory." .. uid)
	local config = type(item) == "table" and Items[item.itemId] or nil
	return config and config.rarity
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.Parent = parent
	return f
end

-- ===== Test: a bar with a green zone and a sweeping needle; tap to stop =====
local function runTest(ctx)
	local step = table.clone(ctx.step)
	step.rarity = rarityOf(ctx.uid)
	local finished = false
	local game_
	game_ = TestGame.new(nil, step, function(fraction)
		ctx.setProgress(fraction)
	end, function(score)
		finished = true
		ctx.complete(score)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RestorationTest"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.IgnoreGuiInset = true
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.66)
	label.Size = UDim2.fromScale(0.6, 0.07)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("1F2D3A")
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = TEST_LABELS[step.style] or "Does it work?"
	label.Parent = gui
	local bar = frame(gui, "Bar", UDim2.fromScale(0.5, 0.74), UDim2.fromScale(0.6, 0.06), Color3.fromHex("E0524D"))
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)
	local z = game_.zone
	local yellow = frame(bar, "Yellow", UDim2.fromScale(z.yellowFrom, 0), UDim2.fromScale(z.yellowTo - z.yellowFrom, 1), Color3.fromHex("FFD43B"))
	local green = frame(bar, "Green", UDim2.fromScale(z.greenFrom, 0), UDim2.fromScale(z.greenTo - z.greenFrom, 1), Color3.fromHex("3DBE6B"))
	local needle = frame(bar, "Needle", UDim2.fromScale(0, -0.4), UDim2.new(0, 6, 1.8, 0), Color3.fromHex("1F2D3A"))
	needle.AnchorPoint = Vector2.new(0.5, 0)
	local button = Instance.new("TextButton")
	button.Name = "TapButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.fromScale(0.5, 0.79)
	button.Size = UDim2.fromScale(0.3, 0.12)
	button.BackgroundColor3 = Color3.fromHex("F2784B")
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Font = Enum.Font.FredokaOne
	button.Text = "TAP!"
	button.AutoButtonColor = true
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.3, 0)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(180, 64)
	limit.MaxSize = Vector2.new(380, 110)
	limit.Parent = button
	gui.Parent = player:WaitForChild("PlayerGui")
	_ = yellow
	_ = green

	local tapped = button.Activated:Connect(function()
		local result = game_:OnPointerDown(nil)
		if result == "red" then
			label.Text = "Missed! Try again"
		elseif result == "yellow" then
			label.Text = "Good!"
		elseif result == "green" then
			label.Text = "Perfect!"
		end
	end)
	local beat = RunService.Heartbeat:Connect(function(dt)
		game_:Update(dt)
		needle.Position = UDim2.fromScale(game_.needle, -0.4)
		if finished then
			button.Active = false
		end
	end)
	return function()
		tapped:Disconnect()
		beat:Disconnect()
		game_:Destroy()
		gui:Destroy()
	end
end

-- ===== Repair feedback (Reassemble/Replace): what is selected, where it goes, right or wrong =====
local SELECT_COLOR = Color3.fromHex("FFD43B")
local SOCKET_COLOR = Color3.fromHex("5BC0EB")
local WRONG_COLOR = Color3.fromHex("E0524D")

local function burst(part: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(12)
	Debris:AddItem(attachment, 1.2)
end

-- Returns the fx table Socket.luau calls, plus a cleanup. Highlights live in the item view model, so they go with it.
local function repairFx(model: Instance)
	local made: { Instance } = {}
	local selected = Instance.new("Highlight")
	selected.Name = "SelectedPart"
	selected.FillColor = SELECT_COLOR
	selected.OutlineColor = SELECT_COLOR
	selected.FillTransparency = 0.6
	selected.DepthMode = Enum.HighlightDepthMode.Occluded
	selected.Enabled = false
	selected.Parent = model
	table.insert(made, selected)
	local sockets = model:FindFirstChild("Sockets")
	if sockets then -- the empty spots glow so you can see where parts go
		local glow = Instance.new("Highlight")
		glow.Name = "SocketGlow"
		glow.Adornee = sockets
		glow.FillColor = SOCKET_COLOR
		glow.OutlineColor = SOCKET_COLOR
		glow.FillTransparency = 0.5
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
		table.insert(made, glow)
	end
	local fx = {}
	function fx.select(part: Instance)
		selected.Adornee = part
		selected.FillColor, selected.OutlineColor = SELECT_COLOR, SELECT_COLOR
		selected.Enabled = true
	end
	function fx.place(part: Instance, socket: Instance)
		selected.Enabled = false
		if socket:IsA("BasePart") then
			socket.Transparency = 1 -- the ghost is filled now
			socket.CanQuery = false
		end
		if part:IsA("BasePart") then
			task.delay(0.25, function()
				if part.Parent then burst(part) end
			end)
		end
	end
	function fx.wrong(part: Instance, _socket: Instance)
		selected.Adornee = part
		selected.FillColor, selected.OutlineColor = WRONG_COLOR, WRONG_COLOR
		selected.Enabled = true
		task.delay(0.4, function()
			if selected.Parent and selected.FillColor == WRONG_COLOR then selected.Enabled = false end
		end)
	end
	return fx, function()
		for _, instance in made do
			instance:Destroy()
		end
	end
end

-- ===== Model minigames: need ctx.model and ctx.attachPointer from the RestorationView =====
local function runWithModel(Game, withRepairFx: boolean?)
	return function(ctx)
		if ctx.model == nil or type(ctx.attachPointer) ~= "function" then
			log(`{ctx.step.type}: no item view yet, using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local fx, cleanupFx = nil, nil
		if withRepairFx then
			fx, cleanupFx = repairFx(ctx.model)
		end
		local ok, game_ = pcall(Game.new, ctx.model, ctx.step, function(fraction)
			ctx.setProgress(fraction)
		end, function(score)
			ctx.complete(score)
		end, fx)
		if not ok then
			if cleanupFx then cleanupFx() end
			warn(`[RestorationMoreMinigames] {ctx.step.type} could not start ({tostring(game_)}), using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local detach = ctx.attachPointer(game_)
		return function()
			if type(detach) == "function" then
				pcall(detach)
			end
			game_:Destroy()
			if cleanupFx then cleanupFx() end
		end
	end
end

function RestorationMoreMinigamesController.Init(others: { [string]: any })
	controller = others.RestorationController
end

function RestorationMoreMinigamesController.Start()
	if controller == nil or type(controller.RegisterMinigame) ~= "function" then
		warn("[RestorationMoreMinigames] RestorationController.RegisterMinigame not found: nothing registered")
		return
	end
	controller.RegisterMinigame("Test", runTest)
	controller.RegisterMinigame("Scrape", runWithModel(ScrapeGame))
	controller.RegisterMinigame("Reassemble", runWithModel(ReassembleGame, true))
	controller.RegisterMinigame("Replace", runWithModel(ReplaceGame, true))
	log("registered Test, Scrape, Reassemble, Replace")
end

return RestorationMoreMinigamesController
