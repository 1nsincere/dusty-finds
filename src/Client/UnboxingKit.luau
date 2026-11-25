-- UnboxingKit.luau (StarterPlayerScripts.Client.UnboxingKit)
-- Purpose: the tap-to-open show that plays before the Discovery card. A full-screen overlay with a Blender-rendered wooden
-- crate (tools/blender/unbox_crate.py): every tap hits it (squash, jolt, camera shake, sparks) and more light leaks out of its
-- gaps (real renders of the crate at rising glow, so the light comes from the wood, not a circle behind it). 3 taps, 4 for
-- Rare+. The last tap blasts the lid off with a flash, shockwave rings, god rays, embers, confetti and dust, and the find
-- rises in its rarity colour (more power for rarer finds). Taps react on the same frame (no animation ever blocks a tap).
-- Sprites: Blender-made white light textures (tools/blender/unbox_vfx.py), tinted per rarity. Client only: the server already
-- rolled the item (DiscoveryController asks for it first); this only decides how the result is shown.
-- Owner: Dev 1 (Ace) with Claude. Depends on: Shared.Config.Rarities, UiTheme.rarityColor, UiSkin.Art, Lighting (blur).
-- API: Unboxing.Play(info, opts) -> "done" | "skip". info = { itemId, name, rarity, golden }, opts = { quick, reduce, sfx }.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))
local Items = require(Shared.Config:WaitForChild("Items"))
local UiSkin = require(Shared.Config:WaitForChild("UiSkin"))
local UiTheme = require(script.Parent:WaitForChild("UiTheme"))

local Unboxing = {}
local DEBUG = true

local FX = {
	glow = "rbxassetid://93831669035461",
	flare = "rbxassetid://111849707739506",
	star = "rbxassetid://70480965980346",
	rays = "rbxassetid://135275527744049",
	ring = "rbxassetid://119128261946876",
	puff = "rbxassetid://99671732803183",
	bokeh = "rbxassetid://85365306515317",
	shard = "rbxassetid://98894193057604",
	ember = "rbxassetid://85800166901274",
	vignette = "rbxassetid://114364691516249",
}
-- Sean's crate (the same art as the loading screen): the whole closed crate, the crate below its lid, and the lid alone.
-- (A Blender-built wooden crate was tried first and dropped: it read as military. The Blender light/bloom sprites stay.)
local CRATE = {
	closed = "rbxassetid://76804381828872",
	body = "rbxassetid://78407116327087",
	lid = "rbxassetid://129376966282150",
}
local ASPECT = 962 / 845 -- crate picture width / height
local BODY_TOP, BODY_H = 0.3325, 0.6675 -- where the body starts under the lid (fraction of the closed picture)
local LID_ASPECT = 1024 / 322
local CRATE_W = 0.62 -- crate width as a fraction of the stage
local CRATE_H = CRATE_W / ASPECT
local CRATE_POS = Vector2.new(0.5, 0.6) -- its centre
local MOUTH = Vector2.new(0.5, CRATE_POS.Y - CRATE_H / 2 + CRATE_H * BODY_TOP) -- the seam: where the light comes out
local MAX_PARTICLES = 140

local FONT_TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_TEXT = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
local INK = Color3.fromRGB(43, 27, 20)
local CREAM = Color3.fromRGB(255, 241, 214)
local WHITE = Color3.new(1, 1, 1)

local gui: ScreenGui? = nil

local function log(...)
	if DEBUG then
		print("[UnboxingKit]", ...)
	end
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

local function tween(o: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(o, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function sprite(parent: Instance, image: string, x: number, y: number, size: number, color: Color3, transparency: number, z: number): ImageLabel
	return new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = 1,
		Image = image,
		ImageColor3 = color,
		ImageTransparency = transparency,
		ZIndex = z,
	}, parent)
end

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	gui = new("ScreenGui", {
		Name = "Unboxing",
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ResetOnSpawn = false,
		DisplayOrder = 700, -- over the HUD and the Discovery card, under the title menu
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	return gui :: ScreenGui
end

-- A ViewportFrame showing the item's model from ReplicatedStorage.Assets.Items (the model name is Items[itemId].model, every
-- item has one). Returns the viewport and a function(angle) that orbits the camera round the model (call it every frame to
-- make it turn). nil when the model is missing. Also used by the Discovery card.
local function itemViewport(parent: Instance, itemId: string): (ViewportFrame?, ((number) -> ())?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	local def = Items[itemId]
	local template = items and (items:FindFirstChild(def and def.model or itemId) or items:FindFirstChild(itemId))
	if not template then
		return nil, nil
	end
	local vp = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		LightColor = Color3.fromRGB(255, 240, 215),
		Ambient = Color3.fromRGB(140, 120, 110),
		LightDirection = Vector3.new(-0.6, -1, -0.5),
		ZIndex = 20,
	}, parent)
	local model = template:Clone()
	if not model:IsA("Model") then
		local wrap = Instance.new("Model")
		model.Parent = wrap
		model = wrap
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	cam.Parent = vp
	vp.CurrentCamera = cam
	local dist = math.max(size.X, size.Y, size.Z) * 2.5
	local function orbit(angle: number)
		local eye = cf.Position + Vector3.new(math.sin(angle) * dist, size.Y * 0.35, math.cos(angle) * dist)
		cam.CFrame = CFrame.lookAt(eye, cf.Position)
	end
	orbit(0.5)
	return vp, orbit
end

Unboxing.ItemViewport = itemViewport
Unboxing.FX = FX

-- Plays the show. Yields until it is over. Returns "skip" if the player pressed Skip all.
function Unboxing.Play(info: { itemId: string, name: string?, rarity: string?, golden: boolean? }, opts: { quick: boolean?, reduce: boolean?, sfx: ((string) -> ())?, autoTap: number? }?): string
	opts = opts or {}
	local quick = opts.quick == true
	local reduce = opts.reduce == true
	local function sfx(name: string)
		if opts.sfx then
			opts.sfx(name)
		end
	end

	local rarityName = info.rarity or "Common"
	local def = Rarities[rarityName]
	local power = math.clamp((def and def.index or 1) + (if info.golden then 1 else 0), 1, 8) -- 1 (Common) .. 8
	local color = UiTheme.rarityColor(rarityName)
	local hot = color:Lerp(WHITE, 0.45)
	local taps = if quick or reduce then 1 elseif power >= 3 then 4 else 3
	local intensity = if quick then 0.65 else 1

	local screen = ensureGui()
	screen.Enabled = true
	local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true }, screen)
	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 6, 5), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, root)
	local vig = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = FX.vignette, ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 1, ZIndex = 2 }, root)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1, ZIndex = 3 }, root)
	local stage = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, holder)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, stage)
	local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 60 }, root)

	local blur = Lighting:FindFirstChild("DfUnboxBlur") or new("BlurEffect", { Name = "DfUnboxBlur", Size = 0 }, Lighting)
	tween(blur, 0.2, { Size = if reduce then 6 else 12 })
	tween(dim, 0.2, { BackgroundTransparency = 0.3 })
	tween(vig, 0.2, { ImageTransparency = 0.25 })

	-- layers (low to high): rays, crate, particles / rings / flare, reveal
	local rays = sprite(stage, FX.rays, MOUTH.X, MOUTH.Y, 1.7, color, 1, 5)
	local crate = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(CRATE_POS.X, CRATE_POS.Y), Size = UDim2.fromScale(CRATE_W, CRATE_H),
		BackgroundTransparency = 1, ZIndex = 10,
	}, stage)
	local crateScale = new("UIScale", {}, crate)
	local shadow = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1.02), Size = UDim2.fromScale(1.15, 0.2), BackgroundTransparency = 1,
		Image = FX.glow, ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.4, ZIndex = 9,
	}, crate)
	-- the open crate's dark inside, with a pool of light in it (shown after the burst)
	local inside = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, BODY_TOP + 0.012), Size = UDim2.fromScale(0.9, 0.1), BackgroundColor3 = Color3.fromRGB(58, 36, 22),
		BorderSizePixel = 0, ZIndex = 10, Visible = false,
	}, crate)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, inside)
	local insideLight = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, BODY_TOP + 0.01), Size = UDim2.fromScale(1.1, 0.5), BackgroundTransparency = 1,
		Image = FX.glow, ImageColor3 = Color3.fromRGB(255, 220, 140), ImageTransparency = 1, ZIndex = 12,
	}, crate)
	local crateImg = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = CRATE.closed, ZIndex = 11 }, crate)
	local lit = new("ImageLabel", { -- the same crate again in hot light, faded in tap by tap: the wood itself gets brighter
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = CRATE.closed, ImageColor3 = Color3.fromRGB(255, 226, 150), ImageTransparency = 1, ZIndex = 13,
	}, crate)
	local openImg = new("ImageLabel", { Position = UDim2.fromScale(0, BODY_TOP), Size = UDim2.fromScale(1, BODY_H), BackgroundTransparency = 1, Image = CRATE.body, ZIndex = 11, Visible = false }, crate)
	local lid = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromScale(1.12, 1.12 * ASPECT / LID_ASPECT),
		BackgroundTransparency = 1, Image = CRATE.lid, ZIndex = 14, Visible = false,
	}, crate)
	-- light leaking out along the lid seam: a soft wide bloom, a hot thin line, and beams that grow with every tap
	local seamBloom = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, BODY_TOP), Size = UDim2.fromScale(1.15, 0.32), BackgroundTransparency = 1,
		Image = FX.glow, ImageColor3 = Color3.fromRGB(255, 205, 110), ImageTransparency = 1, ZIndex = 15,
	}, crate)
	local seamLine = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, BODY_TOP + 0.003), Size = UDim2.fromScale(0.9, 0.012), BackgroundColor3 = Color3.fromRGB(255, 240, 190),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 16,
	}, crate)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, seamLine)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }) }, seamLine)
	-- No static beams: the light is alive. `leak` is how hard it is trying to get out; every frame the bloom and the seam line
	-- flicker with noise, light slivers squirt out of the cracks and die, and a glint sweeps across the lid (all driven by leak).
	local sheenClip = new("Frame", { Name = "SheenClip", Size = UDim2.fromScale(1, BODY_TOP + 0.03), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 16 }, crate)
	local fxLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, stage)
	local revealLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 }, stage)
	-- the lens streak along the seam (flares on every tap)
	local streak = sprite(fxLayer, FX.flare, MOUTH.X, MOUTH.Y, 0.3, WHITE, 1, 22)

	local hint = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.93), Size = UDim2.fromScale(0.5, 0.05), BackgroundTransparency = 1,
		FontFace = FONT_TITLE, Text = "TAP THE CRATE!", TextColor3 = CREAM, TextScaled = true, ZIndex = 40,
	}, stage)
	new("UIStroke", { Color = INK, Thickness = 3 }, hint)
	local pips = {}
	for i = 1, taps do
		local p = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + (i - (taps + 1) / 2) * 0.055, 0.08), Size = UDim2.fromScale(0.03, 0.03),
			BackgroundColor3 = Color3.fromRGB(90, 59, 40), BorderSizePixel = 0, ZIndex = 40, Visible = not (quick or reduce),
		}, stage)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, p)
		new("UIStroke", { Color = INK, Thickness = 2 }, p)
		pips[i] = p
	end
	local skipBtn = new("TextButton", {
		Name = "SkipButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 20), Size = UDim2.fromOffset(120, 40), BackgroundColor3 = INK, BackgroundTransparency = 0.15,
		FontFace = FONT_TEXT, Text = "SKIP ALL ▶", TextColor3 = CREAM, TextSize = 17, AutoButtonColor = true, ZIndex = 70,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 20) }, skipBtn)
	new("UIStroke", { Color = Color3.fromRGB(90, 59, 40), Thickness = 2.5 }, skipBtn)
	new("UIScale", { Scale = math.clamp((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720) / 720, 0.7, 1.25) }, skipBtn)

	-- ===== particles + shake: one Heartbeat =====
	local particles = {}
	local rayFade = 0
	local shake = 0
	local t0 = os.clock()
	local function spawn(image: string, x: number, y: number, vx: number, vy: number, gravity: number, life: number, s0: number, s1: number, a0: number, tint: Color3, spin: number?, z: number?)
		if reduce or #particles >= MAX_PARTICLES then
			return
		end
		local o = sprite(fxLayer, image, x, y, s0, tint, 1, z or 1)
		table.insert(particles, { o = o, x = x, y = y, vx = vx, vy = vy, g = gravity, life = life, age = 0, s0 = s0, s1 = s1, a0 = a0, spin = spin or 0, rot = math.random() * 360 })
	end
	-- ----- the living light at the seam -----
	local leak, leakTarget = 0.12, 0.12 -- 0 = nothing .. ~1 = blazing; taps push it up, it settles back toward the target
	local seamActive = true -- false once the lid has gone (the burst takes over)
	local burstDone = false -- after the burst: the open crate's light keeps flickering and shooting slivers
	local emitAcc, sweepAcc = 0, 0.5
	local slivers = {}
	local WARM = Color3.fromRGB(255, 226, 150)
	local function spawnSliver(big: number?)
		if reduce or #slivers >= 45 then
			return
		end
		local x = MOUTH.X + (math.random() - 0.5) * CRATE_W * 0.82
		local h = (0.1 + math.random() * 0.22) * (0.55 + 0.6 * leak) * (big or 1)
		local w = 0.018 + math.random() * 0.03
		local o = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, MOUTH.Y + 0.012), Size = UDim2.fromScale(w, h * 0.3), BackgroundTransparency = 1,
			Image = FX.ember, ImageColor3 = if math.random() < 0.3 then WHITE else WARM, ImageTransparency = 1, ZIndex = 21,
		}, fxLayer)
		table.insert(slivers, { o = o, x = x, y = MOUTH.Y + 0.012, w = w, h = h, age = 0, life = 0.28 + math.random() * 0.45, sway = math.random() * 6.28, vy = -(0.04 + math.random() * 0.14) })
	end
	local function sweep()
		-- a bright glint slides across the lid, like light catching the wood as it flexes
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.15, 0.5), Size = UDim2.fromScale(0.13, 1.7), Rotation = 18,
			BackgroundColor3 = Color3.fromRGB(255, 244, 210), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 17,
		}, sheenClip)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, math.clamp(0.7 - 0.4 * leak, 0.2, 0.8)), NumberSequenceKeypoint.new(1, 1) }) }, bar)
		tween(bar, 0.5 - 0.15 * math.min(leak, 1), { Position = UDim2.fromScale(1.15, 0.5) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.delay(0.6, function()
			bar:Destroy()
		end)
	end

	local conn = RunService.Heartbeat:Connect(function(dt)
		for i = #particles, 1, -1 do
			local p = particles[i]
			p.age += dt
			local t = p.age / p.life
			if t >= 1 then
				p.o:Destroy()
				table.remove(particles, i)
			else
				p.vy += p.g * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
				local s = lerp(p.s0, p.s1, t)
				p.rot += p.spin * dt
				p.o.Position = UDim2.fromScale(p.x, p.y)
				p.o.Size = UDim2.fromScale(s, s)
				p.o.Rotation = p.rot
				p.o.ImageTransparency = 1 - p.a0 * math.min(t / 0.06, 1) * (1 - t) ^ 0.6
			end
		end
		rays.Rotation = (os.clock() - t0) * 16
		rays.ImageTransparency = 1 - rayFade
		-- the light at the seam: flickers with noise (never the same twice), settles toward its target after every tap
		local tNow = os.clock() - t0
		leak += (leakTarget - leak) * math.min(1, dt * 5)
		if seamActive then
			local n = math.clamp(0.5 + math.noise(tNow * 7.3, 0.5) * 0.9 + math.noise(tNow * 19.7, 4.2) * 0.4, 0, 1)
			local lv = math.min(leak, 1.3)
			seamBloom.ImageTransparency = math.clamp(0.9 - 0.7 * lv * (0.65 + 0.55 * n), 0.05, 1)
			seamBloom.Size = UDim2.fromScale(1.1 + 0.25 * lv, 0.24 + 0.22 * lv * (0.8 + 0.4 * n))
			seamLine.BackgroundTransparency = math.clamp(1 - lv * (0.45 + 0.65 * n), 0, 1)
			seamLine.Size = UDim2.fromScale(0.9, 0.005 + 0.024 * lv * (0.5 + 0.9 * n))
			lit.ImageTransparency = math.clamp(0.93 - 0.5 * lv * (0.7 + 0.5 * n), 0.2, 1)
			emitAcc += dt * (1.5 + 22 * lv)
			while emitAcc >= 1 do
				emitAcc -= 1
				spawnSliver()
			end
			sweepAcc -= dt
			if sweepAcc <= 0 and not reduce then
				sweepAcc = math.max(0.3, 2.0 - 1.5 * math.min(lv, 1)) + math.random() * 0.5
				sweep()
			end
		end
		if burstDone then
			local n2 = math.clamp(0.5 + math.noise(tNow * 6.1, 9.3) * 0.9 + math.noise(tNow * 21.3, 2.2) * 0.4, 0, 1)
			insideLight.ImageTransparency = math.clamp(0.28 - 0.3 * n2, 0, 1)
			emitAcc += dt * (6 + 10 * math.min(leak, 1))
			while emitAcc >= 1 do
				emitAcc -= 1
				spawnSliver(1.5)
			end
		end
		for i = #slivers, 1, -1 do
			local s = slivers[i]
			s.age += dt
			local t = s.age / s.life
			if t >= 1 then
				s.o:Destroy()
				table.remove(slivers, i)
			else
				s.y += s.vy * dt
				local grow = 0.3 + 0.7 * math.min(t / 0.3, 1)
				s.o.Position = UDim2.fromScale(s.x, s.y)
				s.o.Size = UDim2.fromScale(s.w * (1 - 0.3 * t), s.h * grow)
				s.o.Rotation = math.sin(t * 9 + s.sway) * 8
				s.o.ImageTransparency = 1 - 0.95 * math.min(t / 0.1, 1) * (1 - t) ^ 1.3
			end
		end
		if shake > 0.0004 then
			stage.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * shake, 0.5 + (math.random() - 0.5) * shake)
			shake *= 0.8
		elseif stage.Position ~= UDim2.fromScale(0.5, 0.5) then
			stage.Position = UDim2.fromScale(0.5, 0.5)
		end
	end)

	-- the crate drops in and lands with a thud and a puff of dust, then breathes while it waits for the first tap
	local count = 0 -- taps so far
	if not reduce then
		local home = UDim2.fromScale(CRATE_POS.X, CRATE_POS.Y)
		crate.Position = UDim2.fromScale(CRATE_POS.X, CRATE_POS.Y - 0.55)
		tween(crate, 0.4, { Position = home }, Enum.EasingStyle.Bounce)
		task.delay(0.24, function()
			sfx("unboxLand")
			shake = 0.012
			for _ = 1, 4 do
				spawn(FX.puff, CRATE_POS.X + (math.random() - 0.5) * CRATE_W, CRATE_POS.Y + CRATE_H / 2, (math.random() - 0.5) * 0.3, -0.03 - math.random() * 0.03, 0, 0.8 + math.random() * 0.4, 0.08, 0.2, 0.45, Color3.fromRGB(235, 222, 200), (math.random() - 0.5) * 20, 8)
			end
		end)
		task.delay(0.5, function()
			while crate.Parent and count == 0 do
				tween(crateScale, 0.7, { Scale = 1.025 }, Enum.EasingStyle.Sine)
				task.wait(0.7)
				if count > 0 or not crate.Parent then
					break
				end
				tween(crateScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Sine)
				task.wait(0.7)
			end
		end)
	end

	-- ===== input =====
	local tapEvent = Instance.new("BindableEvent")
	local phase = Instance.new("BindableEvent") -- "burst" | "skip"
	local skipped = false
	local tapZone = new("TextButton", { Name = "TapZone", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 50 }, root)
	tapZone.Activated:Connect(function()
		tapEvent:Fire()
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA) then
			tapEvent:Fire()
		end
	end)
	skipBtn.Activated:Connect(function()
		skipped = true
		phase:Fire("skip")
		tapEvent:Fire()
	end)

	local function cleanup()
		conn:Disconnect()
		keyConn:Disconnect()
		tween(blur, 0.2, { Size = 0 })
		tween(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.25, function()
			root:Destroy()
			screen.Enabled = false
			if blur.Parent and blur.Size < 0.5 then
				blur:Destroy()
			end
		end)
	end

	task.spawn(function() -- hint pulse
		while hint.Parent and hint.Visible do
			tween(hint, 0.5, { TextTransparency = 0.4 }, Enum.EasingStyle.Sine)
			task.wait(0.5)
			if not hint.Parent then
				break
			end
			tween(hint, 0.5, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
			task.wait(0.5)
		end
	end)

	-- ===== a tap: reacts on the same frame, never blocks the next tap =====
	local jolt = 0 -- bumped every tap so an older shake stops when a newer one starts
	local function onTap(n: number)
		local t = n / taps
		sfx("unboxTap" .. math.min(n, 4))
		pips[n].BackgroundColor3 = if n == taps then hot else CREAM
		-- more light leaks out of the seam: the target rises, and every hit makes it flare up and then settle back (it flickers
		-- by itself every frame, see the Heartbeat above); a burst of slivers squirts out on the hit
		local lv = if taps == 1 then 0.85 else t
		leakTarget = 0.3 + 0.75 * lv
		leak = leakTarget + 0.55
		if not reduce then
			for _ = 1, 5 + n * 3 do
				spawnSliver(1.3)
			end
			sweepAcc = 0 -- a glint right away
		end
		if reduce then
			return
		end
		jolt += 1
		local mine = jolt
		shake = 0.006 + 0.014 * t
		crateScale.Scale = 0.9 - 0.03 * t -- the hit: squash down at once, then spring back past 1
		tween(crateScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.spawn(function()
			local dir = if n % 2 == 1 then 1 else -1
			for _, r in { 4 + 5 * t, -3 - 4 * t, 2 + 2 * t, 0 } do
				if jolt ~= mine then
					return
				end
				tween(crate, 0.04, { Rotation = r * dir })
				task.wait(0.045)
			end
		end)
		-- sparks squirting out of the cracks
		for _ = 1, 3 + n * 2 do
			local x = MOUTH.X + (math.random() - 0.5) * CRATE_W * 0.6
			local a = math.rad(-90 + (math.random() - 0.5) * 60)
			local sp = 0.25 + math.random() * 0.35 * (0.6 + t)
			spawn(FX.ember, x, MOUTH.Y + 0.02, math.cos(a) * sp, math.sin(a) * sp, 0.8, 0.5 + math.random() * 0.4, 0.035, 0.012, 1, if math.random() < 0.6 then Color3.fromRGB(255, 226, 150) else WHITE, 0, 23)
		end
		for _ = 1, 1 + n do
			local x = MOUTH.X + (math.random() - 0.5) * CRATE_W * 0.7
			local g = sprite(fxLayer, FX.star, x, MOUTH.Y + 0.03 + math.random() * 0.12, 0.03, WHITE, 1, 24)
			local s = 0.06 + 0.07 * math.random() * (0.5 + t)
			g.Rotation = math.random(-15, 15)
			tween(g, 0.07, { ImageTransparency = 0, Size = UDim2.fromScale(s, s) })
			task.delay(0.07, function()
				tween(g, 0.25, { ImageTransparency = 1, Size = UDim2.fromScale(s * 0.3, s * 0.3), Rotation = g.Rotation + 35 })
				task.delay(0.3, function()
					g:Destroy()
				end)
			end)
		end
	end
	local tapConn = tapEvent.Event:Connect(function()
		if skipped or count >= taps then
			return
		end
		count += 1
		local ok, err = pcall(onTap, count) -- a visual hiccup must never stop the crate from opening
		if not ok then
			warn("[UnboxingKit] tap effect failed:", err)
		end
		if count == taps then
			phase:Fire("burst")
		end
	end)
	if opts.autoTap then -- test hook (DevTools / console): seconds between automatic taps
		task.spawn(function()
			while root.Parent and count < taps and not skipped do
				task.wait(opts.autoTap :: number)
				if root.Parent then
					tapEvent:Fire()
				end
			end
		end)
	end

	if phase.Event:Wait() == "skip" then
		tapConn:Disconnect()
		cleanup()
		return "skip"
	end
	tapZone.Visible = false
	hint.Visible = false

	-- ===== the burst: hit-stop, then everything at once =====
	sfx("unboxBurst")
	if not reduce then
		tween(crateScale, 0.07, { Scale = 0.86 })
		task.wait(0.08)
	end
	local revealAt = os.clock()
	crateImg.Visible = false
	lit.Visible = false
	openImg.Visible = true
	inside.Visible = true
	lid.Visible = true
	-- the seam light turns into the pool of light pouring out of the open crate
	tween(insideLight, 0.12, { ImageTransparency = 0.05, Size = UDim2.fromScale(1.4, 0.7) })
	tween(seamBloom, 0.2, { ImageTransparency = 0.25, Size = UDim2.fromScale(1.5, 0.55) })
	tween(seamLine, 0.15, { BackgroundTransparency = 1 })
	seamActive = false -- the lid is gone: from here the open crate's light flickers instead (burstDone, in the Heartbeat)
	burstDone = true
	sheenClip.Visible = false
	if not reduce then
		for _ = 1, 16 do
			spawnSliver(2.2) -- a fan of long light slivers shoots out of the opening
		end
	end
	tween(crateScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Elastic)
	if reduce then
		tween(lid, 0.25, { ImageTransparency = 1 })
	else
		-- the lid is torn off: up and to the side, spinning, then gone
		tween(lid, 0.6, { Position = UDim2.fromScale(1.15, -0.55), Rotation = 62 }, Enum.EasingStyle.Quad)
		task.delay(0.3, function()
			tween(lid, 0.3, { ImageTransparency = 1 })
		end)
	end
	flash.BackgroundColor3 = hot
	flash.BackgroundTransparency = 1 - (if reduce then 0.2 else (0.4 + power * 0.07) * intensity)
	tween(flash, 0.32, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	shake = 0.035 * intensity * (0.6 + power * 0.1)
	rayFade = (0.5 + power * 0.07) * intensity
	rays.ImageColor3 = color
	rays.Size = UDim2.fromScale(0.25, 0.25)
	tween(rays, 0.5, { Size = UDim2.fromScale(1.7 + power * 0.1, 1.7 + power * 0.1) }, Enum.EasingStyle.Quint)
	if not reduce then
		streak.ImageColor3 = hot
		streak.Size = UDim2.fromScale(0.3, 0.3)
		streak.ImageTransparency = 0
		tween(streak, 0.5, { Size = UDim2.fromScale(1.5 * intensity + power * 0.06, 1.5 * intensity + power * 0.06), ImageTransparency = 1 }, Enum.EasingStyle.Quad)
		for k = 1, (if power >= 4 then 2 else 1) do
			task.delay((k - 1) * 0.09, function()
				local r = sprite(fxLayer, FX.ring, MOUTH.X, MOUTH.Y, 0.15, if k == 1 then hot else color, 0.05, 22)
				tween(r, 0.55 + 0.12 * k, { Size = UDim2.fromScale(1.7 * intensity + 0.3, 1.7 * intensity + 0.3), ImageTransparency = 1 }, Enum.EasingStyle.Quad)
				task.delay(0.9, function()
					r:Destroy()
				end)
			end)
		end
		for _ = 1, math.floor((16 + power * 6) * intensity) do -- embers: fast, hot, with gravity
			local a = math.rad(-90 + (math.random() - 0.5) * 150)
			local sp = 0.5 + math.random() * 0.8
			spawn(FX.ember, MOUTH.X, MOUTH.Y, math.cos(a) * sp, math.sin(a) * sp, 1.1, 0.7 + math.random() * 0.7, 0.055, 0.02, 1, if math.random() < 0.5 then hot else color, 0, 26)
		end
		for _ = 1, 5 do
			spawn(FX.puff, MOUTH.X + (math.random() - 0.5) * 0.3, MOUTH.Y + 0.04, (math.random() - 0.5) * 0.3, -0.06 - math.random() * 0.1, 0, 1.1 + math.random() * 0.5, 0.12, 0.3 + math.random() * 0.15, 0.5, Color3.fromRGB(235, 222, 200), (math.random() - 0.5) * 20, 8)
		end
		if power >= 3 then
			local cols = { color, hot, Color3.fromRGB(255, 200, 58), WHITE }
			for _ = 1, math.floor(power * 8 * intensity) do
				local a = math.rad(-90 + (math.random() - 0.5) * 120)
				local sp = 0.6 + math.random() * 0.9
				spawn(FX.shard, MOUTH.X, MOUTH.Y, math.cos(a) * sp, math.sin(a) * sp, 1.5, 1.2 + math.random() * 0.9, 0.035, 0.035, 1, cols[math.random(1, #cols)], (math.random() - 0.5) * 600, 25)
			end
		end
		if power >= 5 then
			for _ = 1, 14 do
				spawn(FX.bokeh, math.random(), 0.45 + math.random() * 0.5, (math.random() - 0.5) * 0.04, -0.06 - math.random() * 0.06, 0, 2.2 + math.random() * 1.2, 0.05 + math.random() * 0.1, 0.07 + math.random() * 0.1, 0.45, hot, 0, 6)
			end
		end
	end

	-- the find rises out of the light
	local item = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.34, 0.34), BackgroundTransparency = 1, ZIndex = 30 }, revealLayer)
	local itemScale = new("UIScale", { Scale = 0.2 }, item)
	sprite(item, FX.glow, 0.5, 0.5, 1.9, color, 0.1, 1)
	local viewport, orbit = itemViewport(item, info.itemId)
	if not viewport then
		sprite(item, UiSkin.Art("Star"), 0.5, 0.5, 0.62, WHITE, 0, 20) -- no real model yet (Dev 2): a star badge
	end
	if not reduce and power >= 2 then
		for i = 1, 3 + power do
			local a = (i / (3 + power)) * math.pi * 2
			local g = sprite(item, FX.star, 0.5 + math.cos(a) * 0.55, 0.5 + math.sin(a) * 0.55, 0.12 + math.random() * 0.1, if i % 2 == 0 then WHITE else hot, 1, 21)
			task.delay(0.15 + i * 0.04, function()
				tween(g, 0.15, { ImageTransparency = 0.1 })
				task.delay(0.4 + math.random() * 0.3, function()
					tween(g, 0.3, { ImageTransparency = 1, Rotation = 60 })
				end)
			end)
		end
	end
	local rise = if reduce then 0.25 else 0.5
	tween(item, rise, { Position = UDim2.fromScale(0.5, 0.34) }, Enum.EasingStyle.Back)
	tween(itemScale, rise, { Scale = 1 }, Enum.EasingStyle.Back)
	sfx("unboxReveal")
	-- the sound of a chest really coming open: wood cracking, then a shimmer; rarer finds get a bright rising chime on top
	sfx("unboxCrack")
	task.delay(0.12, function()
		sfx("unboxShimmer")
	end)
	if power >= 4 then
		task.delay(0.3, function()
			sfx("levelUp")
		end)
	end
	-- the leftover seam light dims slowly instead of staying frozen
	task.delay(0.4, function()
		leakTarget = 0.45 -- the pouring light settles into a steady, flickering glow
		tween(seamBloom, 1.2, { ImageTransparency = 0.7 })
	end)

	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.9, 0.09), BackgroundTransparency = 1,
		FontFace = FONT_TITLE, Text = string.upper(info.name or info.itemId), TextColor3 = WHITE, TextScaled = true, TextTransparency = 1, ZIndex = 36,
	}, revealLayer)
	new("UIGradient", { Color = ColorSequence.new(WHITE, hot), Rotation = 90 }, label)
	local lstroke = new("UIStroke", { Color = INK, Thickness = 4, Transparency = 1 }, label)
	local pill = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(0.26, 0.06), BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 36 }, revealLayer)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
	local pstroke = new("UIStroke", { Color = INK, Thickness = 3, Transparency = 1 }, pill)
	local ptext = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, FontFace = FONT_TITLE, Text = string.upper(rarityName) .. (if info.golden then "  ·  GOLDEN" else ""),
		TextColor3 = INK, TextScaled = true, TextTransparency = 1, ZIndex = 37,
	}, pill)
	new("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, ptext)
	task.delay(if reduce then 0.05 else 0.22, function()
		tween(label, 0.22, { TextTransparency = 0 }, Enum.EasingStyle.Back)
		tween(lstroke, 0.22, { Transparency = 0 })
		tween(pill, 0.22, { BackgroundTransparency = 0 })
		tween(pstroke, 0.22, { Transparency = 0 })
		tween(ptext, 0.22, { TextTransparency = 0 })
	end)
	if not quick then
		local starCount = math.min(def and def.index or 1, 8)
		for i = 1, starCount do
			local s = sprite(revealLayer, UiSkin.Art("Star"), 0.5 + (i - (starCount + 1) / 2) * 0.06, 0.78, 0, WHITE, 0, 36)
			task.delay(0.35 + i * 0.07, function()
				tween(s, 0.2, { Size = UDim2.fromScale(0.055, 0.055) }, Enum.EasingStyle.Back)
			end)
		end
	end

	local spinConn
	if orbit then
		local started = os.clock()
		spinConn = RunService.Heartbeat:Connect(function()
			orbit(0.5 + (os.clock() - started) * 1.3)
		end)
	end

	-- hold, then hand over to the Discovery card (a tap after a moment, or Skip all, shortens it)
	local hold = if reduce then 0.6 elseif quick then 0.7 else 1.15 + power * 0.1
	local early = false
	local holdConn = tapEvent.Event:Connect(function()
		if os.clock() - revealAt > 0.45 then
			early = true
		end
	end)
	local holdTap = UserInputService.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and os.clock() - revealAt > 0.45 then
			early = true
		end
	end)
	while os.clock() - revealAt < hold and not early and not skipped do
		task.wait(0.03)
	end
	holdConn:Disconnect()
	holdTap:Disconnect()
	tapConn:Disconnect()
	if spinConn then
		spinConn:Disconnect()
	end
	tween(item, 0.15, { Position = UDim2.fromScale(0.5, 0.3) })
	tween(itemScale, 0.15, { Scale = 1.12 })
	cleanup()
	log("played:", info.itemId, rarityName, "power", power, "taps", taps, if quick then "(quick)" else "", if skipped then "(skip all)" else "")
	return if skipped then "skip" else "done"
end

return Unboxing
