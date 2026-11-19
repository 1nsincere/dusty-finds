-- LightingController.luau
-- Purpose: the day/night cycle and the town's mood. Blends Lighting, Atmosphere, Bloom, colour grade and sun rays
-- through Config.DayNight keyframes. Night is lit by the sky (moonlight + ambient) plus the Philippine-style street
-- lights (TownT2.StreetLights), each with its own fixed orange SpotLight that is on all night; decorative lanterns and
-- windows only take a warm tint, and every shop gets one fixed warm ceiling light. No lights follow the camera, so
-- nothing switches on/off as you move. Client only: every change is local.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.DayNight, ClientState (settings.reduceEffects), Lighting children
-- (Atmosphere, BloomEffect, ColorCorrectionEffect, SunRaysEffect, Sky), Workspace.Plots.PlotN.Floor.
-- Time = workspace:GetServerTimeNow(), so all players on a server share the same time of day without any remote.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local DayNight = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("DayNight"))

local LightingController = {}
local DEBUG = true

local UPDATE_EVERY = 0.1 -- seconds between look updates (the clock moves slowly; 10 Hz is smooth)
local LAMP_NAMES = { StairPostLamp = true, Lantern = true, Bulb = true, PierLamp = true }
local WINDOW_ROOTS = { "BlenderHouses", "BlenderBuildings" } -- under Workspace.CanalTownWow

type Saved = { material: Enum.Material, color: Color3, transparency: number, reflectance: number }

local lamps: { [BasePart]: Saved } = {}
local windows: { [BasePart]: Saved } = {}
local streetLenses: { [BasePart]: Light } = {} -- SodiumLens -> its fixed SpotLight (all on at night, no distance logic)
local fillLights: { Light } = {} -- invisible NightFill PointLights (all on at night unless Reduce effects)
local shopLights: { PointLight } = {}
local lightsOn: boolean? = nil
local reduceEffects = false
local lastSegment = ""

local atmosphere: Atmosphere?
local bloom: BloomEffect?
local grade: ColorCorrectionEffect?
local sunRays: SunRaysEffect?

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function save(part: BasePart): Saved
	return { material = part.Material, color = part.Color, transparency = part.Transparency, reflectance = part.Reflectance }
end

-- Which clock hour it is right now, following the SEGMENTS pacing (shared by everyone through server time).
local cycleLength = 0
for _, seg in DayNight.SEGMENTS do
	cycleLength += seg.seconds
end

local function currentClock(): (number, string)
	-- Testing aid: set a number attribute PreviewClock on Lighting (e.g. 21) to hold that time; remove it to resume.
	local preview = Lighting:GetAttribute("PreviewClock")
	if type(preview) == "number" then
		return preview % 24, "Preview"
	end
	local t = workspace:GetServerTimeNow() % cycleLength
	for _, seg in DayNight.SEGMENTS do
		if t < seg.seconds then
			return (seg.from + (seg.to - seg.from) * (t / seg.seconds)) % 24, seg.name
		end
		t -= seg.seconds
	end
	local last = DayNight.SEGMENTS[#DayNight.SEGMENTS]
	return last.to % 24, last.name
end

-- Blend the two keyframes around `clock` (wrapping past midnight).
local function sample(clock: number)
	local keys = DayNight.KEYS
	local a, b = keys[#keys], keys[1]
	local aClock, bClock = a.clock - 24, b.clock
	for i = 1, #keys do
		local nextKey = keys[i + 1]
		local nextClock = nextKey and nextKey.clock or (keys[1].clock + 24)
		if clock >= keys[i].clock and clock < nextClock then
			a, b = keys[i], nextKey or keys[1]
			aClock, bClock = keys[i].clock, nextClock
			break
		end
	end
	local t = if bClock > aClock then math.clamp((clock - aClock) / (bClock - aClock), 0, 1) else 0
	return a, b, t
end

local function isLampPart(part: BasePart): boolean
	if LAMP_NAMES[part.Name] then
		return true
	end
	local parent = part.Parent
	return parent ~= nil and string.sub(parent.Name, -5) == "_Lamp"
end

local function isWindowPart(part: BasePart): boolean
	local parent = part.Parent
	if not parent or not part:IsA("MeshPart") then
		return false
	end
	if not (string.sub(parent.Name, -6) == "_Glass" or string.sub(parent.Name, -8) == "_UpGlass") then
		return false
	end
	local wow = workspace:FindFirstChild("CanalTownWow")
	for _, rootName in WINDOW_ROOTS do
		local root = wow and wow:FindFirstChild(rootName)
		if root and part:IsDescendantOf(root) then
			return true
		end
	end
	-- the upper floor of each shop (the ground floor glass stays clear so you can see into the shop)
	return parent.Parent ~= nil and parent.Parent.Name == "Upper"
end

local function applyLamp(part: BasePart, saved: Saved, on: boolean)
	local cfg = DayNight.LAMP_NIGHT
	-- many bulbs are Neon in the model itself: by day they are always matte, at night they glow only if cfg.glow
	local dayMaterial = if saved.material == Enum.Material.Neon then Enum.Material.SmoothPlastic else saved.material
	part.Material = if on and cfg.glow then Enum.Material.Neon else dayMaterial
	part.Color = if on then rgb(cfg.color) else saved.color
end

local function applyWindow(part: BasePart, saved: Saved, on: boolean)
	if on then
		local cfg = DayNight.WINDOW_NIGHT
		part.Material = if cfg.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = rgb(cfg.color)
		part.Transparency = 0
		part.Reflectance = 0
	else
		part.Material = saved.material
		part.Color = saved.color
		part.Transparency = saved.transparency
		part.Reflectance = saved.reflectance
	end
end

local function applyStreetLight(lens: BasePart, light: Light, on: boolean)
	local cfg = DayNight.STREET_LIGHT
	lens.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	lens.Color = rgb(if on then cfg.lensNight else cfg.lensDay)
	light.Color = rgb(cfg.color)
	light.Brightness = cfg.brightness
	light.Range = cfg.range
	if light:IsA("SpotLight") then
		light.Angle = cfg.angle
	end
	light.Enabled = on
end

local function applyFill(light: Light)
	local cfg = DayNight.NIGHT_FILL
	light.Color = rgb(cfg.color)
	light.Brightness = cfg.brightness
	if light:IsA("PointLight") then
		light.Range = cfg.range
	end
	light.Enabled = lightsOn == true and not reduceEffects
end

local function consider(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	if inst.Name == "NightFill" then
		local light = inst:FindFirstChildWhichIsA("Light")
		if light and not table.find(fillLights, light) then
			table.insert(fillLights, light)
			applyFill(light)
		end
		return
	end
	if inst.Name == "SodiumLens" and streetLenses[inst] == nil then
		local light = inst:FindFirstChildWhichIsA("Light")
		if light then
			streetLenses[inst] = light
			applyStreetLight(inst, light, lightsOn == true)
		end
		return
	end
	if lamps[inst] == nil and isLampPart(inst) then
		local saved = save(inst)
		lamps[inst] = saved
		if lightsOn ~= nil then
			applyLamp(inst, saved, lightsOn)
		end
	elseif windows[inst] == nil and isWindowPart(inst) then
		local saved = save(inst)
		windows[inst] = saved
		if lightsOn ~= nil then
			applyWindow(inst, saved, lightsOn)
		end
	end
end

local function setLights(on: boolean)
	if lightsOn == on then
		return
	end
	lightsOn = on
	for part, saved in lamps do
		if part.Parent then
			applyLamp(part, saved, on)
		else
			lamps[part] = nil
		end
	end
	for part, saved in windows do
		if part.Parent then
			applyWindow(part, saved, on)
		else
			windows[part] = nil
		end
	end
	for _, light in shopLights do
		light.Enabled = on
	end
	for lens, light in streetLenses do
		if lens.Parent then
			applyStreetLight(lens, light, on)
		else
			streetLenses[lens] = nil
		end
	end
	for _, light in fillLights do
		applyFill(light)
	end
	if DEBUG then
		print(`[LightingController] lights {if on then "ON" else "OFF"} ({#shopLights} shops)`)
	end
end

local function makeShopLights()
	local plots = workspace:WaitForChild("Plots", 30)
	if not plots then
		return
	end
	local cfg = DayNight.SHOP_LIGHT
	for _, plot in plots:GetChildren() do
		local floor = plot:FindFirstChild("Floor")
		if floor and floor:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "NightShopLight"
			attachment.Position = Vector3.new(0, cfg.height, 0)
			attachment.Parent = floor
			local light = Instance.new("PointLight")
			light.Range = cfg.range
			light.Brightness = cfg.brightness
			light.Color = rgb(cfg.color)
			light.Shadows = false
			light.Enabled = lightsOn == true
			light.Parent = attachment
			table.insert(shopLights, light)
		end
	end
end

local function updateLook()
	local clock, segment = currentClock()
	local a, b, t = sample(clock)
	local function n(key: string): number
		return lerp(a[key], b[key], t)
	end
	local function c(key: string): Color3
		return rgb(a[key]):Lerp(rgb(b[key]), t)
	end

	Lighting.ClockTime = clock
	Lighting.Brightness = n("brightness")
	Lighting.ExposureCompensation = n("exposure")
	Lighting.Ambient = c("ambient")
	Lighting.OutdoorAmbient = c("outdoor")
	Lighting.ColorShift_Top = c("shiftTop")
	if atmosphere then
		atmosphere.Color = c("atmoColor")
		atmosphere.Decay = c("atmoDecay")
		atmosphere.Density = n("atmoDensity")
		atmosphere.Haze = n("atmoHaze")
		atmosphere.Glare = n("atmoGlare")
	end
	if bloom then
		bloom.Intensity = n("bloom")
	end
	if grade then
		grade.TintColor = c("ccTint")
		grade.Saturation = n("ccSat")
		grade.Contrast = n("ccContrast")
	end
	if sunRays then
		sunRays.Enabled = not reduceEffects
		sunRays.Intensity = n("sunRays")
	end

	setLights(n("lights") > DayNight.LIGHTS_ON_ABOVE)

	Lighting:SetAttribute("DayNightClock", math.floor(clock * 10) / 10) -- read-only display for testers (local)
	if DEBUG and segment ~= lastSegment then
		lastSegment = segment
		print(`[LightingController] {segment} (clock {string.format("%.1f", clock)})`)
	end
end

function LightingController.Init(_controllers)
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if DEBUG and not (atmosphere and bloom and grade) then
		warn("[LightingController] Lighting is missing Atmosphere / Bloom / ColorCorrection; the cycle still runs without them")
	end
end

function LightingController.Start()
	reduceEffects = ClientState.Get("settings.reduceEffects") == true
	ClientState.OnChanged("settings", function()
		reduceEffects = ClientState.Get("settings.reduceEffects") == true
		for _, light in fillLights do
			applyFill(light)
		end
	end)

	for _, inst in workspace:GetDescendants() do
		consider(inst)
	end
	workspace.DescendantAdded:Connect(consider) -- streamed-in or rebuilt art
	task.spawn(makeShopLights)

	local sinceLook = UPDATE_EVERY
	updateLook()
	RunService.Heartbeat:Connect(function(dt)
		sinceLook += dt
		if sinceLook >= UPDATE_EVERY then
			sinceLook = 0
			updateLook()
		end
	end)
	if DEBUG then
		local lampCount, windowCount = 0, 0
		for _ in lamps do
			lampCount += 1
		end
		for _ in windows do
			windowCount += 1
		end
		print(`[LightingController] ready: {lampCount} lamps, {windowCount} window meshes, cycle {cycleLength} s`)
	end
end

return LightingController
