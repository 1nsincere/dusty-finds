-- HudSkinController.luau
-- Purpose: gives the HUD, notifications and windows a sleek, dark, angular "shooter HUD" look at runtime: dark gradient
-- panels with a thin bright edge, white glyph icons (instead of emoji), sharper fonts, an orange-gold accent, hover/press
-- feedback, a gradient XP bar and toasts with an accent bar. It only restyles: object names, layout and behaviour of
-- the existing UI (Dev 3's StarterGui screens) are untouched, so every controller keeps working.
-- Also offers helpers to other controllers: Panel(frame), Button(button), HudButton(name, iconId) -> new left-column button.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.UiSkin, PlayerGui screens (HUD, Toasts, *.Window).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))

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
			stroke.Color, stroke.Transparency = C.edge, C.edgeTransparency
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

local function skinHudButton(button: GuiButton)
	HudSkinController.Panel(button)
	if button:IsA("ImageButton") then
		button.Image = ""
	end
	iconify(button, Skin.ICONS[button.Name])
	HudSkinController.Button(button)
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
	b.Parent = column
	skinHudButton(b)
	iconify(b, imageId)
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

-- ===== Left-column drawer: only the important buttons stay out; the rest open from a Menu button =====
local UserInputService = game:GetService("UserInputService")
local PINNED = { Inventory = 1, Travel = 2, Sprint = 3 } -- always visible (Sprint only on touch devices)
local MENU_ORDER = 50
local drawerOpen = false
local menuButton: GuiButton? = nil

local function isPinned(name: string): boolean
	if name == "Sprint" then
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end
	return PINNED[name] ~= nil
end

local function applyDrawer(column: Instance)
	local drawerItems = {}
	for _, b in column:GetChildren() do
		if b:IsA("GuiButton") and b ~= menuButton then
			if isPinned(b.Name) then
				b.LayoutOrder = PINNED[b.Name]
				b.Visible = true
			else
				table.insert(drawerItems, b)
			end
		end
	end
	table.sort(drawerItems, function(a, b)
		local oa, ob = a:GetAttribute("DrawerOrder") or a.LayoutOrder, b:GetAttribute("DrawerOrder") or b.LayoutOrder
		return oa < ob
	end)
	for i, b in drawerItems do
		if b:GetAttribute("DrawerOrder") == nil then
			b:SetAttribute("DrawerOrder", b.LayoutOrder) -- remember the original order once
		end
		b.LayoutOrder = MENU_ORDER + i
		b.Visible = drawerOpen
	end
	if menuButton then
		local glyph = menuButton:FindFirstChild("MenuGlyph")
		if glyph then
			local top, mid, bottom = glyph:FindFirstChild("Bar0"), glyph:FindFirstChild("Bar1"), glyph:FindFirstChild("Bar2")
			if top and mid and bottom then
				-- open: top and bottom bars cross into an X, the middle one hides
				top.Position = if drawerOpen then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.5, 0)
				bottom.Position = if drawerOpen then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.5, 1)
				top.Rotation = if drawerOpen then 45 else 0
				bottom.Rotation = if drawerOpen then -45 else 0
				mid.Visible = not drawerOpen
				top.BackgroundColor3 = if drawerOpen then C.accent else C.text
				bottom.BackgroundColor3 = top.BackgroundColor3
			end
		end
		local stroke = menuButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if drawerOpen then C.accent else C.edge
			stroke.Transparency = if drawerOpen then 0.15 else C.edgeTransparency
		end
	end
end

local function setupDrawer(column: Instance)
	local template = column:FindFirstChild("Collection") or column:FindFirstChildWhichIsA("GuiButton")
	if not template then
		return
	end
	local b = template:Clone() :: GuiButton
	b.Name = "Menu"
	b:SetAttribute("Skinned", nil)
	b:SetAttribute("DrawerOrder", nil)
	for _, c in b:GetChildren() do
		if c.Name == "Glyph" or c.Name == "Icon" then
			c:Destroy()
		end
	end
	b.LayoutOrder = MENU_ORDER
	-- three bars (hamburger) when closed, an X when open; drawn with frames so no font is needed
	local glyph = Instance.new("Frame")
	glyph.Name = "MenuGlyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.5, 0.42)
	glyph.Parent = b
	for i = 0, 2 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = C.text
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, i * 0.5)
		bar.Size = UDim2.new(1, 0, 0, 4)
		Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
		bar.Parent = glyph
	end
	menuButton = b
	b.Parent = column
	HudSkinController.Panel(b)
	HudSkinController.Button(b)
	b.Activated:Connect(function()
		drawerOpen = not drawerOpen
		applyDrawer(column)
	end)
	applyDrawer(column)
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
	for _, columnName in { "LeftButtons", "TopRight" } do
		local column = hud:FindFirstChild(columnName)
		if column then
			for _, b in column:GetChildren() do
				if b:IsA("GuiButton") then
					skinHudButton(b)
				end
			end
			column.ChildAdded:Connect(function(b)
				if b:IsA("GuiButton") and b ~= menuButton then
					task.defer(function()
						skinHudButton(b)
						if columnName == "LeftButtons" then
							-- picking a drawer item closes the drawer again
							b.Activated:Connect(function()
								if drawerOpen and not isPinned(b.Name) then
									drawerOpen = false
									applyDrawer(column)
								end
							end)
							applyDrawer(column)
						end
					end)
				end
			end)
			if columnName == "LeftButtons" then
				for _, b in column:GetChildren() do
					if b:IsA("GuiButton") then
						b.Activated:Connect(function()
							if drawerOpen and not isPinned(b.Name) then
								drawerOpen = false
								applyDrawer(column)
							end
						end)
					end
				end
				setupDrawer(column)
			end
		end
	end
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
