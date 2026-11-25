-- NotificationDock.luau (StarterPlayerScripts.Client.NotificationDock)
-- Purpose: the ONE place notifications appear (Figma "Main HUD — Notifications"): a small dock under the top chips with
-- at most 3 stacked toasts (newest on top, older ones fade), 4 s each, identical messages merge ("Crate delivered! x2"),
-- and a single priority banner (rare-find announcements) that covers the dock for 5 s while other toasts wait.
-- Reduce effects: no slide / pop, just a quick fade. Built entirely in code, no Studio objects needed.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.UiSkin, HudKit (Label), ClientState (via HudKit). Used by HudController
-- (Notify / Announcement remotes) and created by HudLayoutController (it owns the ScreenGui).

local TweenService = game:GetService("TweenService")
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

type Toast = { frame: CanvasGroup, key: string, text: string, kind: string, count: number, token: number, label: TextLabel }

local dock: Frame? = nil
local banner: CanvasGroup? = nil
local bannerLabel: TextLabel? = nil
local maxVisible = 3
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

-- Where the dock sits and how wide it is (reference pixels). Called again when the screen shape changes.
function NotificationDock.SetLayout(position: UDim2, anchor: Vector2, width: number, visibleCount: number)
	maxVisible = visibleCount
	if dock then
		dock.Position = position
		dock.AnchorPoint = anchor
		dock.Size = UDim2.fromOffset(width, 0)
	end
	if banner then
		banner.Position = position
		banner.AnchorPoint = anchor
	end
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
		local target = if index == 1 then 0 elseif index == 2 then 0.12 else 0.26
		if toast.frame.Parent then
			TweenService:Create(toast.frame, FADE, { GroupTransparency = target }):Play()
		end
	end
end

local function buildToast(kind: string, text: string): Toast
	local style = Skin.TOAST[kind] or Skin.TOAST.Info
	order += 1
	local card = make("CanvasGroup", {
		Name = "Toast", BackgroundColor3 = C.walnut, BorderSizePixel = 0, LayoutOrder = -order, GroupTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	}, dock)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, card)
	make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(104, 69, 49), Color3.fromRGB(52, 33, 23)) }, card)
	make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, card)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)
	-- coloured bar along the bottom = the "lip" in the Figma design
	local medallion = make("Frame", { Name = "Medallion", BackgroundColor3 = style.color, BorderSizePixel = 0, Size = UDim2.fromOffset(34, 34), LayoutOrder = 1 }, card)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, medallion)
	make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, medallion)
	make("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = Skin.Art(style.art), ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26),
	}, medallion)
	local label = HudKit.Label(card, {
		Name = "Text", Text = text, FontFace = Skin.FONT_NUMBER, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -50, 0, 0), LayoutOrder = 2,
	})
	make("Frame", {
		Name = "Lip", BackgroundColor3 = style.lip, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, 0),
		Size = UDim2.new(1, -20, 0, 3), ZIndex = 5,
	}, card)

	if HudKit.Reduced() then
		TweenService:Create(card, FADE, { GroupTransparency = 0 }):Play()
	else
		local scale = make("UIScale", { Scale = 0.9 }, card)
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
		TweenService:Create(card, FADE, { GroupTransparency = 0 }):Play()
	end
	return { frame = card, key = kind .. ":" .. text, text = text, kind = kind, count = 1, token = 0, label = label }
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
	local key = kind .. ":" .. text
	for _, toast in stack do
		if toast.key == key and toast.frame.Parent ~= nil then -- same message again: merge
			toast.count += 1
			toast.label.Text = `{toast.text}  x{toast.count}`
			scheduleRemoval(toast)
			return
		end
	end
	local toast = buildToast(kind, text)
	table.insert(stack, 1, toast)
	while #stack > maxVisible do
		removeToast(stack[#stack])
	end
	restack()
	scheduleRemoval(toast)
end

-- ===== priority banner =====

local function showNextBanner()
	if bannerBusy or banner == nil or bannerLabel == nil or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local shown = banner :: CanvasGroup
	bannerLabel.Text = table.remove(bannerQueue, 1) :: string
	shown.GroupTransparency = 1
	shown.Visible = true
	if dock then
		dock.Visible = false
	end
	if priorityListener then
		priorityListener(true)
	end
	TweenService:Create(shown, FADE, { GroupTransparency = 0 }):Play()
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
		Size = UDim2.fromOffset(260, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 5,
	}, screenGui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, dock)

	banner = make("CanvasGroup", {
		Name = "PriorityBanner", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, GroupTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 6,
	}, screenGui)
	local bannerFrame = banner :: CanvasGroup
	make("UICorner", { CornerRadius = UDim.new(0, 20) }, bannerFrame)
	make("UIStroke", { Color = C.gold, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bannerFrame)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(169, 139, 255), Color3.fromRGB(90, 58, 196)) }, bannerFrame)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, bannerFrame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, bannerFrame)
	make("ImageLabel", { Name = "Star", BackgroundTransparency = 1, Image = Skin.Art("Star"), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(38, 38), LayoutOrder = 1 }, bannerFrame)
	bannerLabel = HudKit.Label(bannerFrame, {
		Name = "Text", Text = "", FontFace = Skin.FONT_TITLE, TextSize = 17, TextColor3 = C.gold, TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(250, 0), LayoutOrder = 2,
	})
	make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, bannerLabel)

	for _, message in pending do
		if message[1] == "Priority" then
			NotificationDock.Priority(message[2])
		else
			NotificationDock.Notify(message[1], message[2])
		end
	end
	table.clear(pending)
end

return NotificationDock
