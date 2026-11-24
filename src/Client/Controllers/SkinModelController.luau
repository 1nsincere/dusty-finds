-- SkinModelController.luau (StarterPlayerScripts.Client.Controllers.SkinModelController)
-- Purpose: draws MODEL skins (Config.Skins look.model, e.g. Runic Antique) on every shop's shelves and pedestals, on
-- this screen. The server (SkinService) only sets the piece's Skin attribute and a fallback colour; here the classic
-- block is hidden locally (LocalTransparencyModifier) and the model from ReplicatedStorage.Assets.Skins sits exactly
-- where the block is: it follows the block when it moves (edit mode, pedestals going to the Back Room) and disappears
-- while the block is hidden (locked pedestals). Adds the skin's light and its dark aura mist (mist off with Settings
-- "Reduce effects"). Purely visual: no remotes.
-- Owner: Dev 3 (Sean). Depends on: Shared.Config.Skins, ReplicatedStorage.Assets.Skins.<model> (Models with their
-- WorldPivot at the bottom centre, front = pivot LookVector, length along pivot RightVector), ClientState (settings),
-- Workspace.Plots (Shelves / ExhibitSlots parts with PieceId and the Skin attribute).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Skins = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Skins"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local SkinModelController = {}
local DEBUG = true

-- how each kind's block faces: a shelf's room side is the part's +X (its length runs along Z); a pedestal faces -Z
local FRAME = {
	Shelf = CFrame.Angles(0, math.rad(-90), 0),
	Pedestal = CFrame.identity,
}
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local drawn: { [BasePart]: Model } = {}
local folder: Folder? = nil
-- orbiting star orbs per drawn model (look.orbit), moved every frame in Start
type Orb = { part: BasePart, phase: number, a: number, b: number, height: number, tilt: number, speed: number }
local orbits: { [Model]: { Orb } } = {}
local ORBIT_DRAW_STUDS = 120 -- orbs further than this from the camera don't move (saves phones)

local function log(...)
	if DEBUG then
		print("[SkinModelController]", ...)
	end
end

local function reduceEffects(): boolean
	return ClientState.Get("settings.reduceEffects") == true
end

local function templateFor(skin: any): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local skinsFolder = assets and assets:FindFirstChild("Skins")
	local t = skinsFolder and skin and skin.look and skin.look.model and skinsFolder:FindFirstChild(skin.look.model)
	return if t and t:IsA("Model") then t else nil
end

local function kindOf(part: BasePart): string
	return if part:GetAttribute("PieceKind") == "Shelf" then "Shelf" else "Pedestal"
end

local function clear(part: BasePart)
	local m = drawn[part]
	if m then
		orbits[m] = nil
		m:Destroy()
		drawn[part] = nil
	end
	part.LocalTransparencyModifier = 0
end

local function place(part: BasePart, model: Model)
	model:PivotTo(part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0) * FRAME[kindOf(part)])
end

local function addAura(model: Model, look: any, kind: string)
	local _, size = model:GetBoundingBox()
	if look.light then
		local glow = model:FindFirstChild("Glow", true) or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if glow then
			local light = Instance.new("PointLight")
			light.Name = "SkinLight"
			light.Color = look.light
			light.Range = if kind == "Shelf" then 14 else 10
			light.Brightness = 1.4
			light.Shadows = false
			light.Parent = glow
		end
	end
	if look.pulse then
		model:SetAttribute("Pulse", true) -- the Heartbeat loop in Start breathes its light and neon
	end
	if look.aura then
		-- a low invisible plate round the base that breathes out dark, slowly rising mist
		local plate = Instance.new("Part")
		plate.Name = "AuraEmitter"
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.CastShadow = false
		plate.Transparency = 1
		-- wider than the piece, so the mist starts round it (mist that starts inside is hidden by the stone)
		plate.Size = Vector3.new(size.X + 2.4, 0.4, size.Z + 2.4)
		plate.CFrame = model:GetPivot() * CFrame.new(0, 0.3, 0)
		plate.Parent = model
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "SkinAura"
		mist.Texture = SMOKE
		-- a dark purple mist (Sean, 2026-11-24): low light emission so it stays dark, clearly visible in daylight
		mist.Color = ColorSequence.new(look.aura, look.aura:Lerp(look.light or look.aura, 0.25))
		-- the smoke texture is very soft: a DARK aura needs near-solid puffs and some emission to read (tested in Play);
		-- a LIGHT aura (gold) at that strength blows the whole room out, so it gets a thin, see-through haze instead
		local c = look.aura
		local light = (c.R * 0.3 + c.G * 0.59 + c.B * 0.11) > 0.5
		mist.LightEmission = if light then 0.12 else 0.35
		mist.LightInfluence = 0.4
		mist.Brightness = if light then 1 else 2
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, if light then 0.6 else 0),
			NumberSequenceKeypoint.new(0.7, if light then 0.8 else 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		mist.Size = if light
			then NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 3) })
			else NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4.2) })
		mist.Lifetime = NumberRange.new(2.5, 3.5)
		mist.Speed = NumberRange.new(0.4, 0.8)
		mist.EmissionDirection = Enum.NormalId.Top
		mist.SpreadAngle = Vector2.new(20, 20)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-15, 15)
		mist.Rate = (if kind == "Shelf" then 16 else 8) * (if light then 0.5 else 1)
		mist.Enabled = not reduceEffects()
		mist.Parent = plate
	end
	if look.sparkle then
		-- gentle starlight twinkles: one emitter round the top rim, one on the glowing wings (Glow part)
		local function sparkle(parent: Instance, rate: number)
			local s = Instance.new("ParticleEmitter")
			s.Name = "SkinAura" -- same name as the mist so the Reduce effects switch covers it
			s.Texture = SPARKLE
			s.Color = ColorSequence.new(look.sparkle, look.light or look.sparkle)
			s.LightEmission = 1
			s.LightInfluence = 0
			s.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			s.Transparency = NumberSequence.new(0.1)
			s.Lifetime = NumberRange.new(0.8, 1.4)
			s.Speed = NumberRange.new(0.1, 0.4)
			s.SpreadAngle = Vector2.new(180, 180)
			s.Rotation = NumberRange.new(0, 360)
			s.RotSpeed = NumberRange.new(-90, 90)
			s.Rate = rate
			s.Enabled = not reduceEffects()
			s.Parent = parent
		end
		local rim = Instance.new("Part")
		rim.Name = "SparkleRim"
		rim.Anchored = true
		rim.CanCollide = false
		rim.CanQuery = false
		rim.CanTouch = false
		rim.CastShadow = false
		rim.Transparency = 1
		rim.Size = Vector3.new(size.X, 0.2, size.Z)
		rim.CFrame = model:GetPivot() * CFrame.new(0, size.Y + 0.1, 0)
		rim.Parent = model
		sparkle(rim, if kind == "Shelf" then 6 else 3)
		local glow = model:FindFirstChild("Glow", true)
		if glow then
			sparkle(glow, if kind == "Shelf" then 5 else 3)
		end
	end
	if look.swirl then
		model:SetAttribute("Swirl", true) -- the 20 Hz loop in Start shifts the Nebula / NebulaCore colours
	end
	if look.starDust then
		-- tiny stars drifting up from round the base (galaxy skins; instead of the mist)
		local plate = Instance.new("Part")
		plate.Name = "StarDustEmitter"
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.CastShadow = false
		plate.Transparency = 1
		plate.Size = Vector3.new(size.X + 1.2, 0.2, size.Z + 1.2)
		plate.CFrame = model:GetPivot() * CFrame.new(0, 0.2, 0)
		plate.Parent = model
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "SkinAura" -- covered by the Reduce effects switch
		dust.Texture = SPARKLE
		dust.Color = ColorSequence.new(look.starDust, look.light or look.starDust)
		dust.LightEmission = 1
		dust.LightInfluence = 0
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		})
		dust.Transparency = NumberSequence.new(0.15)
		dust.Lifetime = NumberRange.new(2.5, 4)
		dust.Speed = NumberRange.new(0.8, 1.5)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.SpreadAngle = Vector2.new(12, 12)
		dust.Rotation = NumberRange.new(0, 360)
		dust.RotSpeed = NumberRange.new(-60, 60)
		dust.Rate = if kind == "Shelf" then 14 else 6
		dust.Enabled = not reduceEffects()
		dust.Parent = plate
	end
	if look.orbit then
		-- small glowing star orbs slowly circling the piece, each with a short light trail
		local list = {}
		local count = if kind == "Shelf" then 4 else 3
		for i = 1, count do
			local colour = look.orbit[(i - 1) % #look.orbit + 1]
			local orb = Instance.new("Part")
			orb.Name = "OrbitStar"
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.one * (if kind == "Shelf" then 0.7 else 0.55)
			orb.Material = Enum.Material.Neon
			orb.Color = colour
			orb.Anchored = true
			orb.CanCollide = false
			orb.CanQuery = false
			orb.CanTouch = false
			orb.CastShadow = false
			orb.CFrame = model:GetPivot() * CFrame.new(0, size.Y, 0)
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.22, 0)
			a0.Parent = orb
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.22, 0)
			a1.Parent = orb
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(colour)
			trail.LightEmission = 1
			trail.Lifetime = 1.1
			trail.Transparency = NumberSequence.new(0.3, 1)
			trail.FaceCamera = true
			trail.Enabled = not reduceEffects()
			trail.Parent = orb
			orb.Transparency = if reduceEffects() then 1 else 0
			orb.Parent = model
			table.insert(list, {
				part = orb,
				phase = (i - 1) / count * math.pi * 2,
				a = size.X / 2 + (if kind == "Shelf" then 0.9 else 0.8),
				b = size.Z / 2 + (if kind == "Shelf" then 0.9 else 0.8),
				height = size.Y * (0.45 + 0.35 * ((i - 1) % 2)),
				tilt = if i % 2 == 0 then 0.6 else -0.6,
				speed = if i % 2 == 0 then 0.55 else -0.45, -- alternate directions so they cross
			})
		end
		orbits[model] = list
	end
end

local function render(part: BasePart)
	local id = part:GetAttribute("Skin")
	local skin = if type(id) == "string" then Skins.BY_ID[id] else nil
	local template = templateFor(skin)
	local visible = part.Transparency < 0.99
	if not (template and visible) then
		clear(part)
		return
	end
	local current = drawn[part]
	if current and current:GetAttribute("SkinId") == id then
		place(part, current) -- same skin: just follow the block
		part.LocalTransparencyModifier = 1
		return
	end
	clear(part)
	local model = template:Clone()
	model:SetAttribute("SkinId", id)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	-- fit the block's height (a scaled shop scales its pieces too)
	local _, size = model:GetBoundingBox()
	if size.Y > 0.01 and math.abs(size.Y - part.Size.Y) > 0.02 then
		model:ScaleTo(model:GetScale() * part.Size.Y / size.Y)
	end
	place(part, model)
	addAura(model, skin.look, kindOf(part))
	model.Name = "Skin_" .. part:GetFullName():gsub("%.", "_")
	model.Parent = folder
	drawn[part] = model
	part.LocalTransparencyModifier = 1
end

local hooked: { [BasePart]: boolean } = {}

local function hook(part: Instance)
	if not part:IsA("BasePart") or hooked[part] or part:GetAttribute("PieceId") == nil then
		return
	end
	hooked[part] = true
	part:GetAttributeChangedSignal("Skin"):Connect(function()
		render(part)
	end)
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		render(part)
	end)
	part:GetPropertyChangedSignal("CFrame"):Connect(function()
		local m = drawn[part]
		if m then
			place(part, m)
		end
	end)
	part.AncestryChanged:Connect(function()
		if part.Parent == nil then
			clear(part)
			hooked[part] = nil
		end
	end)
	render(part)
end

local function hookPlot(plot: Instance)
	for _, name in { "Shelves", "ExhibitSlots" } do
		task.spawn(function()
			local f = plot:WaitForChild(name, 30)
			if not f then
				return
			end
			for _, p in f:GetChildren() do
				hook(p)
			end
			f.ChildAdded:Connect(hook)
		end)
	end
end

function SkinModelController.Init(_others) end

function SkinModelController.Start()
	local f = Instance.new("Folder")
	f.Name = "SkinModels"
	f.Parent = workspace
	folder = f
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 30)
		if not plots then
			return
		end
		for _, plot in plots:GetChildren() do
			hookPlot(plot)
		end
		plots.ChildAdded:Connect(hookPlot)
		log("ready")
	end)
	ClientState.OnChanged("settings", function()
		local reduce = reduceEffects()
		for _, model in drawn do
			for _, d in model:GetDescendants() do
				if d:IsA("ParticleEmitter") and d.Name == "SkinAura" then
					d.Enabled = not reduce
				elseif d:IsA("Trail") then
					d.Enabled = not reduce
				elseif d:IsA("BasePart") and d.Name == "OrbitStar" then
					d.Transparency = if reduce then 1 else 0
				end
			end
		end
	end)
	-- orbiting stars (look.orbit): moved every frame for smooth motion, only near the camera, not with Reduce effects
	RunService.RenderStepped:Connect(function()
		if next(orbits) == nil or reduceEffects() then
			return
		end
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local t = os.clock()
		local parts, cframes = {}, {}
		for model, list in orbits do
			local pivot = model:GetPivot()
			if (pivot.Position - camPos).Magnitude <= ORBIT_DRAW_STUDS then
				for _, o in list do
					local ang = o.phase + t * o.speed
					local y = o.height + o.tilt * math.sin(ang) + 0.15 * math.sin(t * 2 + o.phase)
					table.insert(parts, o.part)
					table.insert(cframes, pivot * CFrame.new(math.cos(ang) * o.a, y, math.sin(ang) * o.b))
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
	-- pulse skins (look.pulse): the light and the neon glow slowly breathe (~4 s); steady with Reduce effects on
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 1 / 20 then
			return
		end
		since = 0
		local wave = (math.sin(os.clock() * 1.6) + 1) / 2
		local still = reduceEffects()
		for _, model in drawn do
			local swirl = Skins.BY_ID[model:GetAttribute("SkinId")]
			swirl = swirl and model:GetAttribute("Swirl") and swirl.look.swirl
			if swirl then
				-- nebula colour drifts round the swirl colours (~4 s each); first colour only with Reduce effects
				local pos = if still then 0 else (os.clock() / 4) % #swirl
				local i = math.floor(pos)
				local colour = swirl[i + 1]:Lerp(swirl[(i + 1) % #swirl + 1], pos - i)
				local nebula = model:FindFirstChild("Nebula")
				if nebula and nebula:IsA("BasePart") then
					nebula.Color = colour
				end
				local core = model:FindFirstChild("NebulaCore")
				if core and core:IsA("BasePart") then
					core.Color = colour:Lerp(Color3.new(1, 1, 1), 0.4)
				end
			end
			if model:GetAttribute("Pulse") then
				local glow = model:FindFirstChild("Glow")
				if glow and glow:IsA("BasePart") then
					glow.Transparency = if still then 0 else 0.3 * (1 - wave)
					local light = glow:FindFirstChild("SkinLight")
					if light and light:IsA("PointLight") then
						light.Brightness = if still then 0.9 else 0.5 + 0.8 * wave
					end
				end
			end
		end
	end)
end

return SkinModelController
