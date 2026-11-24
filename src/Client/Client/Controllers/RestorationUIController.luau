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
local StarterGui = game:GetService("StarterGui")
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
local STEP_HINTS = {
	Wipe = "Wipe away the dirt",
	Scrape = "Scrape off the rust",
	Reassemble = "Fit the loose parts",
	Replace = "Fit the matching part",
	Polish = "Polish until it shines",
	Test = "Stop in the green",
}
local QUALITY_NAMES = { "FAIR", "GOOD", "MINT" } -- index = stars (docs/01 B8)
local TICKET_PAPER = Color3.fromHex("F8E9D1")
local TICKET_EDGE = Color3.fromHex("DDC398")
local TICKET_INK = Color3.fromHex("28251F")
local TICKET_STAMP = Color3.fromHex("A03B28")
local TICKET_BRASS = "#835609"
local OSWALD_BOLD = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local TITILLIUM_BOLD = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)

local others = nil
local gui: ScreenGui? = nil
local finishing = false
local cardTween: Tween? = nil
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

local function drawChips(screen, recipe, stepIndex, docked)
	local chips = screen.StepChips
	local gap = chips.UIListLayout.Padding.Offset
	local currentWidth = if docked then 104 else 120
	local otherWidth = if docked then 16 else 22
	chips.Size = UDim2.new(0, currentWidth + (#recipe - 1) * (otherWidth + gap), chips.Size.Y.Scale, chips.Size.Y.Offset)
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "ChipTemplate" then
			child:Destroy()
		end
	end
	for index, step in recipe do
		local stepType = type(step) == "table" and step.type or "?"
		local chip = chips.ChipTemplate:Clone()
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		local done = index < stepIndex
		local isCurrent = index == stepIndex
		chip.Text = if isCurrent then `{index}/{#recipe} · {stepType}` elseif done then "✓" else tostring(index)
		chip.Size = UDim2.new(0, if isCurrent then currentWidth else otherWidth, 1, 0)
		chip.BackgroundColor3 = if done then UiTheme.Teal elseif isCurrent then UiTheme.Coral else UiTheme.Disabled
		chip.TextColor3 = if isCurrent then Color3.new(0, 0, 0) else UiTheme.Ink
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
	if current and fraction >= 1 then
		finishing = true
		screen.Hint.Text = "Finishing this step…"
	end
end

function RestorationUIController.SetHint(text: string)
	if gui and not finishing and type(text) == "string" then
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

local function stopCardAnimation()
	if cardTween then
		cardTween:Cancel()
		cardTween = nil
	end
end

function RestorationUIController.Hide()
	stopCardAnimation()
	finishing = false
	current = nil
	setPlayingVisible(false)
	if gui then
		gui.FinishCard.Visible = false
	end
end

function RestorationUIController.DrawStep(screen, recipe, stepIndex)
	local step = recipe[stepIndex]
	local stepType = type(step) == "table" and step.type or nil
	local trayStep = stepType == "Reassemble" or stepType == "Replace"
	local docked = trayStep or stepType == "Test"
	-- Replacement trays include decoys. Keep the stack above the loose parts and below the HUD.
	local stackShift = if stepType == "Replace" then -30 else 0
	local exitOffset = if stepType == "Replace" then -38 else 4
	local template = StarterGui.Restoration
	screen.ExitButton.BackgroundColor3 = UiTheme.Cream
	screen.ExitButton.TextColor3 = UiTheme.Ink
	screen.ExitButton.Position = if docked then UDim2.new(1, -12, 0.5, exitOffset) else template.ExitButton.Position
	for name, offset in { Hint = -74, Progress = -44, StepChips = -36 } do
		local control = screen[name]
		if docked then
			control.AnchorPoint = Vector2.new(1, 0)
			control.Position = UDim2.new(1, -12, 0.5, offset + stackShift)
		else
			control.AnchorPoint = template[name].AnchorPoint
			control.Position = template[name].Position
		end
	end
	screen.Hint.Text = STEP_HINTS[stepType] or "Restore the item"
	drawChips(screen, recipe, stepIndex, docked)
end

-- RestoreSession arrives on start, on resume, and after every rejection (resync): always redraw from it.
local function onSession(uid: any, recipe: any, stepIndex: any, _seed: any, sessionId: any)
	if gui == nil or type(uid) ~= "string" or type(recipe) ~= "table" or type(stepIndex) ~= "number" then
		return
	end
	stopCardAnimation()
	finishing = false
	current = { uid = uid, recipe = recipe, stepIndex = stepIndex, sessionId = sessionId }
	closeOtherWindows()
	gui.FinishCard.Visible = false
	setPlayingVisible(true)
	-- The runner rebuilds its minigame on every server resync, even at the same index.
	RestorationUIController.SetProgress(0)
	RestorationUIController.DrawStep(gui, recipe, stepIndex)
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
		finishing = false
		RestorationUIController.SetProgress(0)
		RestorationUIController.DrawStep(gui, session.recipe, saved)
		log("step", saved, "of", #session.recipe)
	end
end

local function drawFinishCard(card, name: string, starCount: number, value: number)
	-- The centered card needs a shorter footprint to clear the HUD in landscape.
	local compact = card.Parent.AbsoluteSize.Y < 400
	card.Size = if compact then UDim2.fromOffset(300, 174) else UDim2.fromOffset(320, 230)
	card.BackgroundColor3 = TICKET_PAPER
	card.BackgroundTransparency = 0
	card.UICorner.CornerRadius = UDim.new(0, 8)
	card.UIStroke.Color = TICKET_EDGE
	card.UIGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHex("F5F0E7"))

	card.Title.Text = "RESTORED!"
	card.Title.FontFace = OSWALD_BOLD
	card.Title.TextColor3 = TICKET_STAMP
	card.Title.Position = UDim2.fromOffset(16, if compact then 8 else 12)
	card.Title.Size = UDim2.new(1, -32, 0, if compact then 23 else 36)

	local nameLabel = card.ItemName
	nameLabel.Text = name
	nameLabel.FontFace = TITILLIUM_BOLD
	nameLabel.TextColor3 = TICKET_INK
	nameLabel.TextWrapped = true
	nameLabel.TextScaled = true
	nameLabel.Position = UDim2.fromOffset(16, if compact then 32 else 50)
	nameLabel.Size = UDim2.new(1, -32, 0, if compact then 34 else 44)
	local nameSize = nameLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if nameSize then
		nameSize.MaxTextSize = 26
		nameSize.MinTextSize = 16
	end

	local stars = card.Stars
	local symbols = string.rep("★", starCount) .. string.rep("☆", 3 - starCount)
	stars.Position = UDim2.fromOffset(16, if compact then 67 else 96)
	stars.Size = UDim2.new(1, -32, 0, if compact then 21 else 28)
	stars.FontFace = TITILLIUM_BOLD
	stars.TextColor3 = TICKET_INK
	stars.RichText = true
	stars.Text = `<font color="{TICKET_BRASS}">{symbols}</font>  <b>{QUALITY_NAMES[starCount]}</b>`

	card.Value.FontFace = OSWALD_BOLD
	card.Value.TextColor3 = TICKET_INK
	card.Value.Text = `EST. VALUE  {UiTheme.formatCash(value)}`
	card.Value.Position = UDim2.fromOffset(16, if compact then 90 else 126)
	card.Value.Size = UDim2.new(1, -32, 0, if compact then 20 else 24)
	card.DoneButton.FontFace = TITILLIUM_BOLD
end

local function onRestored(uid: any, stars: any, value: any)
	local screen = gui
	if screen == nil or type(uid) ~= "string" then
		return
	end
	current = nil
	finishing = false
	stopCardAnimation()
	setPlayingVisible(false)
	local starCount = math.clamp(tonumber(stars) or 1, 1, 3)
	local card = screen.FinishCard
	-- The ScreenGui already centers the ticket inside CoreUISafeInsets.
	drawFinishCard(card, itemNameOf(uid), starCount, tonumber(value) or 0)
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1
		if ClientState.Get("settings.reduceEffects") ~= true then
			scale.Scale = 0.92
			cardTween = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			cardTween:Play()
		end
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
