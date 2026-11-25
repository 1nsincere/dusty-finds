-- NotificationDock.luau (StarterPlayerScripts.Client.NotificationDock)
-- Purpose: the ONE place notifications appear (Figma "Main HUD — Notifications"): a small dock under the top chips with
-- at most 3 stacked toasts (newest on top, older ones fade), 4 s each, identical messages merge ("Crate delivered! x2"),
-- and a single priority banner (rare-find announcements) that covers the dock for 5 s while other toasts wait.
-- Look = the Figma components "HUD Toast" (82:4212) and "HUD Priority Banner" (82:4235), Desktop + Phone variants
-- (rebuilt to the design by Sean + Claude, 2026-11-25). Messages are plain text from the server; the first sentence
-- becomes the title and the rest the second line ("Inventory full (16/16)!" / "Sell unrestored items ...").
-- Reduce effects: no pop, just a quick fade. Built entirely in code, no Studio objects needed.
-- Owner: Dev 1 (Ace); design pass Dev 3 (Sean). Depends on: Shared.Config.UiSkin, HudKit (make, Label, Reduced).
-- Used by HudController (Notify / Announcement remotes) and created by HudLayoutController (it owns the ScreenGui).

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))
local HudKit = require(script.Parent:WaitForChild("HudKit"))

local C = Skin.COLORS
local make = HudKit.make

local NotificationDock = {}

local TOAST_SECONDS = 4
local BANNER_SECONDS = 5
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Sizes straight from the Figma variants (reference pixels; HudTop's UIScale scales them with the HUD).
local TOAST_SIZES = {
	Desktop = { radius = 18, padL = 8, padR = 18, padY = 8, gap = 10, medallion = 42, icon = 32, title = 18, sub = 13, line = 23, subLine = 16, maxText = 236 }, -- 236 = the 320 px dock zone minus padding + medallion
	Phone = { radius = 14, padL = 6, padR = 12, padY = 5, gap = 8, medallion = 32, icon = 25, title = 14, sub = 11, line = 18, subLine = 14, maxText = 190 },
}
local BANNER_SIZES = {
	Desktop = { radius = 24, padL = 14, padR = 28, padY = 10, gap = 14, star = 48, title = 26, sub = 15, line = 32, subLine = 19, maxText = 460 },
	Phone = { radius = 18, padL = 10, padR = 18, padY = 7, gap = 10, star = 36, title = 19, sub = 12, line = 24, subLine = 15, maxText = 290 },
}
local TOAST_LIP = 3 -- the type colour showing under a toast (Figma: 0 3px 0 <lip>)
local BANNER_LIP = 4 -- the ink edge under the banner (Figma: 0 4px 0 ink)
local STACK_FADE = { 0, 0.1, 0.22 } -- newest, older, oldest (Figma: 100 / 90 / 78 % opacity)
local BANNER_TOP = Color3.fromRGB(169, 139, 255) -- #a98bff
local BANNER_BOTTOM = Color3.fromRGB(90, 58, 196) -- #5a3ac4

type Toast = { frame: CanvasGroup, key: string, title: string, sub: string, kind: string, count: number, token: number, titleLabel: TextLabel }

local dock: Frame? = nil
local dockList: UIListLayout? = nil
local banner: CanvasGroup? = nil
local maxVisible = 3
local compact = false -- phone variant (SetLayout: a narrow dock means a phone)
local dockWidth = 380 -- the widest a toast may get (SetLayout)
local stack: { Toast } = {} -- newest first
local order = 0
local bannerQueue: { string } = {}
local bannerBusy = false
local priorityListener: ((boolean) -> ())? = nil
local pending: { { string } } = {} -- messages that arrived before Init

function NotificationDock.IsReady(): boolean
	return dock ~= nil
end

-- A callback(active) for "the priority banner is showing" (the chips hide behind it on phones).
function NotificationDock.OnPriority(callback: (boolean) -> ())
	priorityListener = callback
end

-- Where the dock sits and how wide it may get (reference pixels). Called again when the screen shape changes.
-- Toasts hug their text up to that width; a dock narrower than 300 uses the Phone variant.
function NotificationDock.SetLayout(position: UDim2, anchor: Vector2, width: number, visibleCount: number)
	maxVisible = visibleCount
	compact = width < 300
	dockWidth = width
	if dock then
		dock.Position = position
		dock.AnchorPoint = anchor
		dock.Size = UDim2.fromOffset(width, 0)
	end
	if dockList then
		dockList.HorizontalAlignment = if anchor.X < 0.25 then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
	end
	if banner then
		banner.Position = position
		banner.AnchorPoint = anchor
	end
end

-- "Inventory full (16/16)! Sell unrestored items, ..." -> "Inventory full (16/16)!", "Sell unrestored items, ..."
-- Leading emoji/symbols are dropped (the medallion shows the type). A "\n" in the message splits it explicitly.
local function splitMessage(text: string): (string, string)
	local clean = string.gsub(text, "^[^%w%(%$%+%-]+", "")
	local first, rest = string.match(clean, "^(.-)\n(.*)$")
	if first then
		return first, rest
	end
	-- the first sentence end within the first 48 characters: "! " / ". " / "? " (kept) or ": " (dropped)
	local bestAt, bestKeep = nil, true
	for _, mark in { "! ", ". ", "? ", ": " } do
		local at = string.find(clean, mark, 1, true)
		if at and at <= 48 and (bestAt == nil or at < bestAt) then
			bestAt, bestKeep = at, mark ~= ": "
		end
	end
	if bestAt then
		local title = string.sub(clean, 1, if bestKeep then bestAt else bestAt - 1)
		local sub = string.gsub(string.sub(clean, bestAt + 2), "^%s+", "")
		if sub ~= "" then
			return title, sub
		end
	end
	return clean, ""
end

local function fadeOutAndDestroy(frame: CanvasGroup)
	if frame.Parent == nil then
		return
	end
	local tween = TweenService:Create(frame, FADE, { GroupTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		frame:Destroy()
	end)
end

local function removeToast(toast: Toast)
	local index = table.find(stack, toast)
	if index then
		table.remove(stack, index)
	end
	fadeOutAndDestroy(toast.frame)
end

local function restack()
	for index, toast in stack do
		if toast.frame.Parent then
			TweenService:Create(toast.frame, FADE, { GroupTransparency = STACK_FADE[math.min(index, #STACK_FADE)] }):Play()
		end
	end
end

-- A label hugs its text, but past `maxWidth` it gets that fixed width and wraps onto more lines. (Roblox's AutomaticSize
-- ignores a UISizeConstraint's max width, so the line is measured first; the legacy font is close enough to measure with.)
local function fitWidth(label: TextLabel, text: string, size: number, legacyFont: Enum.Font, maxWidth: number)
	local width = TextService:GetTextSize(text, size, legacyFont, Vector2.new(4000, 1000)).X + 4
	if width > maxWidth then
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromOffset(maxWidth, 0)
	else
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.new()
	end
end

-- Title + optional second line, hugging the text up to `maxWidth` (longer lines wrap).
local function textColumn(parent: Instance, s, title: string, sub: string, titleColor: Color3, subColor: Color3, subFont: Font, subAlpha: number, layoutOrder: number): (TextLabel, TextLabel)
	local column = make("Frame", {
		Name = "Text", BackgroundTransparency = 1, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = layoutOrder,
	}, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }, column)
	local titleLabel = HudKit.Label(column, {
		Name = "Title", Text = title, FontFace = Skin.FONT_TITLE, TextSize = s.title, LineHeight = 1, TextColor3 = titleColor,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = 1,
	})
	make("UISizeConstraint", { MinSize = Vector2.new(0, s.line) }, titleLabel)
	fitWidth(titleLabel, title .. "  x99", s.title, Enum.Font.Oswald, s.maxText) -- room for a merge counter
	local subLabel = HudKit.Label(column, {
		Name = "Sub", Text = sub, FontFace = subFont, TextSize = s.sub, TextColor3 = subColor, TextTransparency = subAlpha,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Visible = sub ~= "", LayoutOrder = 2,
	})
	make("UISizeConstraint", { MinSize = Vector2.new(0, s.subLine) }, subLabel)
	fitWidth(subLabel, sub, s.sub, Enum.Font.TitilliumWeb, s.maxText)
	return titleLabel, subLabel
end

-- One toast: a transparent CanvasGroup (for fading) holding the lip strip and the walnut card on top of it.
local function buildToast(kind: string, title: string, sub: string): Toast
	local style = Skin.TOAST[kind] or Skin.TOAST.Info
	local base = if compact then TOAST_SIZES.Phone else TOAST_SIZES.Desktop
	-- never wider than the dock: the text gets what is left after padding, medallion, gap and the 3 px outline
	local s = table.clone(base)
	s.maxText = math.max(120, math.min(base.maxText, dockWidth - (base.padL + base.padR + base.medallion + base.gap + 6)))
	order += 1
	local group = make("CanvasGroup", {
		Name = "Toast_" .. kind, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = -order, GroupTransparency = 1,
		Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY,
	}, dock)
	-- room round the card for its 3 px outline (drawn outside the card) and the lip below it
	make("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3 + TOAST_LIP) }, group)
	local lip = make("Frame", {
		Name = "Lip", BackgroundColor3 = style.lip, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -3, 1, 3 + TOAST_LIP),
		Size = UDim2.new(1, 6, 0, s.radius * 2), ZIndex = 1,
	}, group)
	make("UICorner", { CornerRadius = UDim.new(0, s.radius + 3) }, lip)
	local card = make("Frame", {
		Name = "Card", BackgroundColor3 = C.walnut, BorderSizePixel = 0, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, ZIndex = 2,
	}, group)
	make("UICorner", { CornerRadius = UDim.new(0, s.radius) }, card)
	make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIPadding", { PaddingLeft = UDim.new(0, s.padL), PaddingRight = UDim.new(0, s.padR), PaddingTop = UDim.new(0, s.padY), PaddingBottom = UDim.new(0, s.padY) }, card)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, s.gap), SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)
	local medallion = make("Frame", { Name = "Medallion", BackgroundColor3 = style.color, BorderSizePixel = 0, Size = UDim2.fromOffset(s.medallion, s.medallion), LayoutOrder = 1 }, card)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, medallion)
	make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, medallion)
	make("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = Skin.Art(style.art), ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(s.icon, s.icon),
	}, medallion)
	local titleLabel = textColumn(card, s, title, sub, C.cream, C.cream, Skin.FONT_BODY, 0.15, 2)

	if HudKit.Reduced() then
		TweenService:Create(group, FADE, { GroupTransparency = 0 }):Play()
	else
		local scale = make("UIScale", { Scale = 0.9 }, group)
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		TweenService:Create(group, FADE, { GroupTransparency = 0 }):Play()
	end
	return { frame = group, key = kind .. ":" .. title .. "|" .. sub, title = title, sub = sub, kind = kind, count = 1, token = 0, titleLabel = titleLabel }
end

local function scheduleRemoval(toast: Toast)
	toast.token += 1
	local token = toast.token
	task.delay(TOAST_SECONDS, function()
		if toast.token == token and toast.frame.Parent ~= nil then
			removeToast(toast)
			restack()
		end
	end)
end

function NotificationDock.Notify(kind: string, text: string)
	if dock == nil then
		table.insert(pending, { kind, text })
		return
	end
	local title, sub = splitMessage(text)
	local key = kind .. ":" .. title .. "|" .. sub
	for _, toast in stack do
		if toast.key == key and toast.frame.Parent ~= nil then -- same message again: merge
			toast.count += 1
			toast.titleLabel.Text = `{toast.title}  x{toast.count}`
			scheduleRemoval(toast)
			return
		end
	end
	local toast = buildToast(kind, title, sub)
	table.insert(stack, 1, toast)
	while #stack > maxVisible do
		removeToast(stack[#stack])
	end
	restack()
	scheduleRemoval(toast)
end

-- ===== priority banner =====

-- Rebuilt for each announcement (so it always uses the current Desktop / Phone size).
local function fillBanner(group: CanvasGroup, text: string)
	for _, child in group:GetChildren() do
		child:Destroy()
	end
	local s = if compact then BANNER_SIZES.Phone else BANNER_SIZES.Desktop
	local title, sub = splitMessage(text)
	make("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3 + BANNER_LIP) }, group)
	local lip = make("Frame", {
		Name = "Lip", BackgroundColor3 = C.ink, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -3, 1, 3 + BANNER_LIP),
		Size = UDim2.new(1, 6, 0, s.radius * 2), ZIndex = 1,
	}, group)
	make("UICorner", { CornerRadius = UDim.new(0, s.radius + 3) }, lip)
	local card = make("Frame", {
		Name = "Card", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, ZIndex = 2,
	}, group)
	make("UICorner", { CornerRadius = UDim.new(0, s.radius) }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(BANNER_TOP, BANNER_BOTTOM) }, card)
	make("UIStroke", { Color = C.gold, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIPadding", { PaddingLeft = UDim.new(0, s.padL), PaddingRight = UDim.new(0, s.padR), PaddingTop = UDim.new(0, s.padY), PaddingBottom = UDim.new(0, s.padY) }, card)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, s.gap), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	make("ImageLabel", { Name = "Star", BackgroundTransparency = 1, Image = Skin.Art("Star"), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(s.star, s.star), LayoutOrder = 1 }, card)
	local titleLabel = textColumn(card, s, title, sub, C.gold, C.cream, Skin.FONT_TEXT, 0, 2)
	make("UIStroke", { Color = C.ink, Thickness = if compact then 2 else 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, titleLabel)
end

local function showNextBanner()
	if bannerBusy or banner == nil or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local shown = banner :: CanvasGroup
	fillBanner(shown, table.remove(bannerQueue, 1) :: string)
	shown.GroupTransparency = 1
	shown.Visible = true
	if dock then
		dock.Visible = false
	end
	if priorityListener then
		priorityListener(true)
	end
	TweenService:Create(shown, FADE, { GroupTransparency = 0 }):Play()
	if not HudKit.Reduced() then
		local scale = shown:FindFirstChild("Pop") or make("UIScale", { Name = "Pop" }, shown)
		scale.Scale = 0.92
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
	end
	task.delay(BANNER_SECONDS, function()
		local out = TweenService:Create(shown, FADE, { GroupTransparency = 1 })
		out:Play()
		out.Completed:Wait()
		shown.Visible = false
		bannerBusy = false
		if #bannerQueue == 0 then
			if dock then
				dock.Visible = true
			end
			if priorityListener then
				priorityListener(false)
			end
		end
		showNextBanner()
	end)
end

function NotificationDock.Priority(text: string)
	if banner == nil then
		table.insert(pending, { "Priority", text })
		return
	end
	if #bannerQueue >= 3 then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, text)
	showNextBanner()
end

-- Creates the dock + banner inside `screenGui` (HudLayoutController's "HudTop").
function NotificationDock.Init(screenGui: ScreenGui)
	if dock ~= nil then
		return
	end
	dock = make("Frame", {
		Name = "NotificationDock", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 5,
	}, screenGui)
	-- Figma stacks toasts 4 px apart (64 px tall toasts at 68 px steps)
	dockList = make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, dock)

	banner = make("CanvasGroup", {
		Name = "PriorityBanner", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 6,
	}, screenGui)

	-- load every toast glyph now, so the first toast of each type doesn't show an empty medallion while it downloads
	task.spawn(function()
		local images = {}
		for _, style in Skin.TOAST do
			table.insert(images, make("ImageLabel", { Image = Skin.Art(style.art) }))
		end
		table.insert(images, make("ImageLabel", { Image = Skin.Art("Star") }))
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(images)
		end)
		for _, image in images do
			image:Destroy()
		end
	end)

	for _, message in pending do
		if message[1] == "Priority" then
			NotificationDock.Priority(message[2])
		else
			NotificationDock.Notify(message[1], message[2])
		end
	end
	table.clear(pending)
end

-- Studio check: NotificationDock._split("Inventory full (16/16)! Sell ...") (not used by the game)
NotificationDock._split = splitMessage

return NotificationDock
