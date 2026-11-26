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
-- The guide: what to DO on each step, in plain words (a bold first line, then how). Shown on the left under the step tracker.
local STEP_HINTS = {
	Wipe = "<b>🧽 Wipe it clean</b>\nHold and drag over the dirty spots until they disappear.",
	Scrape = "<b>🔧 Scrape off the rust</b>\nHold and drag over the rusty patches until they flake away.",
	Reassemble = "<b>🧩 Put the pieces back</b>\nTap a loose piece marked PICK ME and it jumps to its spot.",
	Replace = "<b>🔩 Find the right part</b>\nThe missing part is the <b>%PARTS%</b>. Pick it from the tray, then tap the glowing ring.",
	Polish = "<b>✨ Make it shine</b>\nHold and rub over the dull spots until they sparkle.",
	Test = "<b>🎯 Does it work?</b>\nTap when the needle is in the GREEN zone.",
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
local current: { uid: string, recipe: { any }, stepIndex: number, sessionId: number?, provisional: boolean? }? = nil

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

-- ===== The restoring HUD (redesigned 2026-11-25, Figma "Restoration HUD — Redesign") =====
-- One walnut tracker card at the top centre (STEP n OF m, the step name, one pill per step, a gold progress bar), a cream hint chip
-- under it and an Exit button top-left. The pieces stay DIRECT children of StarterGui.Restoration (Hint, StepChips, Progress,
-- ExitButton, FinishCard) because TutorialController, TownTalk and RestorationView look them up by name; this code only restyles
-- and places them, scaled for the screen height so phones get the same layout.
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local HC = Skin.COLORS
local CARD_W, CARD_H, GUIDE_H = 250, 118, 96 -- the left column: tracker card, then the guide under it
local CHIP_GAP = 10
-- Idle nudge: if nothing happens for a few seconds the guide card pulses gold, so a player who is lost looks at it.
local IDLE_PULSE_AFTER = 7
local lastActive = os.clock()
local lastSeenFraction = 0
local pulsing = false

local function clearGradients(object: Instance)
	for _, child in object:GetChildren() do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

local function ensure(parent: Instance, className: string, name: string): Instance
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local function styleBox(box: GuiObject, fill: Color3, radius: number, strokeThickness: number?)
	clearGradients(box)
	box.BackgroundColor3 = fill
	box.BackgroundTransparency = 0
	local corner = box:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = box
	if strokeThickness then
		local stroke = box:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		stroke.Color = HC.ink
		stroke.Thickness = strokeThickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Transparency = 0
		stroke.Parent = box
	end
end

local function hudScale(screen: ScreenGui): number
	return math.clamp(screen.AbsoluteSize.Y / 720, 0.62, 1.1)
end

-- Creates the card and its two labels once, and restyles the template's controls.
local function buildHud(screen: ScreenGui)
	local card = ensure(screen, "Frame", "TrackerCard") :: Frame
	card.AnchorPoint = Vector2.new(0, 0)
	card.ZIndex = 1
	card.BorderSizePixel = 0
	styleBox(card, HC.walnut, 18, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(HC.panelTop, HC.panelBottom)
	gradient.Rotation = 90
	gradient.Parent = card

	for _, spec in { { "StepLabel", HC.accent }, { "StepName", HC.edge } } do
		local label = ensure(screen, "TextLabel", spec[1]) :: TextLabel
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0, 0)
		label.TextColor3 = spec[2]
		label.FontFace = Skin.FONT_TITLE
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = false
		label.ZIndex = 3
	end

	local hint = screen.Hint :: TextLabel
	styleBox(hint, HC.edge, 16, 2.5) -- the guide card
	hint.TextColor3 = HC.ink
	hint.FontFace = Skin.FONT_TITLE
	hint.TextScaled = false
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Center
	hint.TextWrapped = true
	hint.RichText = true
	local hintPad = hint:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	hintPad.PaddingLeft, hintPad.PaddingRight = UDim.new(0, 12), UDim.new(0, 10)
	hintPad.Parent = hint
	hint.ZIndex = 3

	local progress = screen.Progress :: Frame
	styleBox(progress, Color3.fromRGB(26, 15, 8), 5)
	progress.ZIndex = 2
	local fill = progress.Fill :: Frame
	styleBox(fill, HC.accent, 5)
	fill.AnchorPoint = Vector2.new(0, 1) -- the bar is vertical now (right edge of the screen): it fills from the bottom up
	fill.Position = UDim2.fromScale(0, 1)
	fill.ZIndex = 3

	local chips = screen.StepChips :: Frame
	chips.ZIndex = 2
	chips.BackgroundTransparency = 1
	chips.AnchorPoint = Vector2.new(0, 0)
	chips.UIListLayout.Padding = UDim.new(0, CHIP_GAP)
	chips.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chips.UIListLayout.FillDirection = Enum.FillDirection.Horizontal

	local exit = screen.ExitButton :: TextButton
	styleBox(exit, HC.edge, 14, 3)
	exit.TextColor3 = HC.ink
	exit.FontFace = Skin.FONT_TITLE
	exit.TextScaled = false
	exit.Text = "×  Exit"
	exit.AnchorPoint = Vector2.new(0, 0)
	exit.ZIndex = 3
end

-- Places everything for the current screen size (also runs when the screen resizes or rotates).
local function layoutHud(screen: ScreenGui)
	local card = screen:FindFirstChild("TrackerCard") :: Frame?
	if card == nil then
		return
	end
	-- Everything sits in a column on the LEFT so nothing covers the item in the middle (Ace, 2026-11-25).
	local s = hudScale(screen)
	local left = 16 * s
	local cw = CARD_W * s
	local top = 66 * s -- under the Exit button
	card.Position = UDim2.fromOffset(left, top)
	card.Size = UDim2.fromOffset(cw, CARD_H * s)
	local pad = left + 18 * s
	local stepLabel, stepName = screen.StepLabel :: TextLabel, screen.StepName :: TextLabel
	stepLabel.Position = UDim2.fromOffset(pad, top + 10 * s)
	stepLabel.Size = UDim2.fromOffset(cw - 36 * s, 14 * s)
	stepLabel.TextSize = math.max(10, math.floor(11 * s))
	stepName.Position = UDim2.fromOffset(pad, top + 24 * s)
	stepName.Size = UDim2.fromOffset(cw - 36 * s, 28 * s)
	stepName.TextSize = math.max(15, math.floor(22 * s))
	local chips = screen.StepChips :: Frame
	chips.AnchorPoint = Vector2.new(0, 0)
	chips.Position = UDim2.fromOffset(pad, top + 60 * s)
	chips.Size = UDim2.fromOffset(cw - 36 * s, 22 * s)
	local progress = screen.Progress :: Frame
	-- the progress bar: big and vertical on the RIGHT edge, so it never covers the item in the middle (Ace, 2026-11-26)
	local viewHeight = math.max(screen.AbsoluteSize.Y, 360)
	progress.AnchorPoint = Vector2.new(1, 0.5)
	progress.Position = UDim2.new(1, -16 * s, 0.45, 0)
	progress.Size = UDim2.fromOffset(math.max(22, 30 * s), math.floor(viewHeight * 0.4))
	-- the guide: what to do, in plain words, under the tracker
	local hint = screen.Hint :: TextLabel
	hint.AnchorPoint = Vector2.new(0, 0)
	hint.Position = UDim2.fromOffset(left, top + (CARD_H + 10) * s)
	hint.Size = UDim2.fromOffset(cw, GUIDE_H * s)
	hint.TextSize = math.max(13, math.floor(17 * s))
	local exit = screen.ExitButton :: TextButton
	exit.Position = UDim2.fromOffset(left, 16 * s)
	exit.Size = UDim2.fromOffset(92 * s, 40 * s)
	exit.TextSize = math.max(12, math.floor(15 * s))
end

local function drawChips(screen, recipe, stepIndex)
	local chips = screen.StepChips
	local count = #recipe
	for _, child in chips:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "ChipTemplate" then
			child:Destroy()
		end
	end
	for index in recipe do
		local chip = chips.ChipTemplate:Clone()
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		local done = index < stepIndex
		local isCurrent = index == stepIndex
		clearGradients(chip)
		chip.Text = tostring(index) -- done pills are teal (the skin font has no check-mark glyph)
		chip.FontFace = Skin.FONT_TITLE
		chip.TextScaled = false
		chip.TextSize = math.max(10, math.floor(13 * hudScale(screen)))
		-- equal pills that fill the row, whatever the number of steps
		chip.Size = UDim2.new(1 / count, -CHIP_GAP * (count - 1) / count, 1, 0)
		chip.BackgroundColor3 = if done then UiTheme.Teal elseif isCurrent then HC.accent else Color3.fromRGB(90, 70, 58)
		chip.BackgroundTransparency = 0
		chip.TextColor3 = if done or isCurrent then HC.ink else HC.edge
		local corner = chip:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = chip
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if isCurrent then
			stroke = stroke or Instance.new("UIStroke")
			stroke.Color = HC.edge
			stroke.Thickness = 2
			stroke.Parent = chip
		elseif stroke then
			stroke:Destroy()
		end
		chip.Visible = true
		chip.Parent = chips
	end
end

function RestorationUIController.DrawStep(screen, recipe, stepIndex)
	lastActive = os.clock()
	lastSeenFraction = 0
	local step = recipe[stepIndex]
	local stepType = type(step) == "table" and step.type or nil
	local hintText = STEP_HINTS[stepType] or "Restore the item"
	if string.find(hintText, "%PARTS%", 1, true) then
		-- name the missing part(s) so nobody has to guess what to look for
		local names = if type(step) == "table" and type(step.parts) == "table" then string.upper(table.concat(step.parts, " + ")) else "PART"
		hintText = string.gsub(hintText, "%%PARTS%%", names)
	end
	screen.Hint.Text = hintText
	screen.StepLabel.Text = `STEP {stepIndex} OF {#recipe}`
	screen.StepName.Text = string.upper(tostring(stepType or "Restore"))
	layoutHud(screen)
	drawChips(screen, recipe, stepIndex)
end

function RestorationUIController.SetProgress(fraction: number)
	local screen = gui
	if screen == nil or type(fraction) ~= "number" then
		return
	end
	screen.Progress.Fill.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
	if fraction ~= lastSeenFraction then
		lastSeenFraction = fraction
		lastActive = os.clock() -- the player is making progress: no nudge
	end
	if current and fraction >= 1 then
		finishing = true
		screen.Hint.Text = "<b>✅ Nice!</b>\nGetting the next step ready…"
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
	for _, name in { "TrackerCard", "StepLabel", "StepName" } do
		local piece = screen:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Visible = visible
		end
	end
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

-- The screen opens the moment Restore is pressed (RestorationController starts before the server answers); the server's RestoreSession
-- then only confirms it (onSession below). Everything the server decides still wins: see onSession.
function RestorationUIController.Begin(uid: string, recipe: { any }, stepIndex: number)
	if gui == nil then
		return
	end
	stopCardAnimation()
	finishing = false
	current = { uid = uid, recipe = recipe, stepIndex = stepIndex, sessionId = nil, provisional = true }
	closeOtherWindows()
	gui.FinishCard.Visible = false
	setPlayingVisible(true)
	RestorationUIController.SetProgress(0)
	RestorationUIController.DrawStep(gui, recipe, stepIndex)
end

-- RestoreSession arrives on start, on resume, and after every rejection (resync): always redraw from it.
local function onSession(uid: any, recipe: any, stepIndex: any, _seed: any, sessionId: any)
	if gui == nil or type(uid) ~= "string" or type(recipe) ~= "table" or type(stepIndex) ~= "number" then
		return
	end
	if current and current.provisional and current.uid == uid and current.stepIndex == stepIndex then
		current.provisional = nil -- the server confirmed what is already on screen: do not redraw or reset the bar
		current.sessionId = sessionId
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
-- The controller moved on to the next step before the server's answer (RestorationController ADVANCE_DELAY): redraw the screen.
function RestorationUIController.AdvanceTo(stepIndex: number)
	local session = current
	if session == nil or gui == nil or stepIndex < 1 or stepIndex > #session.recipe then
		return
	end
	session.stepIndex = stepIndex
	finishing = false
	RestorationUIController.SetProgress(0)
	RestorationUIController.DrawStep(gui, session.recipe, stepIndex)
end

local function onInventoryChanged()
	local session = current
	if session == nil then
		return
	end
	local item = ClientState.Get("inventory." .. session.uid)
	local saved = type(item) == "table" and item.stepIndex
	if type(saved) == "number" and saved > session.stepIndex and saved >= 1 and saved <= #session.recipe and item.state == "InProgress" then
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
		buildHud(gui)
		-- the idle nudge: pulse the guide card while the player has done nothing for IDLE_PULSE_AFTER seconds
		task.spawn(function()
			while true do
				task.wait(0.7)
				local screen = gui
				local hint = screen and screen:FindFirstChild("Hint")
				if hint and hint:IsA("TextLabel") then
					local idle = current ~= nil and not finishing and screen.Enabled and os.clock() - lastActive > IDLE_PULSE_AFTER
						and ClientState.Get("settings.reduceEffects") ~= true
					if idle then
						pulsing = true
						TweenService:Create(hint, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), { BackgroundColor3 = HC.accent }):Play()
					elseif pulsing then
						pulsing = false
						hint.BackgroundColor3 = HC.edge
					end
				end
			end
		end)
		layoutHud(gui)
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if gui then
				layoutHud(gui)
			end
		end)
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
