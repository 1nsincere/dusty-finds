-- TutorialController.luau (StarterPlayerScripts.Client.Controllers.TutorialController)
-- Purpose: the first-2-minutes tutorial: one short hint at a time plus a bouncing arrow over where to go.
-- The step shown is always the first one not done yet in my saved data (Shared.Tutorial), so it moves on by itself
-- when I really open, restore, display or sell, and a returning player resumes where they left off.
-- Owner: Dev 3 (Sean). Depends on: Shared.Tutorial, Shared.Remotes (RequestTutorialStep), ClientState (inventory,
-- collection, stats, tutorial, settings), StarterGui.Tutorial (Hint → Text, SkipButton), Workspace.Plots (my plot:
-- DeliveryPoint, Benches/Bench1, DisplaySlots, Counter), HUD.LeftButtons.Upgrades, Restoration.Hint (hide while restoring).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local TutorialController = {}
local DEBUG = true

local LOCAL_PLAYER = Players.LocalPlayer
local FINISH_SECONDS = 6
local ARROW_HEIGHT = 4 -- studs above the target
local ARROW_BOUNCE = 1 -- studs up and down

local gui: ScreenGui? = nil
local myPlot: Instance? = nil
local arrow: BillboardGui? = nil
local arrowTween: Tween? = nil
local reported = 0 -- highest step index already sent to the server this session
local finishing = false
local finished = false -- done or skipped (this session); the saved tutorial.done covers later sessions
local restoring = false

local function log(...)
	if DEBUG then
		print("[TutorialController]", ...)
	end
end

local function myData()
	return {
		inventory = ClientState.Get("inventory"),
		collection = ClientState.Get("collection"),
		stats = ClientState.Get("stats"),
	}
end

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

-- ===== Arrow =====

local function partOf(instance: Instance?): BasePart?
	if instance == nil then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function firstEmptyShelf(plot: Instance): BasePart?
	local slots = plot:FindFirstChild("DisplaySlots")
	local best: BasePart? = nil
	local bestIndex = math.huge
	for _, slot in (slots and slots:GetChildren() or {}) do
		if slot:IsA("BasePart") and slot:GetAttribute("Enabled") ~= false and slot:GetAttribute("ItemId") == nil then
			local index = tonumber(slot:GetAttribute("SlotIndex")) or tonumber(string.match(slot.Name, "%d+")) or 99
			if index < bestIndex then
				best, bestIndex = slot, index
			end
		end
	end
	return best
end

local function targetPart(target: string): BasePart?
	local plot = myPlot
	if plot == nil then
		return nil
	end
	if target == "DeliveryPoint" then
		return partOf(plot:FindFirstChild("DeliveryPoint"))
	elseif target == "Bench" then
		local benches = plot:FindFirstChild("Benches")
		return partOf(benches and (benches:FindFirstChild("Bench1") or benches:FindFirstChildWhichIsA("Instance")))
	elseif target == "EmptyShelf" then
		return firstEmptyShelf(plot)
	elseif target == "Counter" then
		return partOf(plot:FindFirstChild("Counter"))
	end
	return nil
end

local function hideArrow()
	if arrowTween then
		arrowTween:Cancel()
		arrowTween = nil
	end
	if arrow then
		arrow.Enabled = false
		arrow.Adornee = nil
	end
end

local function showArrow(part: BasePart)
	if arrow == nil then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "TutorialArrow"
		billboard.Size = UDim2.fromOffset(64, 64)
		-- Not AlwaysOnTop: every target is inside my own shop, and an always-on-top arrow did not show in testing.
		billboard.AlwaysOnTop = false
		billboard.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "▼" -- a plain triangle: the ⬇️ emoji drew nothing in a BillboardGui
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = UiTheme.Coral
		label.Parent = billboard
		billboard.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui") -- client-only: never replicates to others
		arrow = billboard
	end
	local billboard = arrow :: BillboardGui
	if billboard.Adornee == part and billboard.Enabled then
		return
	end
	hideArrow()
	billboard.Adornee = part
	billboard.StudsOffsetWorldSpace = Vector3.new(0, ARROW_HEIGHT, 0)
	billboard.Enabled = true
	if not reduceEffects() then
		arrowTween = TweenService:Create(
			billboard,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ StudsOffsetWorldSpace = Vector3.new(0, ARROW_HEIGHT + ARROW_BOUNCE, 0) }
		)
		arrowTween:Play()
	end
end

-- ===== Hint =====

local function setHint(text: string?)
	local screen = gui
	if screen == nil then
		return
	end
	screen.Hint.Visible = text ~= nil and not restoring
	if text then
		screen.Hint.Text.Text = text
	end
end

local function glowUpgradesButton(on: boolean)
	local hud = LOCAL_PLAYER.PlayerGui:FindFirstChild("HUD")
	local button = hud and hud:FindFirstChild("LeftButtons") and hud.LeftButtons:FindFirstChild("Upgrades")
	local stroke = button and button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:SetAttribute("TutorialOldColor", stroke:GetAttribute("TutorialOldColor") or stroke.Color)
		stroke.Color = if on then UiTheme.Coral else stroke:GetAttribute("TutorialOldColor")
		stroke.Thickness = if on then 4 else 2
	end
end

local function stopTutorial()
	finished = true
	finishing = false
	setHint(nil)
	hideArrow()
	glowUpgradesButton(false)
end

-- ===== Steps =====

local function refresh()
	if gui == nil or finished or finishing then
		return
	end
	local saved = ClientState.Get("tutorial")
	if type(saved) == "table" and saved.done == true then
		stopTutorial()
		return
	end
	local data = myData()
	local index = Tutorial.CurrentStep(data)

	-- Tell the server about steps finished since last time (it re-checks them against my real data).
	if index - 1 > reported then
		reported = index - 1
		if reported >= 1 then
			Remotes.RequestTutorialStep:FireServer(Tutorial.Steps[reported].id)
		end
	end

	if index > #Tutorial.Steps then
		-- All done: celebrate briefly, point at Upgrades, then save "done".
		finishing = true
		hideArrow()
		setHint(Tutorial.FinishHint)
		glowUpgradesButton(true)
		log("finished")
		task.delay(FINISH_SECONDS, function()
			Remotes.RequestTutorialStep:FireServer("done")
			stopTutorial()
		end)
		return
	end

	local step = Tutorial.Steps[index]
	setHint(step.hint)
	local part = targetPart(step.target)
	if part and not restoring then
		showArrow(part)
	else
		hideArrow()
	end
end

local function waitForMyPlot(): Instance?
	local plots = workspace:WaitForChild("Plots", 30)
	if plots == nil then
		return nil
	end
	for _ = 1, 60 do
		for _, plot in plots:GetChildren() do
			if plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
				return plot
			end
		end
		task.wait(0.5)
	end
	return nil
end

function TutorialController.Init(_others)
	log("Init")
end

function TutorialController.Start()
	log("Start")
	task.spawn(function()
		local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
		gui = playerGui:WaitForChild("Tutorial", 10) :: ScreenGui?
		if gui == nil then
			warn("[TutorialController] PlayerGui.Tutorial not found: is StarterGui.Tutorial missing?")
			return
		end
		gui.Hint.Visible = false
		gui.Hint.SkipButton.Activated:Connect(function()
			if finished then
				return
			end
			Remotes.RequestTutorialStep:FireServer("skip")
			log("skipped")
			stopTutorial()
		end)

		myPlot = waitForMyPlot()
		if myPlot == nil then
			warn("[TutorialController] no plot is mine: tutorial arrows are off")
		end

		-- The Restoration screen has its own hint in the same spot: step aside while it is open.
		local restorationGui = playerGui:WaitForChild("Restoration", 10)
		local restoreHint = restorationGui and restorationGui:FindFirstChild("Hint")
		if restoreHint and restoreHint:IsA("GuiObject") then
			restoreHint:GetPropertyChangedSignal("Visible"):Connect(function()
				restoring = restoreHint.Visible
				if restoring then
					setHint(nil)
					hideArrow()
				end
				refresh()
			end)
		end

		for _, prefix in { "inventory", "collection", "stats", "tutorial" } do
			ClientState.OnChanged(prefix, refresh)
		end
		-- Shelves fill and empty without my data changing (customers buy): keep the shelf arrow on a free slot.
		local slots = myPlot and myPlot:FindFirstChild("DisplaySlots")
		for _, slot in (slots and slots:GetChildren() or {}) do
			slot:GetAttributeChangedSignal("ItemId"):Connect(refresh)
			slot:GetAttributeChangedSignal("Enabled"):Connect(refresh)
		end
		refresh()
		log("ready, step", Tutorial.CurrentStep(myData()))
	end)
end

return TutorialController
