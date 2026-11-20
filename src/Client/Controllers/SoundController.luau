-- SoundController.luau
-- Purpose: all client audio: a day/night music playlist (shuffled, crossfaded), town ambience (birds by day, crickets at
-- night, 3D waves at the lagoon), UI clicks, and game-event sounds (sale, level up, box, restoration work + snaps,
-- customer doorbell). Respects the Settings switches "music" and "sfx". Client only; the server never plays these.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Sounds (ids/volumes), Shared.Remotes (SaleMade, ItemRestored, BoxOpened,
-- Notify, Announcement), ClientState (settings), Lighting attribute DayNightClock (set by LightingController).
-- Other controllers call SoundController.Play(name) / SoundController.Work(stepType) through the shared controller table.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Sounds"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local SoundController = {}
local DEBUG = true

local function log(...)
	if DEBUG then
		print("[SoundController]", ...)
	end
end

local rng = Random.new()
local musicOn, sfxOn = true, true
local groups: { [string]: SoundGroup } = {}
local sfxTemplates: { [string]: Sound } = {}
local workSounds: { [string]: Sound } = {}
local lastWork: { [string]: number } = {}

local function asset(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local function group(name: string, volume: number): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = "DF_" .. name
	g.Volume = volume
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function isNight(): boolean
	local clock = Lighting:GetAttribute("DayNightClock")
	if type(clock) ~= "number" then
		clock = Lighting.ClockTime
	end
	return clock >= Config.MUSIC.nightFrom or clock < Config.MUSIC.nightTo
end

-- Inside a shop = standing over any plot's Floor, under its roof height. (Shop music plays in every shop, mine or a
-- friend's; ambience is lowered indoors.)
local INDOOR_HEIGHT = 16
local function isIndoors(): boolean
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plots = workspace:FindFirstChild("Plots")
	if not root or not plots then
		return false
	end
	for _, plot in plots:GetChildren() do
		local floor = plot:FindFirstChild("Floor")
		if floor and floor:IsA("BasePart") then
			local rel = floor.CFrame:PointToObjectSpace(root.Position)
			local half = floor.Size / 2
			if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and rel.Y > -2 and rel.Y < INDOOR_HEIGHT then
				return true
			end
		end
	end
	return false
end

local function fade(sound: Sound, to: number, seconds: number, thenStop: boolean?)
	local tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = to })
	tween:Play()
	if thenStop then
		tween.Completed:Once(function()
			if sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

-- ===== Music: two players crossfade; each mood keeps a shuffled queue =====
local musicA: Sound, musicB: Sound
local activeMusic: Sound? = nil
local mood: string? = nil
local queues: { [string]: { number } } = {}

local function nextTrack(m: string): number
	local q = queues[m]
	if not q or #q == 0 then
		q = {}
		for _, t in Config.MUSIC[m] do
			table.insert(q, t.id)
		end
		for i = #q, 2, -1 do -- shuffle
			local j = rng:NextInteger(1, i)
			q[i], q[j] = q[j], q[i]
		end
		queues[m] = q
	end
	return table.remove(q, 1) :: number
end

local function playMusic(m: string)
	local incoming = if activeMusic == musicA then musicB else musicA
	local outgoing = activeMusic
	incoming.SoundId = asset(nextTrack(m))
	incoming.Volume = 0
	incoming.TimePosition = 0
	incoming:Play()
	fade(incoming, 1, Config.MUSIC.crossfade)
	if outgoing then
		fade(outgoing, 0, Config.MUSIC.crossfade, true)
	end
	activeMusic = incoming
	mood = m
end

-- ===== Ambience =====
local ambDay: Sound, ambNight: Sound
local INDOOR_AMBIENCE = 0.3 -- outdoor sounds are muffled to 30% inside a shop
local function setAmbience(night: boolean, indoors: boolean?)
	local k = if indoors then INDOOR_AMBIENCE else 1
	fade(ambDay, if night then 0 else Config.AMBIENCE.day.volume * k, 3)
	fade(ambNight, if night then Config.AMBIENCE.night.volume * k else 0, 3)
end

-- ===== Effects =====
-- Play a named effect. `at` (optional) = a BasePart or Attachment to make it 3D at that spot.
function SoundController.Play(name: string, at: Instance?)
	if not sfxOn then
		return
	end
	local template = sfxTemplates[name]
	if not template then
		return
	end
	local cfg = Config.SFX[name]
	local s = template:Clone()
	if cfg.pitch then
		s.PlaybackSpeed = rng:NextNumber(cfg.pitch[1], cfg.pitch[2])
	end
	if at then
		s.RollOffMaxDistance = cfg.rolloff or 80
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = at
	else
		s.Parent = SoundService
	end
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
end

-- Restoration work loop for a step type (Wipe / Scrape / Polish): call on every progress tick; it fades out by itself.
function SoundController.Work(stepType: string)
	local s = workSounds[stepType]
	if not s or not sfxOn then
		return
	end
	lastWork[stepType] = os.clock()
	if not s.IsPlaying then
		s.Volume = Config.WORK[stepType].volume
		s.PlaybackSpeed = rng:NextNumber(0.95, 1.08)
		s.TimePosition = rng:NextNumber(0, math.max(0, s.TimeLength - 0.4))
		s:Play()
	end
end

local function hookButton(inst: Instance)
	if inst:IsA("GuiButton") and not inst:GetAttribute("NoClickSound") then
		inst.Activated:Connect(function()
			SoundController.Play("click")
		end)
	end
end

local function applySettings()
	local settings = ClientState.Get("settings")
	musicOn = not (type(settings) == "table" and settings.music == false)
	sfxOn = not (type(settings) == "table" and settings.sfx == false)
	groups.music.Volume = if musicOn then Config.MIX.music else 0
	groups.ambience.Volume = if musicOn then Config.MIX.ambience else 0 -- ambience follows the music switch
	groups.sfx.Volume = if sfxOn then Config.MIX.sfx else 0
end

function SoundController.Init(_controllers)
	group("music", Config.MIX.music)
	group("ambience", Config.MIX.ambience)
	group("sfx", Config.MIX.sfx)
end

function SoundController.Start()
	-- music players
	local function musicPlayer(name: string): Sound
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundGroup = groups.music
		s.Parent = SoundService
		s.Ended:Connect(function()
			if activeMusic == s and mood then
				playMusic(mood)
			end
		end)
		return s
	end
	musicA, musicB = musicPlayer("MusicA"), musicPlayer("MusicB")
	-- ambience loops
	local function loop(name: string, id: number, volume: number): Sound
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = asset(id)
		s.Looped = true
		s.Volume = volume
		s.SoundGroup = groups.ambience
		s.Parent = SoundService
		s:Play()
		return s
	end
	ambDay = loop("AmbDay", Config.AMBIENCE.day.id, 0)
	ambNight = loop("AmbNight", Config.AMBIENCE.night.id, 0)
	-- waves: a 3D emitter at the lagoon (heard only nearby)
	local w = Config.AMBIENCE.waves
	local emitter = Instance.new("Part")
	emitter.Name = "LagoonWavesEmitter"
	emitter.Anchored, emitter.CanCollide, emitter.CanQuery, emitter.CanTouch = true, false, false, false
	emitter.Transparency = 1
	emitter.Size = Vector3.one
	emitter.Position = w.position
	emitter.Parent = workspace
	local waves = Instance.new("Sound")
	waves.Name = "Waves"
	waves.SoundId = asset(w.id)
	waves.Looped = true
	waves.Volume = w.volume
	waves.RollOffMode = Enum.RollOffMode.Linear
	waves.RollOffMinDistance = 20
	waves.RollOffMaxDistance = w.range
	waves.SoundGroup = groups.ambience
	waves.Parent = emitter
	waves:Play()
	-- effect templates and work loops
	for name, cfg in Config.SFX do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = asset(cfg.id)
		s.Volume = cfg.volume
		s.SoundGroup = groups.sfx
		sfxTemplates[name] = s
	end
	for stepType, cfg in Config.WORK do
		local s = Instance.new("Sound")
		s.Name = "Work_" .. stepType
		s.SoundId = asset(cfg.id)
		s.Looped = true
		s.Volume = cfg.volume
		s.SoundGroup = groups.sfx
		s.Parent = SoundService
		workSounds[stepType] = s
	end

	applySettings()
	ClientState.OnChanged("settings", applySettings)

	-- game events from the server
	Remotes.SaleMade.OnClientEvent:Connect(function()
		SoundController.Play("coins")
	end)
	Remotes.ItemRestored.OnClientEvent:Connect(function()
		SoundController.Play("restored")
	end)
	Remotes.BoxOpened.OnClientEvent:Connect(function()
		SoundController.Play("boxOpen")
		task.delay(0.35, SoundController.Play, "reveal")
	end)
	Remotes.Announcement.OnClientEvent:Connect(function()
		SoundController.Play("reveal")
	end)
	Remotes.Notify.OnClientEvent:Connect(function(kind)
		if kind == "LevelUp" then
			SoundController.Play("levelUp")
		elseif kind == "Upgrade" then
			SoundController.Play("purchase")
		elseif kind == "Delivery" then
			SoundController.Play("delivery")
		end
	end)

	-- every UI button clicks
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, inst in playerGui:GetDescendants() do
		hookButton(inst)
	end
	playerGui.DescendantAdded:Connect(hookButton)

	-- a customer walking in rings the shop door bell (3D, so only people nearby hear it)
	task.spawn(function()
		local customers = workspace:WaitForChild("Customers", 30)
		if customers then
			customers.ChildAdded:Connect(function(model)
				task.wait(0.2)
				local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
				if root then
					SoundController.Play("doorbell", root)
				end
			end)
		end
	end)

	-- music / ambience follow the day-night clock and whether I'm inside a shop; work loops fade out when progress stops
	local night, indoors = isNight(), isIndoors()
	local function wanted(n: boolean, inside: boolean): string
		return if inside then "shop" elseif n then "night" else "day"
	end
	setAmbience(night, indoors)
	playMusic(wanted(night, indoors))
	local sinceMood = 0
	local lastAmbience = { night, indoors }
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for stepType, s in workSounds do
			if s.IsPlaying and now - (lastWork[stepType] or 0) > 0.25 then
				s:Stop()
			end
		end
		sinceMood += dt
		if sinceMood > 0.5 then -- twice a second: walking through a shop door switches quickly
			sinceMood = 0
			local n, inside = isNight(), isIndoors()
			if n ~= lastAmbience[1] or inside ~= lastAmbience[2] then
				lastAmbience = { n, inside }
				setAmbience(n, inside)
			end
			local want = wanted(n, inside)
			if want ~= mood then
				playMusic(want)
				log("music mood ->", want)
			end
		end
	end)
	log("ready: music", mood, "| music on:", musicOn, "| sfx on:", sfxOn)
end

return SoundController
