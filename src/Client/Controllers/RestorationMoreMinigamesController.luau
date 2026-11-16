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

-- ===== Model minigames: need ctx.model and ctx.attachPointer from the RestorationView =====
local function runWithModel(Game)
	return function(ctx)
		if ctx.model == nil or type(ctx.attachPointer) ~= "function" then
			log(`{ctx.step.type}: no item view yet, using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local ok, game_ = pcall(Game.new, ctx.model, ctx.step, function(fraction)
			ctx.setProgress(fraction)
		end, function(score)
			ctx.complete(score)
		end)
		if not ok then
			warn(`[RestorationMoreMinigames] {ctx.step.type} could not start ({tostring(game_)}), using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local detach = ctx.attachPointer(game_)
		return function()
			if type(detach) == "function" then
				pcall(detach)
			end
			game_:Destroy()
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
	controller.RegisterMinigame("Reassemble", runWithModel(ReassembleGame))
	controller.RegisterMinigame("Replace", runWithModel(ReplaceGame))
	log("registered Test, Scrape, Reassemble, Replace")
end

return RestorationMoreMinigamesController
