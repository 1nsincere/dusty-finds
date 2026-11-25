-- HudKit.luau (StarterPlayerScripts.Client.HudKit)
-- Purpose: builds the Figma "Main HUD — Final Proposal" pieces in code: chunky tiles (lip, face, bevel, gloss, jewel
-- socket, multicolour icon, sparkle, label) with hover / press motion, menu cells with an optional on/off switch, the
-- status plate (cash, level, stars, XP) and info chips. It only builds and styles; behaviour (what a button does) stays
-- with the controllers. Hover/press motion and the decorative layers switch off with Settings -> Reduce effects.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.UiSkin, ClientState (settings.reduceEffects).
-- All sizes are "reference pixels": the HUD ScreenGui has a UIScale (HudController), so one layout fits phone + desktop.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))

local C = Skin.COLORS

local HudKit = {}

HudKit.TILE_W = 62
HudKit.TILE_H = 64
local LIP = 6 -- px of the darker edge under a tile's face
local EFFECTS_NAMES = { DfGloss = true, DfRim = true, DfSparkle = true, DfSocket = true, DfShade = true }

local HOVER = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function HudKit.Reduced(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

-- ===== small builders =====

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end
HudKit.make = make

local function corner(parent: Instance, radius: number)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function textStroke(label: TextLabel, thickness: number)
	return make("UIStroke", { Color = C.ink, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
end

-- A TextLabel with the game fonts. `font` is one of Skin.FONT_*.
function HudKit.Label(parent: Instance, props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		FontFace = Skin.FONT_TEXT,
		TextColor3 = C.cream,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		BorderSizePixel = 0,
	}
	for key, value in props do
		base[key] = value
	end
	return make("TextLabel", base, parent)
end

-- Layers named Df* that are decorative are tracked so Reduce effects can hide them.
local trackedEffects: { Instance } = {}
local function track(inst: Instance)
	table.insert(trackedEffects, inst)
end

local function applyReducedToAll()
	local reduced = HudKit.Reduced()
	for i = #trackedEffects, 1, -1 do
		local inst = trackedEffects[i]
		if inst.Parent == nil then
			table.remove(trackedEffects, i)
		else
			(inst :: any).Visible = not reduced
		end
	end
end
ClientState.OnChanged("settings", applyReducedToAll)

-- Removes everything an earlier skin added, so a button can be re-skinned (or cloned) cleanly.
function HudKit.Strip(button: GuiObject)
	for _, child in button:GetChildren() do
		if string.sub(child.Name, 1, 2) == "Df" then
			child:Destroy()
		end
	end
end

-- Hides the old Studio / old-skin look of a button without destroying it (other controllers keep their references).
local function hideOldLook(button: GuiButton)
	if button:IsA("ImageButton") then
		button.Image = ""
	end
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.ClipsDescendants = false
	for _, child in button:GetChildren() do
		if string.sub(child.Name, 1, 2) ~= "Df" then
			if child.Name == "Icon" or child.Name == "Glyph" or child.Name == "MenuGlyph" then
				(child :: any).Visible = false
			elseif child:IsA("UIStroke") then
				child.Enabled = false
			elseif child:IsA("UICorner") then
				child.CornerRadius = UDim.new(0, 0)
			elseif child:IsA("UIGradient") then
				child.Enabled = false
			end
		end
	end
end

-- ===== tile =====

-- Restyles an existing ImageButton (or a new one) as a Figma tile. opts: label, art (icon name), face, lip, w, h.
-- Returns the button. The button stays the click target; every layer inside it ignores input.
function HudKit.SkinTile(button: GuiButton, opts: { [string]: any }): GuiButton
	HudKit.Strip(button)
	hideOldLook(button)
	local w = opts.w or HudKit.TILE_W
	local h = opts.h or HudKit.TILE_H
	button.Size = UDim2.fromOffset(w, h)
	local radius = 14
	local faceH = h - LIP - 2

	local shadow = make("Frame", {
		Name = "DfShadow", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, LIP + 3), Size = UDim2.new(1, 0, 1, -(LIP + 3)), ZIndex = 1,
	}, button)
	corner(shadow, radius)
	track(shadow)

	local lip = make("Frame", {
		Name = "DfLip", BackgroundColor3 = opts.lip, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, LIP), Size = UDim2.new(1, 0, 1, -LIP), ZIndex = 2,
	}, button)
	corner(lip, radius)
	stroke(lip, C.ink, 2.5)

	local face = make("Frame", {
		Name = "DfFace", BackgroundColor3 = opts.face, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, faceH), ZIndex = 3,
	}, button)
	corner(face, radius)
	local faceStroke = stroke(face, C.ink, 2.5)
	faceStroke.Name = "DfFaceStroke"

	local shade = make("Frame", {
		Name = "DfShade", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1,
	}, face)
	corner(shade, radius)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(1, 0.8),
		}),
	}, shade)
	track(shade)

	local rim = make("Frame", {
		Name = "DfRim", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 2,
	}, face)
	corner(rim, radius - 2)
	stroke(rim, Color3.new(1, 1, 1), 1.5, 0.55)
	track(rim)

	local gloss = make("Frame", {
		Name = "DfGloss", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.74, BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 5), Size = UDim2.new(1, -12, 0.28, 0), ZIndex = 3,
	}, face)
	corner(gloss, 9)
	track(gloss)

	local iconSize = if h >= 80 then 46 else 33
	local iconTop = 3
	local socketSize = iconSize + 8
	local socket = make("Frame", {
		Name = "DfSocket", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.8,
		BorderSizePixel = 0, Position = UDim2.new(0.5, 0, 0, iconTop + iconSize / 2), Size = UDim2.fromOffset(socketSize, socketSize), ZIndex = 4,
	}, face)
	corner(socket, socketSize)
	stroke(socket, Color3.new(1, 1, 1), 1, 0.72)
	track(socket)

	local baseIconPos = UDim2.new(0.5, 0, 0, iconTop + iconSize / 2)
	local icon = make("ImageLabel", {
		Name = "DfIcon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
		Image = Skin.Art(opts.art), ScaleType = Enum.ScaleType.Fit, Position = baseIconPos,
		Size = UDim2.fromOffset(iconSize, iconSize), ZIndex = 5,
	}, face)

	local sparkle = make("Frame", {
		Name = "DfSparkle", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(1, -11, 0, 11), Size = UDim2.fromOffset(9, 9), ZIndex = 6,
	}, face)
	for _, rot in { 0, 90 } do
		local bar = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.1, BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), Rotation = rot,
		}, sparkle)
		corner(bar, 2)
	end
	track(sparkle)

	local label = HudKit.Label(face, {
		Name = "DfLabel", Text = opts.label, TextSize = 11, Position = UDim2.new(0, 0, 1, -19), Size = UDim2.new(1, 0, 0, 15), ZIndex = 7,
		TextTruncate = Enum.TextTruncate.None,
	})
	textStroke(label, 2.5)

	-- ===== hover / press motion =====
	local hovered, pressed = false, false
	local function refresh()
		local reduced = HudKit.Reduced()
		local faceY = 2
		local iconScale, iconRot, iconDy = 1, 0, 0
		if pressed then
			faceY = LIP
			if not reduced then
				iconScale, iconDy = 0.88, 1
			end
		elseif hovered and not reduced then
			faceY = 0
			iconScale, iconRot, iconDy = 1.12, -9, -3
		end
		if reduced then
			face.Position = UDim2.fromOffset(0, faceY)
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			icon.Rotation = 0
			icon.Position = baseIconPos
			return
		end
		local info = if pressed then PRESS else HOVER
		TweenService:Create(face, info, { Position = UDim2.fromOffset(0, faceY) }):Play()
		TweenService:Create(icon, info, {
			Size = UDim2.fromOffset(iconSize * iconScale, iconSize * iconScale),
			Rotation = iconRot,
			Position = UDim2.new(0.5, 0, 0, iconTop + iconSize / 2 + iconDy),
		}):Play()
		local sparkleSize = if hovered then 13 else 9
		TweenService:Create(sparkle, info, { Size = UDim2.fromOffset(sparkleSize, sparkleSize) }):Play()
	end
	button.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			hovered = true
			refresh()
		end
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		refresh()
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressed = true
			refresh()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressed = false
			refresh()
		end
	end)

	applyReducedToAll()
	button:SetAttribute("DfSkinned", true)
	return button
end

-- Highlights a toggled tile (Sprint on, Menu open): gold outline.
function HudKit.SetActive(button: GuiObject, on: boolean)
	local face = button:FindFirstChild("DfFace")
	local faceStroke = face and face:FindFirstChild("DfFaceStroke")
	if faceStroke then
		faceStroke.Color = if on then C.gold else C.ink
		faceStroke.Thickness = if on then 3.5 else 2.5
	end
end

-- ===== menu cell (2x2 grid in the Menu flyout) =====

HudKit.CELL_W = 84
HudKit.CELL_H = 58

-- opts: label, art, color (medallion), toggle (bool: shows an on/off switch). Existing ImageButton or a new one.
function HudKit.SkinCell(button: GuiButton, opts: { [string]: any }): GuiButton
	HudKit.Strip(button)
	hideOldLook(button)
	local w, h = HudKit.CELL_W, HudKit.CELL_H
	button.Size = UDim2.fromOffset(w, h)

	local lip = make("Frame", {
		Name = "DfLip", BackgroundColor3 = C.ink, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 1, -3), ZIndex = 1,
	}, button)
	corner(lip, 12)
	local surface = make("Frame", {
		Name = "DfSurface", BackgroundColor3 = C.walnutLight, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -3), ZIndex = 2,
	}, button)
	corner(surface, 12)
	stroke(surface, C.ink, 2.5)
	local hoverTint = make("Frame", {
		Name = "DfHover", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1,
	}, surface)
	corner(hoverTint, 12)

	local medSize = 26
	local med = make("Frame", {
		Name = "DfMedallion", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = opts.color, BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(medSize, medSize), ZIndex = 2,
	}, surface)
	corner(med, medSize)
	stroke(med, C.ink, 2.5)
	local icon = make("ImageLabel", {
		Name = "DfIcon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, Image = Skin.Art(opts.art),
		ScaleType = Enum.ScaleType.Fit, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(21, 21), ZIndex = 3,
	}, med)
	HudKit.Label(surface, {
		Name = "DfLabel", Text = opts.label, TextSize = 12, Position = UDim2.new(0, 0, 1, -19), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3,
	})

	if opts.toggle then
		local sw = make("Frame", {
			Name = "DfToggle", BackgroundColor3 = Color3.fromRGB(107, 132, 152), BorderSizePixel = 0,
			Position = UDim2.new(1, -33, 0, 3), Size = UDim2.fromOffset(30, 15), ZIndex = 4,
		}, surface)
		corner(sw, 8)
		stroke(sw, C.ink, 2)
		make("Frame", {
			Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.cream, BorderSizePixel = 0,
			Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(11, 11), ZIndex = 5,
		}, sw)
		corner(sw:FindFirstChild("Knob") :: Frame, 6)
	end

	local hovered = false
	local function refresh(pressed: boolean)
		local reduced = HudKit.Reduced()
		if reduced then
			hoverTint.BackgroundTransparency = if pressed then 0.85 else 1
			icon.Rotation = 0
			return
		end
		TweenService:Create(hoverTint, HOVER, { BackgroundTransparency = if pressed then 0.82 elseif hovered then 0.9 else 1 }):Play()
		TweenService:Create(icon, HOVER, {
			Rotation = if hovered and not pressed then -9 else 0,
			Size = UDim2.fromOffset(if pressed then 18 elseif hovered then 24 else 21, if pressed then 18 elseif hovered then 24 else 21),
		}):Play()
	end
	button.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			hovered = true
			refresh(false)
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		refresh(false)
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			refresh(true)
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			refresh(false)
		end
	end)

	button:SetAttribute("DfSkinned", true)
	return button
end

-- Turns a cell's on/off switch (opts.toggle) on or off.
function HudKit.SetToggle(button: GuiObject, on: boolean)
	local sw = button:FindFirstChild("DfToggle", true)
	if not sw then
		return
	end
	local knob = sw:FindFirstChild("Knob")
	local color = if on then Color3.fromRGB(61, 190, 90) else Color3.fromRGB(107, 132, 152)
	local pos = if on then UDim2.new(1, -13, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
	if HudKit.Reduced() then
		sw.BackgroundColor3 = color
		if knob then
			knob.Position = pos
		end
	else
		TweenService:Create(sw, HOVER, { BackgroundColor3 = color }):Play()
		if knob then
			TweenService:Create(knob, HOVER, { Position = pos }):Play()
		end
	end
end

-- ===== status plate =====

-- Builds the status plate (cash, level, stars, XP) inside `parent`. Returns { Frame, Update }.
-- Update({ cash = string, level = string, progress = number 0-1, xpText = string, stars = number 0-5 })
function HudKit.Plate(parent: Instance): { [string]: any }
	local plate = make("Frame", {
		Name = "StatusPlate", BackgroundColor3 = C.walnut, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(300, 62), ZIndex = 2,
	}, parent)
	corner(plate, 18)
	stroke(plate, C.ink, 3)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(112, 74, 52), Color3.fromRGB(46, 29, 20)),
	}, plate)
	local rim = make("Frame", {
		Name = "DfRim", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 3,
	}, plate)
	corner(rim, 14)
	stroke(rim, C.gold, 1.5, 0.55)
	track(rim)

	make("ImageLabel", {
		Name = "Coin", BackgroundTransparency = 1, Image = Skin.Art("Cash"), ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(10, 17), Size = UDim2.fromOffset(28, 28), ZIndex = 4,
	}, plate)
	local cash = HudKit.Label(plate, {
		Name = "Cash", Text = "$0", FontFace = Skin.FONT_NUMBER, TextColor3 = C.gold, TextSize = 25, TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(44, 12), Size = UDim2.fromOffset(92, 36), ZIndex = 4,
	})
	make("UITextSizeConstraint", { MaxTextSize = 25, MinTextSize = 12 }, cash)
	textStroke(cash, 3)
	make("Frame", { Name = "Divider", BackgroundColor3 = C.ink, BackgroundTransparency = 0.4, BorderSizePixel = 0, Position = UDim2.fromOffset(140, 10), Size = UDim2.fromOffset(2, 42), ZIndex = 4 }, plate)

	local level = HudKit.Label(plate, {
		Name = "Level", Text = "LEVEL 1", FontFace = Skin.FONT_NUMBER, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(152, 5), Size = UDim2.fromOffset(66, 18), ZIndex = 4,
	})
	local stars = {}
	for i = 1, 5 do
		stars[i] = make("ImageLabel", {
			Name = "Star" .. i, BackgroundTransparency = 1, Image = Skin.Art("Star"), ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(204 + (i - 1) * 17, 6), Size = UDim2.fromOffset(15, 15), ZIndex = 4,
		}, plate)
	end

	local xpTrack = make("Frame", {
		Name = "XPTrack", BackgroundColor3 = C.ink, BorderSizePixel = 0, Position = UDim2.fromOffset(152, 28), Size = UDim2.fromOffset(136, 12), ZIndex = 4,
	}, plate)
	corner(xpTrack, 6)
	stroke(xpTrack, C.walnutLight, 2)
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, ClipsDescendants = true, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = 5 }, xpTrack)
	corner(inner, 4)
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 5 }, inner)
	corner(fill, 4)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.xpTo, C.xpFrom) }, fill)
	local gloss = make("Frame", { Name = "DfGloss", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 1), Size = UDim2.new(1, -4, 0.3, 0), ZIndex = 6 }, fill)
	corner(gloss, 3)
	track(gloss)
	local xpText = HudKit.Label(plate, {
		Name = "XPText", Text = "", FontFace = Skin.FONT_TEXT, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(152, 42), Size = UDim2.fromOffset(140, 14), ZIndex = 4,
	})

	local function update(values: { [string]: any })
		if values.cash ~= nil then
			cash.Text = values.cash
		end
		if values.level ~= nil then
			level.Text = values.level
		end
		if values.progress ~= nil then
			local p = math.clamp(values.progress, 0, 1)
			if HudKit.Reduced() then
				fill.Size = UDim2.fromScale(p, 1)
			else
				TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(p, 1) }):Play()
			end
		end
		if values.xpText ~= nil then
			xpText.Text = values.xpText
		end
		if values.stars ~= nil then
			for i = 1, 5 do
				stars[i].ImageTransparency = if i <= values.stars then 0 else 0.72
				stars[i].ImageColor3 = if i <= values.stars then Color3.new(1, 1, 1) else Color3.fromRGB(110, 90, 80)
			end
		end
	end
	update({ stars = 0 })
	applyReducedToAll()
	return { Frame = plate, Update = update }
end

-- ===== info chip =====

-- A pill with an icon, a small line and a big line. opts: art, sub, title, color (fill), clickable (bool).
-- Returns the chip (an ImageButton when clickable, else a Frame) and a setter: chip:SetAttribute-free, use .SetTexts.
function HudKit.Chip(parent: Instance, opts: { [string]: any }): { [string]: any }
	local chip = make(if opts.clickable then "ImageButton" else "Frame", {
		Name = opts.name or "Chip", BackgroundColor3 = opts.color or C.walnut, BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), ZIndex = 2,
	}, parent)
	if opts.clickable then
		chip.AutoButtonColor = false
		chip.Image = ""
	end
	corner(chip, 20)
	stroke(chip, C.ink, 2.5)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 14) }, chip)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chip)
	make("ImageLabel", {
		Name = "Icon", BackgroundTransparency = 1, Image = Skin.Art(opts.art), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, ZIndex = 3,
	}, chip)
	local texts = make("Frame", { Name = "Texts", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 2, ZIndex = 3 }, chip)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, texts)
	local sub = HudKit.Label(texts, {
		Name = "Sub", Text = opts.sub or "", TextSize = 11, TextColor3 = C.gold, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 13),
		LayoutOrder = 1, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local title = HudKit.Label(texts, {
		Name = "Title", Text = opts.title or "", FontFace = Skin.FONT_NUMBER, TextSize = 15, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 18),
		LayoutOrder = 2, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left,
	})
	applyReducedToAll()
	return {
		Frame = chip,
		SetTexts = function(subText: string?, titleText: string?)
			if subText ~= nil then
				sub.Text = subText
			end
			if titleText ~= nil then
				title.Text = titleText
			end
		end,
	}
end

return HudKit
