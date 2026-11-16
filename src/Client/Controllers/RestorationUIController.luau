-- RestorationUIController.luau (StarterPlayerScripts.Client.Controllers.RestorationUIController)
-- Purpose: the Restoration SCREEN only: step chips, hint, progress bar, Exit button and the "Restored!" finish card.
-- It draws what the server says (RestoreSession, the saved item.stepIndex, ItemRestored), so it never decides anything about steps.
-- Owner: Dev 3 (Sean). The minigames, camera and step logic are Dev 2's RestorationController (docs/Restoration_Contract.md).
-- Depends on: Shared.Remotes (RestoreSession, ItemRestored, RequestExitRestore), Shared.Config.Items, ClientState, UiTheme,
-- StarterGui.Restoration (Hint, StepChips → ChipTemplate, Progress → Fill, ExitButton, FinishCard → Title, ItemName, Stars, Value, DoneButton).
-- For Dwayne: RestorationUIController.SetProgress(0..1) and SetHint(text) while a step runs; Hide() if you end the session yourself.
-- If RestorationController has Exit(), the Exit button calls it; otherwise it sends RequestExitRestore itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Config"):WaitForChild("Items"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local RestorationUIController = {}
local DEBUG = true

local LOCAL_PLAYER = Players.LocalPlayer

-- Presentation only: the step types themselves come from each item's Config recipe.
local STEP_ICONS = { Wipe = "🧽", Scrape = "🔧", Reassemble = "🧩", Replace = "🔩", Polish = "✨", Test = "🔔" }
local STEP_HINTS = {
	Wipe = "Wipe away the dirt",
	Scrape = "Scrape off the rust",
	Reassemble = "Put the parts back where they belong",
	Replace = "Pick the right part and fit it",
	Polish = "Polish it until it shines",
	Test = "Test it! Stop in the green",
}
local QUALITY_NAMES = { "Fair", "Good", "Mint" } -- index = stars (docs/01 B8)

local others = nil
local gui: ScreenGui? = nil
local current: { uid: string, recipe: { any }, stepIndex: number, sessionId: number? }? = nil

local function log(...)
	if DEBUG then
		print("[RestorationUIController]", ...)
	end
end

local function itemNameOf(uid: string): string
	local item = ClientState.Get("inventory." .. uid)
	local def = type(item) == "table" and Items[item.itemId]
	return if def then def.name else "Item"
end

local function closeOtherWindows()
	if others == nil then
		return
	end
	for _, name in { "InventoryController", "SettingsController", "CollectionController", "VisitController" } do
		local controller = others[name]
		if controller and controller.Close then
			controller.Close()
		end
	end
	if others.ShopController and others.ShopController.CloseAll then
		others.ShopController.CloseAll()
	end
end

-- ===== Drawing =====

local function drawChips()
	local screen, session = gui, current
	if screen == nil or session == nil then
		return
	end
	local chips = screen.StepChips
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "ChipTemplate" then
			child:Destroy()
		end
	end
	for index, step in session.recipe do
		local stepType = type(step) == "table" and step.type or "?"
		local chip = chips.ChipTemplate:Clone()
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		local done = index < session.stepIndex
		local isCurrent = index == session.stepIndex
		chip.Text = if done then `✔ {stepType}` else `{STEP_ICONS[stepType] or "•"} {stepType}`
		chip.BackgroundColor3 = if done then UiTheme.Teal elseif isCurrent then UiTheme.Coral else UiTheme.Disabled
		chip.Visible = true
		chip.Parent = chips
	end
end

function RestorationUIController.SetProgress(fraction: number)
	local screen = gui
	if screen == nil or type(fraction) ~= "number" then
		return
	end
	screen.Progress.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

function RestorationUIController.SetHint(text: string)
	if gui and type(text) == "string" then
		gui.Hint.Text = text
	end
end

local function setPlayingVisible(visible: boolean)
	local screen = gui
	if screen == nil then
		return
	end
	screen.Hint.Visible = visible
	screen.StepChips.Visible = visible
	screen.Progress.Visible = visible
	screen.ExitButton.Visible = visible
end

function RestorationUIController.IsOpen(): boolean
	return current ~= nil
end

function RestorationUIController.Hide()
	current = nil
	setPlayingVisible(false)
	if gui then
		gui.FinishCard.Visible = false
	end
end

local function drawStep()
	local screen, session = gui, current
	if screen == nil or session == nil then
		return
	end
	local step = session.recipe[session.stepIndex]
	local stepType = type(step) == "table" and step.type or nil
	screen.Hint.Text = `{STEP_ICONS[stepType] or "🛠️"} {STEP_HINTS[stepType] or "Restore the item"}`
	drawChips()
end

-- RestoreSession arrives on start, on resume, and after every rejection (resync): always redraw from it.
local function onSession(uid: any, recipe: any, stepIndex: any, _seed: any, sessionId: any)
	if gui == nil or type(uid) ~= "string" or type(recipe) ~= "table" or type(stepIndex) ~= "number" then
		return
	end
	local stepChanged = current == nil or current.uid ~= uid or current.stepIndex ~= stepIndex
	current = { uid = uid, recipe = recipe, stepIndex = stepIndex, sessionId = sessionId }
	closeOtherWindows()
	gui.FinishCard.Visible = false
	setPlayingVisible(true)
	if stepChanged then
		RestorationUIController.SetProgress(0)
	end
	drawStep()
	log(`session {tostring(sessionId)}: {itemNameOf(uid)} step {stepIndex}/{#recipe}`)
end

-- An ACCEPTED step has no message of its own (the server only answers rejections): it saves item.stepIndex, which
-- reaches us through ClientState. Follow it so the chips move on.
local function onInventoryChanged()
	local session = current
	if session == nil then
		return
	end
	local item = ClientState.Get("inventory." .. session.uid)
	local saved = type(item) == "table" and item.stepIndex
	if type(saved) == "number" and saved ~= session.stepIndex and saved >= 1 and saved <= #session.recipe and item.state == "InProgress" then
		session.stepIndex = saved
		RestorationUIController.SetProgress(0)
		drawStep()
		log("step", saved, "of", #session.recipe)
	end
end

local function onRestored(uid: any, stars: any, value: any)
	local screen = gui
	if screen == nil or type(uid) ~= "string" then
		return
	end
	current = nil
	setPlayingVisible(false)
	local starCount = math.clamp(tonumber(stars) or 1, 1, 3)
	local card = screen.FinishCard
	card.ItemName.Text = itemNameOf(uid)
	card.Stars.Text = string.rep("★", starCount) .. string.rep("☆", 3 - starCount) .. `  {QUALITY_NAMES[starCount]}`
	card.Value.Text = `Worth about {UiTheme.formatCash(tonumber(value) or 0)}`
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	log("restored", uid, starCount, "stars", value)
end

local function onExitTapped()
	local session = current
	if session == nil then
		RestorationUIController.Hide()
		return
	end
	local controller = others and others.RestorationController
	if controller and type(controller.Exit) == "function" then
		controller.Exit()
	else
		Remotes.RequestExitRestore:FireServer(session.uid)
	end
	RestorationUIController.Hide()
	log("exit", session.uid)
end

function RestorationUIController.Init(otherControllers)
	others = otherControllers
	log("Init")
end

function RestorationUIController.Start()
	log("Start")
	task.spawn(function()
		local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
		gui = playerGui:WaitForChild("Restoration", 10) :: ScreenGui?
		if gui == nil then
			warn("[RestorationUIController] PlayerGui.Restoration not found: is StarterGui.Restoration missing?")
			return
		end
		RestorationUIController.Hide()
		gui.ExitButton.Activated:Connect(onExitTapped)
		gui.FinishCard.DoneButton.Activated:Connect(RestorationUIController.Hide)
		Remotes.RestoreSession.OnClientEvent:Connect(onSession)
		Remotes.ItemRestored.OnClientEvent:Connect(onRestored)
		ClientState.OnChanged("inventory", onInventoryChanged)
		log("ready")
	end)
end

return RestorationUIController
