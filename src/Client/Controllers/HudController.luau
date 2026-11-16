-- HudController.luau
-- Purpose: HUD: shows my money, level, XP and shop rating stars from ClientState; shows server messages
-- (Notify, Announcement) as the coral banner (good news) or toasts (problems); scales HUD + Toasts to the screen.
-- Buttons are wired by their own screens.
-- Owner: Dev 3 (Sean). Depends on: ClientState ("rating" is sent by CollectionBookService), UiTheme,
-- Shared.Remotes (Notify, Announcement), Shared.Formulas, Shared.Config.Economy,
-- StarterGui.HUD + StarterGui.Toasts (UI contract, docs/03 §8).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

local HudController = {}
local DEBUG = true

-- The HUD layout is about 325 px tall at scale 1 (top row → last left button) + bottom margin.
-- Scale = usable screen height / REFERENCE_HEIGHT, clamped so buttons never drop below ~44 px (52 × 0.85)
-- and never get comically large on a 4K monitor.
local REFERENCE_HEIGHT = 360
local MIN_SCALE = 0.85
local MAX_SCALE = 1.4

-- Messages (docs/01 J3: banner auto-hides after 4 s; J4: failures get a friendly toast)
local BANNER_SECONDS = 4
local TOAST_SECONDS = 3
local MAX_BANNER_QUEUE = 3 -- waiting banners; extra ones push out the oldest so a burst can't stall the screen
local MAX_TOASTS = 3 -- on screen at once
local MAX_TEXT_LENGTH = 120
local SLIDE = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.3)
-- Notify kinds shown as the banner, with their icon. Any other kind (e.g. "Info") becomes a toast.
local BANNER_ICONS = {
	LevelUp = "⭐",
	Upgrade = "🔨",
	Delivery = "📦", -- "Crate delivered!" / "Free delivery arrived!" (ShipmentService, docs/01 J3)
}
local MAX_STARS = 5
local ANNOUNCEMENT_ICON = "🏆"

local hud: ScreenGui? = nil
local toasts: ScreenGui? = nil
local cameraConnection: RBXScriptConnection? = nil

-- ===== Money / level / XP =====

local function updateMoney()
	local cash = ClientState.Get("cash")
	if hud == nil or type(cash) ~= "number" then
		return -- not loaded: keep the placeholder text from Studio
	end
	hud.MoneyPill.Amount.Text = UiTheme.formatCash(cash)
end

-- "rating" = shop rating stars (1-5), worked out by the server from decor, expansions and exhibits.
local function updateRating()
	local stars = ClientState.Get("rating")
	if hud == nil or type(stars) ~= "number" then
		return -- not sent (older server): keep the Studio placeholder
	end
	stars = math.clamp(math.floor(stars), 0, MAX_STARS)
	for i = 1, MAX_STARS do
		local star = hud.RatingPill.Stars:FindFirstChild("Star" .. i)
		if star then
			star.TextColor3 = if i <= stars then UiTheme.Coral else UiTheme.Disabled
		end
	end
	if DEBUG then
		print(`[HudController] rating {stars}★`)
	end
end

local function updateXp()
	local level = ClientState.Get("level")
	local xp = ClientState.Get("xp")
	if hud == nil or type(level) ~= "number" or type(xp) ~= "number" then
		return
	end
	local bar = hud.XPBar
	if level >= Economy.MaxLevel then
		bar.Level.Text = `Lv {level} MAX`
		bar.Fill.Size = UDim2.fromScale(1, 1)
		return
	end
	-- `xp` is progress inside the current level (EconomyService subtracts it on level-up).
	local needed = Formulas.xpToNext(level)
	local progress = if needed > 0 then math.clamp(xp / needed, 0, 1) else 0
	bar.Level.Text = `Lv {level}`
	bar.Fill.Size = UDim2.fromScale(progress, 1)
	if DEBUG then
		print(`[HudController] Lv {level}, xp {xp}/{needed}`)
	end
end

-- ===== Banner (one at a time, queued) =====

local bannerQueue: { string } = {}
local bannerBusy = false
local bannerShownPosition: UDim2? = nil -- where Studio placed it; we slide in from above to here

local function showNextBanner()
	if bannerBusy or hud == nil or bannerShownPosition == nil or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local banner = hud.Banner
	local shown = bannerShownPosition
	local hidden = UDim2.new(shown.X.Scale, shown.X.Offset, 0, -banner.AbsoluteSize.Y - 20)

	banner.Text.Text = table.remove(bannerQueue, 1)
	banner.Position = hidden
	banner.Visible = true
	TweenService:Create(banner, SLIDE, { Position = shown }):Play()

	task.delay(BANNER_SECONDS, function()
		local out = TweenService:Create(banner, FADE, { Position = hidden })
		out:Play()
		out.Completed:Wait()
		banner.Visible = false
		bannerBusy = false
		showNextBanner()
	end)
end

local function queueBanner(text: string)
	if #bannerQueue >= MAX_BANNER_QUEUE then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, text)
	showNextBanner()
end

-- ===== Toasts (stack, fade out) =====

local toastCount = 0 -- also used as LayoutOrder, so newer toasts sit lower

local function fadeAndRemove(toast: Frame)
	if toast.Parent == nil then
		return -- already pushed out by a newer toast
	end
	local label = toast:FindFirstChild("Text")
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	local fade = TweenService:Create(toast, FADE, { BackgroundTransparency = 1 })
	if label then
		TweenService:Create(label, FADE, { TextTransparency = 1 }):Play()
	end
	if stroke then
		TweenService:Create(stroke, FADE, { Transparency = 1 }):Play()
	end
	fade:Play()
	fade.Completed:Wait()
	toast:Destroy()
end

local function showToast(text: string)
	if toasts == nil then
		return
	end
	local container = toasts:FindFirstChild("Container")
	local template = toasts:FindFirstChild("ToastTemplate")
	if container == nil or template == nil then
		warn("[HudController] Toasts.Container or Toasts.ToastTemplate missing (UI contract docs/03 §8)")
		return
	end

	-- Make room: remove the oldest toasts (lowest LayoutOrder) beyond the limit.
	local live = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(live, child)
		end
	end
	table.sort(live, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #live - MAX_TOASTS + 1 do
		live[i]:Destroy()
	end

	toastCount += 1
	local toast = template:Clone()
	toast.Name = "Toast"
	toast.LayoutOrder = toastCount
	toast.Text.Text = text
	toast.Visible = true
	toast.Parent = container
	task.delay(TOAST_SECONDS, fadeAndRemove, toast)
end

-- ===== Server messages =====

local function cleanText(text: any): string?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	return string.sub(text, 1, MAX_TEXT_LENGTH)
end

local function onNotify(kind: any, text: any)
	local message = cleanText(text)
	if message == nil then
		return
	end
	local icon = if type(kind) == "string" then BANNER_ICONS[kind] else nil
	if DEBUG then
		print(`[HudController] Notify {tostring(kind)}: {message}`)
	end
	if icon then
		queueBanner(`{icon} {message}`)
	else
		showToast(message)
	end
end

local function onAnnouncement(text: any, _rarity: any)
	local message = cleanText(text)
	if message == nil then
		return
	end
	-- Settings → "Show announcements" (saved in my data). Missing/not loaded counts as on.
	if ClientState.Get("settings.announcements") == false then
		return
	end
	queueBanner(`{ANNOUNCEMENT_ICON} {message}`)
end

-- ===== Screen scaling =====

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	-- GetGuiInset().Y = Roblox's topbar height; our screens start below it (IgnoreGuiInset = false).
	local usableHeight = camera.ViewportSize.Y - GuiService:GetGuiInset().Y
	local scale = math.clamp(usableHeight / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
	for _, gui in { hud, toasts } do
		local uiScale = gui and gui:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = scale
		end
	end
	if DEBUG then
		print(`[HudController] viewport {camera.ViewportSize.X}x{camera.ViewportSize.Y}, scale {string.format("%.2f", scale)}`)
	end
end

local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		-- Fires when the window is resized or a phone rotates.
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end

-- For client-only messages (no server involved, e.g. "Invites aren't available"): same look as a server Notify.
function HudController.Notify(kind: string, text: string)
	onNotify(kind, text)
end

-- ===== Lifecycle =====

function HudController.Init(_others)
	if DEBUG then
		print("[HudController] Init")
	end
end

function HudController.Start()
	if DEBUG then
		print("[HudController] Start")
	end
	-- Own thread: waiting for the screens here must not hold up the other controllers' Start().
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local foundHud = playerGui:WaitForChild("HUD", 10)
		if foundHud == nil then
			warn("[HudController] PlayerGui.HUD not found: is StarterGui.HUD missing?")
			return
		end
		hud = foundHud :: ScreenGui
		bannerShownPosition = foundHud.Banner.Position

		toasts = playerGui:WaitForChild("Toasts", 5) :: ScreenGui?
		if toasts == nil then
			warn("[HudController] PlayerGui.Toasts not found: Info messages will not show")
		end

		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
		watchCamera()

		-- Show what we have now, then follow every server change.
		updateMoney()
		updateXp()
		updateRating()
		ClientState.OnChanged("rating", updateRating)
		ClientState.OnChanged("cash", updateMoney)
		ClientState.OnChanged("level", updateXp)
		ClientState.OnChanged("xp", updateXp)

		Remotes.Notify.OnClientEvent:Connect(onNotify)
		Remotes.Announcement.OnClientEvent:Connect(onAnnouncement)
	end)
end

return HudController
