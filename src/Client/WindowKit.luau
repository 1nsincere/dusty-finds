-- WindowKit.luau (StarterPlayerScripts.Client.WindowKit)
-- Purpose: gives every Studio-authored window (Inventory, Upgrades, Supply, Collection, Settings, Visit) and the code-built
-- Travel window the Figma "Main HUD — Windows" look: walnut shell with a gold rim, a title medallion + icon, a coral close
-- button, pill tabs, chunky buttons, rounded cards, pill labels. It ONLY restyles: object names, layout, text and the colours
-- the controllers set (UiTheme.Teal / Coral / Disabled, rarity strokes) are left alone, so every controller keeps working.
-- Templates (UpgradeTemplate, CrateTemplate, EntryTemplate, ToggleTemplate, RowTemplate, Assets.UI.ItemCard) are styled once;
-- the controllers clone them, so every card inherits the look. The Discovery card is intentionally NOT touched (the unboxing
-- animation is being designed separately).
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.UiSkin, HudKit (make). Called by HudSkinController.Start and TravelController.
-- Figma pieces (Fit, Chunky, Badge, BUTTON; Sean 2026-11-25) are used by the Inventory, Upgrades and Visit controllers,
-- which mark their Window with the DfFigma attribute so this module only draws their shell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))
local HudKit = require(script.Parent:WaitForChild("HudKit"))

local C = Skin.COLORS
local make = HudKit.make

local WindowKit = {}
local DEBUG = true

local function log(...)
	if DEBUG then
		print("[WindowKit]", ...)
	end
end

local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[WindowKit] {label}: {err}`)
	end
end

local function child(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name)
end

local function corner(parent: Instance, radius: number)
	local existing = parent:FindFirstChildOfClass("UICorner")
	if existing then
		existing.CornerRadius = UDim.new(0, radius)
		return existing
	end
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- The border stroke of a frame/button. Reuses the Studio one (so controllers that recolour it keep working).
local function borderStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = parent:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if stroke == nil then
		stroke = make("UIStroke", {}, parent) :: UIStroke
	end
	local s = stroke :: UIStroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0
	s:SetAttribute("DfBaseColor", color) -- HudSkinController.Button restores this after hover
	s:SetAttribute("DfBaseTransparency", 0)
	return s
end

local function textStroke(label: GuiObject, thickness: number)
	if label:FindFirstChild("DfTextStroke") then
		return
	end
	local s = make("UIStroke", { Name = "DfTextStroke", Color = C.ink, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	return s
end

local function setFont(obj: Instance, font: Font)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		obj.FontFace = font
	end
end

-- ===== pieces =====

-- Chunky button: ink border, rounded, Oswald label, a soft bottom shade. Colours come from the controller (BackgroundColor3).
function WindowKit.Button(button: GuiButton, small: boolean?)
	if button:GetAttribute("DfBtn") then
		return
	end
	button:SetAttribute("DfBtn", true)
	setFont(button, Skin.FONT_TITLE)
	button.TextColor3 = C.cream
	corner(button, if small then 10 else 12)
	borderStroke(button, C.ink, 2.5)
	local shade = make("Frame", {
		Name = "DfShade", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = button.ZIndex,
		Active = false,
	}, button)
	corner(shade, if small then 10 else 12)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.78) }),
	}, shade)
	-- the label draws on the button; keep the shade from hiding it
	for _, d in button:GetChildren() do
		if d:IsA("GuiObject") and d ~= shade then
			d.ZIndex = math.max(d.ZIndex, button.ZIndex + 1)
		end
	end
end

-- Pill tab (Inventory All / Needs Restoring / Restored, Upgrades Tools / Shop / Expansions).
function WindowKit.Tab(tab: GuiButton)
	WindowKit.Button(tab, true)
end

-- Rounded card (templates and panels). fill = background colour.
function WindowKit.Card(frame: GuiObject, fill: Color3?, radius: number?)
	frame.BackgroundColor3 = fill or C.walnutLight
	frame.BackgroundTransparency = 0
	corner(frame, radius or 14)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if stroke:GetAttribute("DfBaseColor") == nil then
			stroke:SetAttribute("DfBaseColor", stroke.Color)
			stroke:SetAttribute("DfBaseTransparency", stroke.Transparency)
		end
	else
		borderStroke(frame, C.ink, 2.5)
	end
	for _, d in frame:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local n = d.Name
			if n == "Title" or n == "ItemName" or n == "Name" or n == "PlaceName" or n == "Amount" then
				d.FontFace = Skin.FONT_TITLE
			else
				d.FontFace = Skin.FONT_TEXT
			end
		end
	end
end

-- Dark pill for a label (cash, capacity).
function WindowKit.Pill(label: GuiObject)
	if label:GetAttribute("DfPill") then
		return
	end
	label:SetAttribute("DfPill", true)
	label.BackgroundColor3 = C.ink
	label.BackgroundTransparency = 0
	corner(label, 16)
	borderStroke(label, C.walnutLight, 2.5)
	setFont(label, Skin.FONT_NUMBER)
end

-- ===== Figma "Main HUD — Windows" pieces (Sean, 2026-11-25) =====
-- The design is drawn at 560 x 325 (phone) and 1.4x that on desktop. Windows that use these pieces set the attribute
-- DfFigma on their Window; WindowKit then only draws the shell for them and leaves the content to the controller.

local GuiService = game:GetService("GuiService")

-- Scales a window to the screen like the design: about 1x on a phone, up to 1.4x on a 720 px tall desktop.
function WindowKit.Fit(window: GuiObject, designHeight: number)
	local scale = window:FindFirstChild("DfFit") :: UIScale?
	if scale == nil then
		scale = make("UIScale", { Name = "DfFit" }, window) :: UIScale
	end
	local function apply()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local usable = camera.ViewportSize.Y - GuiService:GetGuiInset().Y - 24
		;(scale :: UIScale).Scale = math.clamp(usable / designHeight, 0.7, 1.4)
	end
	apply()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
end

-- Design button colours (face, lip, text). Primary = teal, Danger = coral, Gold = special / MAX, Disabled = locked,
-- Walnut = an inactive tab, GoldTab = the active tab.
WindowKit.BUTTON = {
	Primary = { face = Color3.fromRGB(31, 194, 165), lip = Color3.fromRGB(11, 127, 108), text = C.cream },
	Danger = { face = Color3.fromRGB(255, 106, 77), lip = Color3.fromRGB(184, 52, 31), text = C.cream },
	Gold = { face = Color3.fromRGB(255, 200, 58), lip = Color3.fromRGB(217, 138, 0), text = C.ink },
	Disabled = { face = Color3.fromRGB(122, 107, 98), lip = Color3.fromRGB(78, 66, 59), text = Color3.fromRGB(200, 188, 176) },
	Violet = { face = Color3.fromRGB(145, 104, 255), lip = Color3.fromRGB(90, 58, 196), text = C.cream },
	Walnut = { face = Color3.fromRGB(90, 59, 40), lip = Color3.fromRGB(43, 27, 20), text = C.cream },
}

local function darker(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.38)
end

local function lightFace(color: Color3): boolean
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) > 0.68
end

-- The design's chunky button: a face with an ink outline sitting on a darker "lip" (3 px), Oswald text. The button itself
-- turns transparent and keeps its clicks; its Text and BackgroundColor3 are mirrored onto the face, so a controller that
-- sets `button.BackgroundColor3 = UiTheme.Disabled` or changes the text keeps working. style = a WindowKit.BUTTON entry.
function WindowKit.Chunky(button: GuiButton, style: { [string]: any }, textSize: number?, radius: number?)
	local r = radius or 12
	local existing = button:FindFirstChild("DfFace")
	if existing == nil then
		button:SetAttribute("DfBtn", true) -- WindowKit.Button / HudSkinController leave it alone
		for _, c in button:GetChildren() do
			if c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") or c.Name == "DfShade" or c:IsA("UITextSizeConstraint") then
				c:Destroy()
			end
		end
		local z = button.ZIndex
		local lip = make("Frame", { Name = "DfLip", BorderSizePixel = 0, Position = UDim2.fromOffset(0, 3), Size = UDim2.fromScale(1, 1), ZIndex = z, Active = false }, button)
		corner(lip, r)
		local face = make("Frame", { Name = "DfFace", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Active = false }, button)
		corner(face, r)
		make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, face)
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)),
		}, face)
		local label = make("TextLabel", {
			Name = "DfText", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), ZIndex = z + 2,
			FontFace = Skin.FONT_TITLE, TextWrapped = true, Active = false,
		}, button)
		make("UITextSizeConstraint", { MaxTextSize = textSize or 16, MinTextSize = 8 }, label)
		label.TextScaled = true
		button.BackgroundTransparency = 1
		button.TextTransparency = 1
		button.AutoButtonColor = false
		local busy = false
		local function sync()
			if busy then
				return
			end
			busy = true
			local faceColor = button.BackgroundColor3
			face.BackgroundColor3 = faceColor
			lip.BackgroundColor3 = button:GetAttribute("DfLipColor") or darker(faceColor)
			label.TextColor3 = if lightFace(faceColor) then C.ink else C.cream
			label.Text = button.Text
			busy = false
		end
		button:GetPropertyChangedSignal("Text"):Connect(sync)
		button:GetPropertyChangedSignal("BackgroundColor3"):Connect(sync)
		button:GetAttributeChangedSignal("DfLipColor"):Connect(sync)
		-- pressed: the face drops onto the lip
		button.MouseButton1Down:Connect(function()
			face.Position = UDim2.fromOffset(0, 2)
		end)
		local function release()
			face.Position = UDim2.fromOffset(0, 0)
		end
		button.MouseButton1Up:Connect(release)
		button.MouseLeave:Connect(release)
	end
	button:SetAttribute("DfLipColor", style.lip)
	button.BackgroundColor3 = style.face
	local label = button:FindFirstChild("DfText") :: TextLabel?
	if label and textSize then
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint.MaxTextSize = textSize
		end
	end
end

-- Pill chip on a TextLabel (rarity badge): coloured fill, ink outline, ink text, sized to the text.
function WindowKit.Badge(label: TextLabel, color: Color3, textSize: number?)
	if not label:GetAttribute("DfBadge") then
		label:SetAttribute("DfBadge", true)
		for _, c in label:GetChildren() do
			if c:IsA("UITextSizeConstraint") or c:IsA("UIStroke") or c:IsA("UICorner") or c:IsA("UIPadding") then
				c:Destroy()
			end
		end
		corner(label, 10)
		make("UIStroke", { Color = C.ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, label)
		make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, label)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.TextScaled = false
		label.FontFace = Skin.FONT_TEXT
	end
	label.TextSize = textSize or 11
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.TextColor3 = C.ink -- the design uses ink text on every rarity colour
end

-- Gold scrollbars.
local function scrollbars(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ScrollingFrame") then
			d.ScrollBarImageColor3 = C.gold
			d.ScrollBarThickness = 6
		end
	end
end

-- Removes a leading emoji + space from a title ("🎒 Inventory" -> "INVENTORY"): the window now has a proper icon.
local function cleanTitle(title: TextLabel)
	if title:GetAttribute("DfTitle") then
		return
	end
	title:SetAttribute("DfTitle", true)
	local busy = false
	local function apply()
		if busy then
			return
		end
		local text = title.Text
		local stripped = string.gsub(text, "^[^%w]+", "")
		local upper = string.upper(stripped)
		if upper ~= "" and upper ~= text then
			busy = true
			title.Text = upper
			busy = false
		end
	end
	title:GetPropertyChangedSignal("Text"):Connect(apply)
	apply()
end

-- The window frame: shell, title, medallion + icon, close button. o: art, color.
function WindowKit.Shell(window: GuiObject, o: { [string]: any })
	if window:GetAttribute("DfShell") then
		return
	end
	window:SetAttribute("DfShell", true)
	window.BackgroundColor3 = Color3.new(1, 1, 1)
	window.BackgroundTransparency = 0
	window.ClipsDescendants = false
	for _, g in window:GetChildren() do
		if g:IsA("UIGradient") then
			g:Destroy()
		end
	end
	make("UIGradient", { Name = "DfShellGradient", Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(106, 70, 48), Color3.fromRGB(46, 29, 20)) }, window)
	corner(window, 20)
	borderStroke(window, C.ink, 3.5)
	make("Frame", { Name = "DfRimHolder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = window.ZIndex, Active = false }, window)
	local rim = make("Frame", {
		Name = "DfRim", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), Active = false,
	}, window)
	corner(rim, 16)
	make("UIStroke", { Color = C.gold, Thickness = 1.5, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, rim)

	local title = child(window, o.titleName or "Title")
	if title and title:IsA("TextLabel") then
		local medallion = make("Frame", {
			Name = "DfMedallion", BackgroundColor3 = o.color or C.gold, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(36, 36), ZIndex = title.ZIndex, Active = false,
		}, window)
		corner(medallion, 18)
		borderStroke(medallion, C.ink, 2.5)
		make("ImageLabel", {
			Name = "DfIcon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = Skin.Art(o.art or "Menu"), ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(28, 28), ZIndex = title.ZIndex + 1,
		}, medallion)
		title.Position = UDim2.new(title.Position.X.Scale, 58, title.Position.Y.Scale, title.Position.Y.Offset)
		title.Size = UDim2.new(title.Size.X.Scale, title.Size.X.Offset - 42, title.Size.Y.Scale, title.Size.Y.Offset)
		title.FontFace = Skin.FONT_TITLE
		title.TextColor3 = C.gold
		title.TextXAlignment = Enum.TextXAlignment.Left
		textStroke(title, 3)
		cleanTitle(title)
	end

	local closeButton = child(window, o.closeName or "CloseButton")
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.BackgroundColor3 = Color3.fromRGB(255, 106, 77)
		WindowKit.Button(closeButton, true)
		closeButton.Text = ""
		make("ImageLabel", {
			Name = "DfIcon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = Skin.Art("Close"), ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), ZIndex = closeButton.ZIndex + 2, Active = false,
		}, closeButton)
	end
	scrollbars(window)
end

-- Applies fn to every current child of `container` and to every child added later (deferred, so the controller has finished
-- naming / filling it first).
local function watch(container: Instance?, fn: (Instance) -> ())
	if container == nil then
		return
	end
	for _, c in container:GetChildren() do
		task.defer(fn, c)
	end
	container.ChildAdded:Connect(function(c)
		task.defer(fn, c)
	end)
end

local function styleTabs(window: Instance)
	local tabs = child(window, "Tabs")
	if tabs then
		for _, t in tabs:GetDescendants() do
			if t:IsA("GuiButton") then
				WindowKit.Tab(t)
			end
		end
	end
end

local function styleButtonsIn(root: Instance, exclude: { [string]: boolean }?)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and not (exclude and exclude[d.Name]) then
			WindowKit.Button(d)
		end
	end
end

-- ===== per window =====

local function inventory(gui: ScreenGui)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	if window == nil then
		return
	end
	WindowKit.Shell(window, { art = "Inventory", color = Color3.fromRGB(31, 194, 165) })
	if window:GetAttribute("DfFigma") then
		return -- InventoryController draws the Figma layout itself (tabs, cards, details)
	end
	styleTabs(window)
	try("inventory details", function()
		local details = child(window, "Details")
		if details and details:IsA("GuiObject") then
			WindowKit.Card(details, C.ink, 16)
			for _, name in { "QuickSellButton", "RestoreButton", "PlaceButton" } do
				local b = child(details, name)
				if b and b:IsA("GuiButton") then
					WindowKit.Button(b)
				end
			end
		end
		local capacity = child(window, "Capacity")
		if capacity and capacity:IsA("GuiObject") then
			WindowKit.Pill(capacity)
		end
	end)
	-- grid cards come from ReplicatedStorage.Assets.UI.ItemCard (cloned by InventoryController)
	try("inventory item card", function()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local ui = assets and assets:FindFirstChild("UI")
		local card = ui and ui:FindFirstChild("ItemCard")
		if card and card:IsA("GuiObject") then
			WindowKit.Card(card, C.walnutLight, 12)
		end
	end)
end

local function upgrades(gui: ScreenGui)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	if window == nil then
		return
	end
	WindowKit.Shell(window, { art = "Upgrades", color = Color3.fromRGB(255, 138, 61) })
	if window:GetAttribute("DfFigma") then
		return -- ShopController draws the Figma upgrade cards itself
	end
	styleTabs(window)
	local cash = child(window, "Cash")
	if cash and cash:IsA("GuiObject") then
		WindowKit.Pill(cash)
	end
	local template = gui:FindFirstChild("UpgradeTemplate")
	if template and template:IsA("GuiObject") then
		WindowKit.Card(template, C.walnutLight, 14)
		local icon = child(template, "Icon")
		if icon and icon:IsA("GuiObject") then -- emoji in a round medallion
			icon.BackgroundTransparency = 0
			icon.BackgroundColor3 = Color3.fromRGB(255, 138, 61)
			corner(icon, 20)
			borderStroke(icon, C.ink, 2.5)
		end
		local buy = child(template, "BuyButton")
		if buy and buy:IsA("GuiButton") then
			WindowKit.Button(buy)
		end
		local dots = child(template, "Dots")
		if dots then
			for _, dot in dots:GetChildren() do
				if dot:IsA("GuiObject") then
					corner(dot, 8)
					borderStroke(dot, C.ink, 1.5)
				end
			end
		end
	end
end

local function supply(gui: ScreenGui)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	if window == nil then
		return
	end
	WindowKit.Shell(window, { art = "Crate", color = Color3.fromRGB(255, 106, 77) })
	local cash = child(window, "Cash")
	if cash and cash:IsA("GuiObject") then
		WindowKit.Pill(cash)
	end
	local template = gui:FindFirstChild("CrateTemplate")
	if template and template:IsA("GuiObject") then
		WindowKit.Card(template, C.walnutLight, 16)
		local buy = child(template, "BuyButton")
		if buy and buy:IsA("GuiButton") then
			WindowKit.Button(buy)
		end
	end
end

local function collection(gui: ScreenGui)
	local book = gui:FindFirstChild("Book") :: GuiObject?
	if book == nil then
		return
	end
	WindowKit.Shell(book, { art = "Collection", color = Color3.fromRGB(31, 194, 165) })
	for _, name in { "PrevButton", "NextButton" } do
		local b = child(book, name)
		if b and b:IsA("GuiButton") then
			WindowKit.Button(b, true)
		end
	end
	local pageLabel = child(book, "PageLabel")
	if pageLabel and pageLabel:IsA("TextLabel") then
		pageLabel.FontFace = Skin.FONT_TITLE
		pageLabel.TextColor3 = C.cream
	end
	local template = gui:FindFirstChild("EntryTemplate")
	if template and template:IsA("GuiObject") then
		WindowKit.Card(template, C.walnutLight, 12)
		local icon = child(template, "Icon") -- coloured letter badge
		if icon and icon:IsA("GuiObject") then
			corner(icon, 18)
		end
	end
end

local function settings(gui: ScreenGui)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	if window == nil then
		return
	end
	WindowKit.Shell(window, { art = "Settings", color = Color3.fromRGB(134, 163, 181) })
	local template = gui:FindFirstChild("ToggleTemplate")
	if template and template:IsA("GuiObject") then
		WindowKit.Card(template, C.walnutLight, 14)
		local label = child(template, "Label")
		if label and label:IsA("TextLabel") then
			label.FontFace = Skin.FONT_TITLE
			label.TextColor3 = C.cream
		end
		local switch = child(template, "Switch")
		if switch and switch:IsA("GuiButton") then
			WindowKit.Button(switch, true)
			corner(switch, 18) -- a pill switch
		end
	end
end

local function visit(gui: ScreenGui)
	local window = gui:FindFirstChild("Window") :: GuiObject?
	if window == nil then
		return
	end
	WindowKit.Shell(window, { art = "Visit", color = Color3.fromRGB(255, 107, 142) })
	if window:GetAttribute("DfFigma") then
		return -- VisitController draws the Figma rows itself
	end
	local invite = child(window, "InviteButton")
	if invite and invite:IsA("GuiButton") then
		WindowKit.Button(invite)
	end
	local template = gui:FindFirstChild("RowTemplate")
	if template and template:IsA("GuiObject") then
		WindowKit.Card(template, C.walnutLight, 14)
		local button = child(template, "VisitButton")
		if button and button:IsA("GuiButton") then
			WindowKit.Button(button)
		end
	end
end

local BY_NAME = { Inventory = inventory, Upgrades = upgrades, Supply = supply, Collection = collection, Settings = settings, Visit = visit }

-- Restyles one ScreenGui if it is a known window. Safe to call more than once. Discovery / Restoration / Tutorial are skipped.
function WindowKit.SkinScreen(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	local fn = BY_NAME[gui.Name]
	if fn == nil then
		return
	end
	try("skin " .. gui.Name, function()
		fn(gui)
		scrollbars(gui)
	end)
	log("skinned", gui.Name)
end

return WindowKit
