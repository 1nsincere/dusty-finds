-- LoadingScreen.local.luau (ReplicatedFirst.Loading.LoadingScreen, a LocalScript)
-- Purpose: the join screen. Covers Roblox's default loader straight away with a cozy Dusty Finds screen: a mystery box
-- shakes and opens, a dusty find pops out and gets wiped clean (the game's loop in a few seconds), a progress bar that
-- follows the REAL loading steps, and rotating tips. Fades out when the client is ready (or after Skip / a time limit,
-- so nobody can get stuck). Soft sound effects on the box, rag and sparkle (they follow the Settings sound-effects switch
-- once the save loads); no music here: the game music fades in by itself once the shop is open (SoundController).
-- Owner: Dev 3 (Sean). Depends on: Main.local.luau setting the local Player attributes DF_SaveLoaded / DF_ClientReady.
-- ReplicatedFirst runs before anything else replicates: this script uses no other module (fonts, colours inline).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local DEBUG = true
local SKIP_AFTER = 16 -- seconds before the Skip button shows (after the minimum time)
local MAX_WAIT = 40 -- the screen closes by itself after this, whatever happens
local MIN_SHOW = 15 -- a fast join still shows the screen for 15 s (Sean, 2026-11-25): about two full box animations
local UNPACK_MAX = 12 -- the last step (shop, HUD and skin art downloading) gives up after this

local function log(...)
	if DEBUG then
		print("[LoadingScreen]", ...)
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()
local startedAt = os.clock()

local FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_TEXT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local CREAM, SAND = Color3.fromRGB(246, 236, 216), Color3.fromRGB(226, 202, 160)
local INK, INK_SOFT = Color3.fromRGB(59, 42, 30), Color3.fromRGB(122, 96, 72)
local GOLD, GOLD_LIGHT = Color3.fromRGB(255, 176, 46), Color3.fromRGB(255, 214, 92)
local DUST = Color3.fromRGB(120, 98, 74)

local TIPS = {
	"Restore an item fully to sell it for the best price.",
	"Serve customers at the counter quickly for a bonus.",
	"New skins arrive at the skins stall every 5 minutes.",
	"Keep your rarest finds as exhibits to raise your shop rating.",
	"Use the Travel menu (map pin) to get around town fast.",
	"Phone feeling slow? Turn on Reduce effects in Settings.",
}

-- Sound effects: the game's own sounds (same ids as Shared.Config.Sounds, copied because ReplicatedFirst can't require
-- Shared yet), quiet. Once the save loads they stop if the player has sound effects off (DF_SfxOn, set by Main).
local SFX_VOLUME = 0.6 -- on top of each sound's own volume
local SOUNDS = {
	rattle = { id = 9113591001, volume = 0.35, pitch = { 0.7, 0.85 } }, -- box wiggle taps ("snap", lower)
	open = { id = 9114054266, volume = 0.6 }, -- lid pops off ("boxOpen")
	reveal = { id = 9120217544, volume = 0.45, pitch = { 1.1, 1.2 } }, -- the find rises
	wipe = { id = 9113597285, volume = 0.35 }, -- a rag pass (restoration "Wipe"), soft
	restored = { id = 9044739323, volume = 0.45, pitch = { 1.05, 1.05 } }, -- sparkle + RESTORED!
	thud = { id = 9113591001, volume = 0.4, pitch = { 0.5, 0.55 } }, -- the lid drops back on
	click = { id = 9125654847, volume = 0.35, pitch = { 1.35, 1.5 } }, -- Skip
}

-- ===== small UI helpers =====

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function tween(o: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(o, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- ===== the screen =====

local gui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local bg = new("Frame", { Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, gui)
new("UIGradient", { Color = ColorSequence.new(CREAM, SAND), Rotation = 90 }, bg)

-- everything sits in a centred column that keeps its shape on any screen
local column = new("Frame", {
	Name = "Column",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.9),
	BackgroundTransparency = 1,
}, bg)
new("UIAspectRatioConstraint", { AspectRatio = 1.2 }, column)
new("UISizeConstraint", { MaxSize = Vector2.new(620, 520) }, column)

local title = new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0, 0.02),
	Size = UDim2.fromScale(1, 0.13),
	FontFace = FONT_TITLE,
	Text = "DUSTY FINDS",
	TextColor3 = INK,
	TextScaled = true,
}, column)
new("UIStroke", { Color = GOLD, Thickness = 2, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
new("TextLabel", {
	Name = "Subtitle",
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0, 0.15),
	Size = UDim2.fromScale(1, 0.06),
	FontFace = FONT_TEXT,
	Text = "RESTORE & SELL",
	TextColor3 = INK_SOFT,
	TextScaled = true,
}, column)

-- ===== sound effects =====

local soundFolder = new("Folder", { Name = "Sounds" }, gui)
local sounds: { [string]: Sound } = {}
for name, cfg in SOUNDS do
	sounds[name] = new("Sound", { Name = name, SoundId = "rbxassetid://" .. cfg.id, Volume = cfg.volume * SFX_VOLUME }, soundFolder)
end
task.spawn(function()
	local list = {}
	for _, s in sounds do
		table.insert(list, s)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
end)

local function sfxAllowed(): boolean
	-- before the save loads we don't know the setting: play (quietly); after, follow Settings
	return player:GetAttribute("DF_SfxOn") ~= false
end

local function play(name: string)
	local s, cfg = sounds[name], SOUNDS[name]
	if not (s and sfxAllowed()) then
		return
	end
	local pitch = cfg.pitch
	s.PlaybackSpeed = if pitch then pitch[1] + math.random() * (pitch[2] - pitch[1]) else 1
	s.TimePosition = 0
	s:Play()
end

-- ===== cozy background: drifting dust motes and a soft vignette =====

column.ZIndex = 3 -- above the motes and the vignette
local motes = {}
for i = 1, 16 do
	local size = math.random(4, 9)
	local m = new("Frame", {
		Name = "Mote" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.random(), math.random()),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.45 + math.random() * 0.3,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, bg)
	round(m, 999)
	table.insert(motes, m)
end
local vignette = new("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
	ZIndex = 2,
}, bg)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.22, 1),
		NumberSequenceKeypoint.new(0.78, 1),
		NumberSequenceKeypoint.new(1, 0.7),
	}),
}, vignette)

-- ===== the stage: Sean's mystery box art, a dusty find, a rag =====
-- Box art (Sean, 2026-11-25; assets/loading, cut into assets/loading/game): BoxClosed = the whole crate; BoxBody = the same crate below
-- its own lid (its top sits 33.25% down BoxClosed, 66.75% of its height); Lid = the separate lid art (with a soft glow).
local IMAGES = {
	closed = "rbxassetid://76804381828872",
	body = "rbxassetid://78407116327087",
	lid = "rbxassetid://129376966282150",
}
-- the find, rag, sparkle and stamp (Sean's Gemini art, 2026-11-25; the painted-in checkerboard removed, cut into
-- assets/loading/game BearDusty / BearClean / Rag / Sparkle / Stamp)
local ART = {
	bearDusty = "rbxassetid://84371218642425",
	bearClean = "rbxassetid://120858166705193",
	rag = "rbxassetid://103951113689353",
	sparkle = "rbxassetid://85553486157898",
	stamp = "rbxassetid://83137638890002",
}
local BODY_TOP, BODY_H = 0.3325, 0.6675
local LID_ASPECT = 1024 / 322

local stage = new("Frame", {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.22),
	Size = UDim2.fromScale(0.56, 0.5),
	BackgroundTransparency = 1,
}, column)

-- golden light rays that burst out of the open box (behind everything on the stage)
local rays = new("Frame", {
	Name = "Rays",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	ZIndex = 1,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, rays)
-- UI rotation turns round an element's own centre, so each ray is a bar through the middle: 5 bars = 10 rays,
-- bright in the middle and fading to nothing at the tips
for i = 0, 4 do
	local r = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(if i % 2 == 0 then 0.1 else 0.07, 1),
		Rotation = i * 36,
		BackgroundColor3 = GOLD_LIGHT,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, rays)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, r)
end

-- the glow ring that blooms behind the restored find
local glowRing = new("Frame", {
	Name = "GlowRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.29),
	Size = UDim2.fromScale(0, 0),
	BackgroundColor3 = GOLD_LIGHT,
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
	ZIndex = 2,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, glowRing)
round(glowRing, 999)
local glowStroke = new("UIStroke", { Color = GOLD, Thickness = 4, Transparency = 0.3 }, glowRing)

-- the box holder keeps the crate art's shape (962 x 845) on any screen
local holder = new("Frame", {
	Name = "BoxHolder",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.98),
	Size = UDim2.fromScale(0.7, 0.7),
	BackgroundTransparency = 1,
	ZIndex = 4,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 962 / 845 }, holder)

local shadow = new("Frame", {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.98),
	Size = UDim2.fromScale(1.05, 0.1),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	ZIndex = 1,
}, holder)
round(shadow, 999)

-- the dark inside of the box, seen once the lid is off
local inside = new("Frame", {
	Name = "Inside",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, BODY_TOP + 0.01),
	Size = UDim2.fromScale(0.9, 0.1),
	BackgroundColor3 = Color3.fromRGB(58, 36, 22),
	BorderSizePixel = 0,
	ZIndex = 2,
	Visible = false,
}, holder)
round(inside, 6)

-- the find: Sean's teddy bear (Gemini art, 2026-11-25), a dusty and a clean picture stacked exactly on top of each other;
-- the clean one fades in as the rag wipes. It rises out of the box (between the box's inside and its front).
local item = new("Frame", {
	Name = "Item",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.fromScale(0.34, 0.34),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Visible = false,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 691 / 799 }, item)
local bearDusty = new("ImageLabel", {
	Name = "BearDusty",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = ART.bearDusty,
	ZIndex = 3,
}, item)
local bearClean = new("ImageLabel", {
	Name = "BearClean",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = ART.bearClean,
	ImageTransparency = 1,
	ZIndex = 4,
}, item)
local sparkle = new("ImageLabel", {
	Name = "Sparkle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.86, 0.14),
	Size = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	Image = ART.sparkle,
	ZIndex = 6,
}, item)
new("UIAspectRatioConstraint", { AspectRatio = 573 / 587 }, sparkle)
local sparkle2 = new("ImageLabel", { -- a smaller second twinkle on the other side
	Name = "Sparkle2",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.12, 0.42),
	Size = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	Image = ART.sparkle,
	ZIndex = 6,
}, item)
new("UIAspectRatioConstraint", { AspectRatio = 573 / 587 }, sparkle2)
local restored = new("ImageLabel", { -- the RESTORED! stamp, beside the find (above it would cover the subtitle)
	Name = "Restored",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(1.3, 0.62),
	Rotation = -6,
	Size = UDim2.fromScale(1.5, 0.5),
	BackgroundTransparency = 1,
	Image = ART.stamp,
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 7,
}, item)

-- the box art: the closed crate, and the crate body that shows once the lid has popped off
local boxClosed = new("ImageLabel", {
	Name = "BoxClosed",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = IMAGES.closed,
	ZIndex = 4,
}, holder)
local boxBody = new("ImageLabel", {
	Name = "BoxBody",
	Position = UDim2.fromScale(0, BODY_TOP),
	Size = UDim2.fromScale(1, BODY_H),
	BackgroundTransparency = 1,
	Image = IMAGES.body,
	ZIndex = 4,
	Visible = false,
}, holder)
-- the lid art flies off the box (only shown while it is off or flying)
local LID_HOME = UDim2.fromScale(0.5, 0.2)
local lid = new("ImageLabel", {
	Name = "Lid",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = LID_HOME,
	Size = UDim2.fromScale(1.12, 1.12 * 962 / 845 / LID_ASPECT),
	BackgroundTransparency = 1,
	Image = IMAGES.lid,
	ZIndex = 6,
	Visible = false,
}, holder)

-- the rag that wipes the dust off (Sean's rag art)
local rag = new("ImageLabel", {
	Name = "Rag",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.2, 0.4),
	Size = UDim2.fromScale(0.2, 0.2),
	Rotation = -12,
	BackgroundTransparency = 1,
	Image = ART.rag,
	ZIndex = 7,
	Visible = false,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 711 / 550 }, rag)

-- a puff of dust flying off where the rag passes
local function dustPuff(atX: number, atY: number)
	-- soft: a few light puffs that drift up slowly and fade
	for _ = 1, 3 do
		local size = math.random(8, 14) / 100
		local p = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(atX + (math.random() - 0.5) * 0.1, atY),
			Size = UDim2.fromScale(size * 0.5, size * 0.5),
			BackgroundColor3 = DUST,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 8,
		}, stage)
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, p)
		round(p, 999)
		local dx, dy = (math.random() - 0.5) * 0.18, -0.06 - math.random() * 0.1
		TweenService:Create(p, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(atX + dx, atY + dy),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(size, size),
		}):Play()
		task.delay(1.45, function()
			p:Destroy()
		end)
	end
end

-- ===== progress bar, step text, tips, skip =====

local stepLabel = new("TextLabel", {
	Name = "Step",
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.15, 0.73),
	Size = UDim2.fromScale(0.7, 0.05),
	FontFace = FONT_TEXT,
	Text = "Loading the town...",
	TextColor3 = INK,
	TextScaled = true,
}, column)
local bar = new("Frame", {
	Name = "Bar",
	Position = UDim2.fromScale(0.15, 0.8),
	Size = UDim2.fromScale(0.7, 0.035),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
}, column)
round(bar, 999)
local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.04, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, bar)
round(fill, 999)
new("UIGradient", { Color = ColorSequence.new(GOLD, GOLD_LIGHT) }, fill)

local tipLabel = new("TextLabel", {
	Name = "Tip",
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.08, 0.88),
	Size = UDim2.fromScale(0.84, 0.06),
	FontFace = FONT_TEXT,
	Text = "Tip: " .. TIPS[math.random(1, #TIPS)],
	TextColor3 = INK_SOFT,
	TextScaled = true,
	TextWrapped = true,
}, column)

local skip = new("TextButton", {
	Name = "Skip",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(110, 40),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.15,
	FontFace = FONT_TEXT,
	Text = "SKIP  ▶",
	TextColor3 = CREAM,
	TextSize = 18,
	AutoButtonColor = true,
	Visible = false,
}, bg)
round(skip, 8)

-- ===== DF_LOADING_V2: golden-hour look from the Figma loading design (2026-11-25) =====
-- Same scene, sounds and real loading steps as before; new: dark warm background, glowing bar with a marker and a percent,
-- the logo emblem, and a small twist: the player can scrub the dusty bear clean with a finger / the mouse (cosmetic only).
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local CREAM_UI, DIM_UI = Color3.fromRGB(255, 241, 214), Color3.fromRGB(214, 190, 160)
bg:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(Color3.fromRGB(86, 55, 36), Color3.fromRGB(24, 14, 9))
title.TextColor3 = Color3.new(1, 1, 1)
local oldStroke = title:FindFirstChildOfClass("UIStroke")
if oldStroke then oldStroke:Destroy() end
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 244, 168), Color3.fromRGB(240, 138, 18)), Rotation = 90 }, title)
new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
local sub = column:FindFirstChild("Subtitle")
if sub then sub.TextColor3 = DIM_UI end
new("ImageLabel", {
	Name = "Emblem", Position = UDim2.new(0, 18, 0, 14), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1,
	Image = "rbxassetid://100622808127569", ZIndex = 3,
}, bg)

stepLabel.TextColor3 = CREAM_UI
stepLabel.FontFace = FONT_TITLE
stepLabel.TextXAlignment = Enum.TextXAlignment.Left
stepLabel.Size = UDim2.fromScale(0.55, 0.05)
tipLabel.TextColor3 = DIM_UI
local percent = new("TextLabel", {
	Name = "Percent", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.85, 0.73),
	Size = UDim2.fromScale(0.2, 0.05), FontFace = FONT_TITLE, Text = "0%", TextColor3 = GOLD, TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
}, column)
bar.BackgroundColor3 = Color3.fromRGB(27, 15, 10)
bar.BackgroundTransparency = 0
new("UIStroke", { Color = Color3.fromRGB(90, 59, 40), Thickness = 3 }, bar)
local fillGrad = fill:FindFirstChildOfClass("UIGradient")
fillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 138), Color3.fromRGB(255, 154, 31))
fillGrad.Rotation = 90
local shine = new("Frame", { Position = UDim2.fromScale(0.03, 0.14), Size = UDim2.fromScale(0.94, 0.26), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 2 }, fill)
round(shine, 999)
local marker = new("Frame", {
	Name = "Marker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.04, 0.5), Size = UDim2.fromScale(0, 1.5),
	BackgroundColor3 = CREAM_UI, BorderSizePixel = 0, ZIndex = 3,
}, bar)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, marker)
round(marker, 999)
new("UIStroke", { Color = INK, Thickness = 2 }, marker)
fill:GetPropertyChangedSignal("Size"):Connect(function()
	local x = fill.Size.X.Scale
	percent.Text = math.floor(x * 100 + 0.5) .. "%"
	marker.Position = UDim2.fromScale(x, 0.5)
end)

-- the hint chip (bottom-left): shown while the dusty bear is out
local hint = new("Frame", {
	Name = "Hint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(250, 40),
	BackgroundColor3 = Color3.fromRGB(43, 27, 20), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 5, Visible = false,
}, bg)
round(hint, 20)
new("UIStroke", { Color = Color3.fromRGB(90, 59, 40), Thickness = 2.5 }, hint)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -24, 1, 0), FontFace = FONT_TEXT,
	Text = "✦  Scrub the bear clean!", TextColor3 = CREAM_UI, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
}, hint)

-- the twist: scrub the dusty bear. A second clean picture sits on top and fades in as you scrub; a rag follows your finger.
-- Only the picture changes: the real progress bar and the loading steps never depend on it.
local scrubAmount = 0
local scrubClean = new("ImageLabel", { Name = "BearScrub", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = ART.bearClean, ImageTransparency = 1, ZIndex = 4 }, item)
local scrubRag = new("ImageLabel", {
	Name = "ScrubRag", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.2, 0.2), Rotation = -10, BackgroundTransparency = 1,
	Image = ART.rag, ZIndex = 9, Visible = false,
}, stage)
new("UIAspectRatioConstraint", { AspectRatio = 711 / 550 }, scrubRag)
local zone = new("TextButton", { Name = "ScrubZone", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 10 }, item)
local scrubbing, lastPos, lastPuff = false, Vector2.zero, 0
local function pointer(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end
local function toStage(p: Vector2): Vector2
	return (p - stage.AbsolutePosition) / stage.AbsoluteSize
end
local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
zone.InputBegan:Connect(function(input)
	if isPress(input) then
		scrubbing, lastPos = true, pointer(input)
		local r = toStage(lastPos)
		scrubRag.Position = UDim2.fromScale(r.X, r.Y)
		scrubRag.Visible = true
	end
end)
UIS.InputChanged:Connect(function(input)
	if not scrubbing then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local p = pointer(input)
	local r = toStage(p)
	scrubRag.Position = UDim2.fromScale(r.X, r.Y)
	scrubRag.Rotation = -10 + math.clamp((p.X - lastPos.X) * 2, -14, 14)
	local inside = p.X >= item.AbsolutePosition.X and p.X <= item.AbsolutePosition.X + item.AbsoluteSize.X
		and p.Y >= item.AbsolutePosition.Y and p.Y <= item.AbsolutePosition.Y + item.AbsoluteSize.Y
	if inside and item.Visible then
		scrubAmount = math.min(1, scrubAmount + (p - lastPos).Magnitude / (item.AbsoluteSize.X * 5))
		scrubClean.ImageTransparency = 1 - scrubAmount
		if os.clock() - lastPuff > 0.3 then
			lastPuff = os.clock()
			play("wipe")
			dustPuff(r.X, r.Y)
		end
	end
	lastPos = p
end)
UIS.InputEnded:Connect(function(input)
	if scrubbing and isPress(input) then
		scrubbing = false
		scrubRag.Visible = false
	end
end)
task.spawn(function()
	while gui.Parent do
		hint.Visible = item.Visible and restored.ImageTransparency > 0.9
		task.wait(0.15)
	end
end)

-- ===== the box animation loop: wiggle, the lid pops off (light rays), the find rises, the rag wipes the dust off
-- (puffs), it glows and sparkles, then back in and the lid drops on =====

local running = true

local function pause(seconds: number): boolean
	task.wait(seconds)
	return running
end

-- slow spin for the rays, gentle drift for the dust motes (one Heartbeat for both)
local motePhase = {}
for i, m in motes do
	motePhase[m] = { speed = 0.006 + math.random() * 0.01, sway = math.random() * math.pi * 2, x = m.Position.X.Scale, i = i }
end
local heartbeat = game:GetService("RunService").Heartbeat:Connect(function(dt)
	rays.Rotation = (rays.Rotation + dt * 18) % 360
	local t = os.clock()
	for m, p in motePhase do
		local y = m.Position.Y.Scale - p.speed * dt * 6
		if y < -0.05 then
			y = 1.05
		end
		m.Position = UDim2.fromScale(p.x + math.sin(t * 0.6 + p.sway) * 0.01, y)
	end
end)

local ITEM_IN, ITEM_OUT = UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.5, 0.29)
local ITEM_SMALL, ITEM_BIG = UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.46, 0.46)

local function resetScene()
	boxClosed.Visible = true
	boxBody.Visible, inside.Visible = false, false
	lid.Visible, lid.Position, lid.Rotation, lid.ImageTransparency = false, LID_HOME, 0, 0
	holder.Rotation = 0
	item.Visible, item.Position, item.Size = false, ITEM_IN, ITEM_SMALL
	bearClean.ImageTransparency = 1 -- dusty again
	scrubAmount = 0
	scrubClean.ImageTransparency = 1
	scrubRag.Visible = false
	sparkle.Size, sparkle2.Size = UDim2.fromScale(0, 0), UDim2.fromScale(0, 0)
	restored.ImageTransparency = 1
	restored.Size = UDim2.fromScale(0.8, 0.27)
	rays.Size = UDim2.fromScale(0, 0)
	glowRing.Size, glowRing.BackgroundTransparency, glowStroke.Transparency = UDim2.fromScale(0, 0), 0.55, 0.3
	rag.Visible = false
end

task.spawn(function()
	while running do
		resetScene()
		if not pause(0.35) then
			return
		end
		-- 1. the mystery box wiggles (and hops a little)
		for k, r in { -7, 7, -5, 5, -3, 0 } do
			if k % 2 == 1 then
				play("rattle")
			end
			tween(holder, 0.07, { Rotation = r })
			if not pause(0.08) then
				return
			end
		end
		tween(holder, 0.12, { Position = UDim2.fromScale(0.5, 0.94) })
		if not pause(0.12) then
			return
		end
		tween(holder, 0.18, { Position = UDim2.fromScale(0.5, 0.98) }, Enum.EasingStyle.Bounce)
		-- 2. pop! the lid flies off, light bursts out and the dusty find rises
		play("open")
		boxClosed.Visible = false
		boxBody.Visible, inside.Visible, lid.Visible = true, true, true
		tween(lid, 0.55, { Position = UDim2.fromScale(1.15, -0.55), Rotation = 38, ImageTransparency = 1 }, Enum.EasingStyle.Quad)
		tween(rays, 0.5, { Size = UDim2.fromScale(1.25, 1.25) }, Enum.EasingStyle.Back)
		item.Visible = true
		play("reveal")
		tween(item, 0.55, { Position = ITEM_OUT, Size = ITEM_BIG }, Enum.EasingStyle.Back)
		if not pause(0.7) then
			return
		end
		-- 3. the rag wipes across twice; the clean bear fades in (half, then all) and dust puffs off as it passes
		-- soft and slow (Sean, 2026-11-25): long eased strokes, small tilt, the rag fades in and out of each stroke
		local STROKE = 1.1
		local smooth = Enum.EasingStyle.Sine
		rag.Visible = true
		for pass = 1, 2 do
			local fromX, toX = if pass == 1 then 0.36 else 0.64, if pass == 1 then 0.64 else 0.36
			local y0, y1 = if pass == 1 then 0.22 else 0.33, if pass == 1 then 0.24 else 0.35
			rag.Position = UDim2.fromScale(fromX, y0)
			rag.Rotation = if pass == 1 then -6 else 5
			rag.ImageTransparency = 1
			play("wipe")
			tween(rag, 0.25, { ImageTransparency = 0 }, smooth)
			TweenService:Create(rag, TweenInfo.new(STROKE, smooth, Enum.EasingDirection.InOut), {
				Position = UDim2.fromScale(toX, y1),
				Rotation = if pass == 1 then 3 else -3,
			}):Play()
			TweenService:Create(bearClean, TweenInfo.new(STROKE, smooth, Enum.EasingDirection.InOut), {
				ImageTransparency = if pass == 1 then 0.5 else 0,
			}):Play()
			task.delay(STROKE * 0.45, dustPuff, (fromX + toX) / 2, (y0 + y1) / 2)
			task.delay(STROKE - 0.25, function()
				tween(rag, 0.25, { ImageTransparency = 1 }, smooth)
			end)
			if not pause(STROKE + 0.15) then
				return
			end
		end
		rag.Visible = false
		-- 4. clean: a golden glow ring blooms behind it, a sparkle, and RESTORED! bounces in
		play("restored")
		tween(glowRing, 0.45, { Size = UDim2.fromScale(0.62, 0.62) }, Enum.EasingStyle.Back)
		tween(sparkle, 0.3, { Size = UDim2.fromScale(0.34, 0.34) }, Enum.EasingStyle.Back)
		task.delay(0.15, function()
			tween(sparkle2, 0.3, { Size = UDim2.fromScale(0.22, 0.22) }, Enum.EasingStyle.Back)
		end)
		tween(restored, 0.35, { ImageTransparency = 0, Size = UDim2.fromScale(1.5, 0.5) }, Enum.EasingStyle.Back)
		if not pause(1.2) then
			return
		end
		-- 5. back into the box, the light fades, the lid drops back on
		tween(glowRing, 0.3, { BackgroundTransparency = 1 })
		tween(glowStroke, 0.3, { Transparency = 1 })
		tween(sparkle, 0.2, { Size = UDim2.fromScale(0, 0) })
		tween(sparkle2, 0.2, { Size = UDim2.fromScale(0, 0) })
		tween(restored, 0.2, { ImageTransparency = 1 })
		tween(rays, 0.35, { Size = UDim2.fromScale(0, 0) })
		tween(item, 0.35, { Position = ITEM_IN, Size = ITEM_SMALL }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if not pause(0.3) then
			return
		end
		lid.Position, lid.Rotation, lid.ImageTransparency = UDim2.fromScale(0.5, -0.4), -10, 0
		tween(lid, 0.28, { Position = LID_HOME, Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if not pause(0.28) then
			return
		end
		play("thud")
		boxClosed.Visible = true
		boxBody.Visible, inside.Visible, lid.Visible, item.Visible = false, false, false, false
		tween(holder, 0.08, { Position = UDim2.fromScale(0.5, 1) })
		if not pause(0.08) then
			return
		end
		tween(holder, 0.15, { Position = UDim2.fromScale(0.5, 0.98) }, Enum.EasingStyle.Bounce)
		if not pause(0.6) then
			return
		end
	end
end)

-- tips change every 4.5 s
task.spawn(function()
	local i = math.random(1, #TIPS)
	while running do
		task.wait(4.5)
		if not running then
			return
		end
		i = i % #TIPS + 1
		tween(tipLabel, 0.25, { TextTransparency = 1 }).Completed:Wait()
		tipLabel.Text = "Tip: " .. TIPS[i]
		tween(tipLabel, 0.25, { TextTransparency = 0 })
	end
end)

-- ===== the real loading steps =====

local closed = false
local skipped = false
skip.Activated:Connect(function()
	play("click")
	skipped = true
end)

local function timeLeft(): number
	return MAX_WAIT - (os.clock() - startedAt)
end

-- waits until check() is true, Skip is pressed or time runs out (limit = this step's own cap, if any)
local function waitFor(check: () -> boolean, limit: number?): boolean
	local stepStart = os.clock()
	while not check() do
		if skipped or timeLeft() <= 0 or (limit and os.clock() - stepStart > limit) then
			return false
		end
		task.wait(0.1)
	end
	return true
end

local unpacked = false -- set by the last step once its preload has finished
local steps = {
	{ text = "Loading the town...", check = function()
		return game:IsLoaded()
	end },
	{ text = "Loading your save...", check = function()
		return player:GetAttribute("DF_SaveLoaded") == true
	end },
	{ text = "Finding your shop...", limit = 8, check = function()
		-- standing in the world, with the ground under you streamed in
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return false
		end
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { player.Character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		return workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params) ~= nil
	end },
	{ text = "Opening the doors...", check = function()
		return player:GetAttribute("DF_ClientReady") == true
	end },
	-- let the art catch up: preload my shop, the HUD and the skin models, and wait until Roblox's download queue is
	-- (nearly) empty, so the game doesn't pop in behind the screen; capped by UNPACK_MAX
	{ text = "Unpacking your shop...", limit = UNPACK_MAX, start = function()
		task.spawn(function()
			local list = {}
			local plots = workspace:FindFirstChild("Plots")
			for _, plot in if plots then plots:GetChildren() else {} do
				if plot:GetAttribute("OwnerUserId") == player.UserId then
					table.insert(list, plot)
				end
			end
			local hud = playerGui:FindFirstChild("HUD")
			if hud then
				table.insert(list, hud)
			end
			local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
			local skins = assets and assets:FindFirstChild("Skins")
			if skins then
				table.insert(list, skins)
			end
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(list)
			end)
			unpacked = true
		end)
	end, check = function()
		return unpacked and game:GetService("ContentProvider").RequestQueueSize <= 2
	end },
}

task.spawn(function()
	task.wait(SKIP_AFTER)
	if not closed then
		skip.Visible = true
	end
end)

for i, step in steps do
	stepLabel.Text = step.text
	if step.start then
		step.start()
	end
	-- creep toward the next mark while waiting so the bar never looks frozen
	local creep = tween(fill, 6, { Size = UDim2.fromScale((i - 0.25) / #steps, 1) }, Enum.EasingStyle.Sine)
	local ok = waitFor(step.check, step.limit)
	creep:Cancel()
	tween(fill, 0.3, { Size = UDim2.fromScale(i / #steps, 1) })
	log(step.text, if ok then "done" else "skipped / timed out", string.format("%.1fs", os.clock() - startedAt))
	if skipped or timeLeft() <= 0 then
		break
	end
end

-- Skip only skips the extra waiting (the minimum time, the art preload): it must never drop the player into a
-- half-started game before the title menu exists (bug found by Sean, 2026-11-25). So after a Skip we still wait for
-- the menu (or for the game to be ready), up to the overall time limit.
if skipped then
	skip.Visible = false
	stepLabel.Text = "Almost there..."
	local function menuReady(): boolean
		return playerGui:FindFirstChild("MainMenu") ~= nil or player:GetAttribute("DF_ClientReady") == true
	end
	while not menuReady() and timeLeft() > 0 do
		task.wait(0.1)
	end
	log("after Skip: menu ready =", menuReady(), string.format("%.1fs", os.clock() - startedAt))
end

stepLabel.Text = "Welcome to your shop!"
tween(fill, 0.3, { Size = UDim2.fromScale(1, 1) })
local shown = os.clock() - startedAt
if shown < MIN_SHOW and not skipped then
	task.wait(MIN_SHOW - shown)
end
task.wait(0.4)

-- ===== fade out and clean up =====
closed = true
skip.Visible = false
local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
for _, o in gui:GetDescendants() do
	if o:IsA("TextLabel") or o:IsA("TextButton") then
		TweenService:Create(o, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	elseif o:IsA("ImageLabel") then
		TweenService:Create(o, fade, { ImageTransparency = 1 }):Play()
	elseif o:IsA("Frame") then
		TweenService:Create(o, fade, { BackgroundTransparency = 1 }):Play()
	elseif o:IsA("UIStroke") then
		TweenService:Create(o, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.65)
running = false
heartbeat:Disconnect()
gui:Destroy()
log(string.format("closed after %.1fs%s", os.clock() - startedAt, if skipped then " (skipped)" else ""))
