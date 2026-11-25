-- HudSkinController.luau
-- Purpose: gives windows and toasts the warm walnut look at runtime (base panel skin, fonts, hover/press feedback), then
-- WindowKit adds the Figma window look on top. HUD buttons / rails / plate are HudLayoutController's job (since 2026-11-25).
-- It only restyles: object names, layout and behaviour of the existing UI (Dev 3's StarterGui screens) are untouched, so
-- every controller keeps working.
-- Also offers helpers to other controllers: Panel(frame), Button(button), HudButton(name, iconId) -> new left-column button.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.UiSkin, HudKit, WindowKit, PlayerGui screens (HUD, Toasts, *.Window).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit"))
local WindowKit = require(script.Parent.Parent:WaitForChild("WindowKit"))

local HudSkinController = {}
local DEBUG = true
local C = Skin.COLORS

local function log(...)
	if DEBUG then
		print("[HudSkinController]", ...)
	end
end

local function child(parent: Instance, class: string, name: string): any
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(class) then
		return existing
	end
	local inst = Instance.new(class)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function setFont(obj: Instance, font: Font)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		obj.FontFace = font
	end
end

-- Dark gradient panel with a thin bright edge and small corners.
function HudSkinController.Panel(frame: GuiObject, accentEdge: boolean?)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = C.panelTransparency
	local grad = child(frame, "UIGradient", "SkinGradient")
	grad.Color = ColorSequence.new(C.panelTop, C.panelBottom)
	grad.Rotation = 90
	for _, g in frame:GetChildren() do -- an older gradient would fight ours
		if g:IsA("UIGradient") and g ~= grad then
			g:Destroy()
		end
	end
	local corner = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, Skin.CORNER)
	local stroke = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", frame)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if accentEdge then C.accent else C.edge
	stroke.Transparency = if accentEdge then 0.25 else C.edgeTransparency
	stroke.Thickness = 1.5
end

-- Hover = accent edge, press = quick squash.
function HudSkinController.Button(button: GuiButton)
	if button:GetAttribute("Skinned") then
		return
	end
	button:SetAttribute("Skinned", true)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local scale = child(button, "UIScale", "PressScale")
	button.MouseEnter:Connect(function()
		if stroke then
			stroke.Color, stroke.Transparency = C.accent, 0.15
		end
	end)
	button.MouseLeave:Connect(function()
		if stroke then
			-- WindowKit buttons keep their ink border: it stores the resting stroke in these attributes
			stroke.Color = stroke:GetAttribute("DfBaseColor") or C.edge
			stroke.Transparency = stroke:GetAttribute("DfBaseTransparency") or C.edgeTransparency
		end
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.88
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- Swap an emoji TextLabel "Icon" for a white glyph image.
local function iconify(button: GuiObject, imageId: string?)
	if not imageId then
		return
	end
	local emoji = button:FindFirstChild("Icon")
	if emoji and emoji:IsA("TextLabel") then
		emoji.TextTransparency = 1
	end
	local img = child(button, "ImageLabel", "Glyph")
	img.BackgroundTransparency = 1
	img.Image = imageId
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(0.66, 0.66)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = button.ZIndex + 1
end


-- A new left-column HUD button (same style as the others). Returns the button; the caller wires Activated.
function HudSkinController.HudButton(name: string, imageId: string, layoutOrder: number?): GuiButton?
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD", 15)
	local column = hud and hud:WaitForChild("LeftButtons", 15)
	if not column then
		return nil
	end
	local existing = column:FindFirstChild(name)
	if existing then
		return existing :: GuiButton
	end
	local template = column:FindFirstChild("Collection") or column:FindFirstChildWhichIsA("GuiButton")
	if not template then
		return nil
	end
	local b = template:Clone() :: GuiButton
	b.Name = name
	b:SetAttribute("Skinned", nil)
	HudKit.Strip(b) -- the template may already wear the Figma tile look: start from a clean button
	for _, c in b:GetChildren() do
		if c:IsA("LocalScript") then
			c:Destroy()
		end
	end
	local highest = 0
	for _, other in column:GetChildren() do
		if other:IsA("GuiObject") then
			highest = math.max(highest, other.LayoutOrder)
		end
	end
	b.LayoutOrder = layoutOrder or highest + 1
	-- HudLayoutController restyles + positions every button that appears in LeftButtons / TopRight (it listens to ChildAdded).
	b.Parent = column
	return b
end

local function skinPill(pill: Frame?, iconId: string?)
	if not pill then
		return
	end
	HudSkinController.Panel(pill)
	iconify(pill, iconId)
	local glyph = pill:FindFirstChild("Glyph")
	local emoji = pill:FindFirstChild("Icon")
	if glyph and emoji then -- keep the glyph where the emoji was
		glyph.AnchorPoint = Vector2.zero
		glyph.Position = emoji.Position
		glyph.Size = emoji.Size
	end
end

local function skinHud(hud: ScreenGui)
	local money = hud:FindFirstChild("MoneyPill")
	skinPill(money, Skin.ICONS.Coin)
	local amount = money and money:FindFirstChild("Amount")
	if amount then
		amount.FontFace = Skin.FONT_NUMBER
		amount.TextColor3 = C.money
	end
	skinPill(hud:FindFirstChild("RatingPill"), nil)
	local xp = hud:FindFirstChild("XPBar")
	if xp then
		HudSkinController.Panel(xp)
		local fill = xp:FindFirstChild("Fill")
		if fill and fill:IsA("Frame") then
			fill.BackgroundColor3 = Color3.new(1, 1, 1)
			local g = child(fill, "UIGradient", "SkinGradient")
			g.Color = ColorSequence.new(C.xpFrom, C.xpTo)
			local fc = fill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", fill)
			fc.CornerRadius = UDim.new(0, Skin.CORNER)
		end
		local level = xp:FindFirstChild("Level")
		if level then
			level.FontFace = Skin.FONT_NUMBER
			level.TextColor3 = C.text
		end
	end
	-- LeftButtons / TopRight (tiles, Menu flyout, rails) are styled and placed by HudLayoutController since 2026-11-25.
end

-- Toasts: dark panel, orange accent bar on the left, bell glyph; Banner (good news) gets the gold edge.
local function skinToast(frame: Frame, good: boolean)
	HudSkinController.Panel(frame, good)
	local bar = child(frame, "Frame", "AccentBar")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = if good then C.money else C.accent
	bar.Size = UDim2.new(0, 4, 1, -8)
	bar.Position = UDim2.fromOffset(4, 4)
	local text = frame:FindFirstChild("Text")
	if text then
		text.FontFace = Skin.FONT_TEXT
		text.TextColor3 = C.text
		text.Position = UDim2.fromOffset(40, text.Position.Y.Offset)
		text.Size = UDim2.new(1, -52, text.Size.Y.Scale, text.Size.Y.Offset)
	end
	local icon = child(frame, "ImageLabel", "Glyph")
	icon.BackgroundTransparency = 1
	icon.Image = Skin.ICONS.Bell
	icon.Size = UDim2.fromOffset(22, 22)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
end

-- Windows (Inventory, Upgrades, Supply, Collection, Settings, Visit, Cashier...): dark panel, sharper fonts, button feel.
local function skinWindow(window: GuiObject)
	if window:GetAttribute("Skinned") then
		return
	end
	window:SetAttribute("Skinned", true)
	HudSkinController.Panel(window)
	for _, d in window:GetDescendants() do
		if d.Name == "Title" or d.Name == "Header" then
			setFont(d, Skin.FONT_TITLE)
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			setFont(d, Skin.FONT_TEXT)
		end
		if d:IsA("UICorner") then
			d.CornerRadius = UDim.new(0, Skin.CORNER)
		end
		if d:IsA("GuiButton") then
			HudSkinController.Button(d)
		end
	end
end

function HudSkinController.Init(_controllers) end

function HudSkinController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	task.spawn(function()
		local hud = playerGui:WaitForChild("HUD", 15)
		if hud then
			skinHud(hud)
		end
		local toasts = playerGui:WaitForChild("Toasts", 15)
		if toasts then
			local template = toasts:FindFirstChild("ToastTemplate")
			if template then
				skinToast(template, false) -- toasts are cloned from this, so they all get the look
			end
			local banner = toasts:FindFirstChild("Banner")
			if banner then
				skinToast(banner, true)
			end
		end
		local function tryWindow(gui: Instance)
			if gui:IsA("ScreenGui") then
				for _, name in { "Window", "Card" } do
					local w = gui:FindFirstChild(name)
					if w and w:IsA("GuiObject") then
						skinWindow(w)
					end
				end
				WindowKit.SkinScreen(gui) -- Figma window look (shell, tabs, buttons, cards); after the base skin so it wins
			end
		end
		for _, gui in playerGui:GetChildren() do
			tryWindow(gui)
		end
		playerGui.ChildAdded:Connect(function(gui)
			task.defer(tryWindow, gui)
		end)
		log("HUD, toasts and windows skinned")
	end)
end

return HudSkinController
