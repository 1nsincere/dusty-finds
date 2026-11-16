-- WipeTest.local.luau: disposable, unsaved Wipe test runner for a SEPARATE unsynced place.
-- Owner: Dev 2 (Dwayne). Depends on: sibling PointerInput/SpotClear and Workspace.WipeTestItem.
-- Creates its own temporary test UI and local item clone; no production modules or remotes.
-- Do not install in the production place. Completion means one Wipe step, never a Restored item.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DEBUG = true
-- Extra guard, not a replacement for using a new empty place.
assert(RunService:IsStudio(), "Wipe prototype is Studio-only")
assert(game.PlaceId ~= 113871213495650, "Do not run WipeTest in the production place")
assert(not ReplicatedStorage:FindFirstChild("Shared")
	and not ReplicatedStorage:FindFirstChild("Remotes")
	and not StarterPlayer.StarterPlayerScripts:FindFirstChild("Client"),
	"Use an empty unsynced place without production scripts")

local PointerInput = require(script.Parent:WaitForChild("PointerInput"))
local SpotClear = require(script.Parent:WaitForChild("SpotClear"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
assert(not playerGui:FindFirstChild("WipePrototype"), "Only install one WipeTest LocalScript")

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in properties do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local gui = make("ScreenGui", { Name = "WipePrototype", ResetOnSpawn = false,
	IgnoreGuiInset = false, DisplayOrder = 50 }, playerGui)
local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0.9, 0, 0, 148),
	BackgroundColor3 = Color3.fromRGB(28, 34, 42), Active = true }, gui)
make("UISizeConstraint", { MaxSize = Vector2.new(520, 148) }, panel)
local label = make("TextLabel", { Name = "Status", Position = UDim2.fromOffset(10, 6),
	Size = UDim2.new(1, -20, 0, 52), BackgroundTransparency = 1, TextWrapped = true,
	TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
	Text = "Wipe test only - press Start" }, panel)
local track = make("Frame", { Position = UDim2.new(0, 10, 0, 65),
	Size = UDim2.new(1, -20, 0, 16), BackgroundColor3 = Color3.fromRGB(60, 70, 80),
	ClipsDescendants = true }, panel)
local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(82, 205, 155) }, track)
local function button(name, x, text)
	return make("TextButton", { Name = name, Position = UDim2.new(x, 8, 0, 92),
		Size = UDim2.new(1 / 3, -16, 0, 46), Text = text, TextSize = 17,
		TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(65, 83, 105) }, panel)
end
local startButton = button("Start", 0, "Start")
local restartButton = button("Restart", 1 / 3, "Restart")
local exitButton = button("Exit", 2 / 3, "Exit")

local pointer, minigame, clone = nil, nil, nil
local source, sourceParent = nil, nil
local savedCamera = nil
local active = false
local connections = {}
local cleanedUp = false
local oldMouseBehavior = nil

local function log(message)
	if DEBUG then
		print("[WipeTest] " .. message)
	end
end

local function stopRun()
	active = false
	if pointer then
		pointer:Destroy()
		pointer = nil
	end
	if minigame then
		minigame:Destroy()
		minigame = nil
	end
	if clone then
		clone:Destroy()
		clone = nil
	end
	if source and source.Parent == nil and sourceParent then
		source.Parent = sourceParent
	end
	if savedCamera then
		local camera = savedCamera.camera
		if camera.Parent then
			camera.CFrame = savedCamera.cframe
			camera.Focus = savedCamera.focus
			camera.FieldOfView = savedCamera.fov
			camera.CameraType = savedCamera.kind
		end
		savedCamera = nil
	end
	if oldMouseBehavior then
		UserInputService.MouseBehavior = oldMouseBehavior
		oldMouseBehavior = nil
	end
end

local function startRun()
	stopRun()
	fill.Size = UDim2.fromScale(0, 1)
	local ok, reason = pcall(function()
		source = workspace:FindFirstChild("WipeTestItem")
		assert(source and source:IsA("Model"), "Workspace needs a Model named WipeTestItem")
		local base = source:FindFirstChild("Base")
		assert(base and base:IsA("BasePart") and source.PrimaryPart == base,
			"WipeTestItem needs Base as its PrimaryPart")
		for _, descendant in source:GetDescendants() do
			assert(not descendant:IsA("LuaSourceContainer"), "Test item must contain no scripts")
			if descendant:IsA("BasePart") then
				assert(descendant.Anchored, `{descendant.Name} must be anchored`)
			end
		end
		clone = source:Clone()
		assert(clone, "Set WipeTestItem.Archivable=true")
		clone.Name = "WipeTestActive"
		-- Remove only this client's fixture from view so its dirty decals cannot show through.
		sourceParent = source.Parent
		source.Parent = nil
		clone.Parent = workspace
		local camera = workspace.CurrentCamera
		assert(camera, "No current camera; try Start again after spawning")
		savedCamera = { camera = camera, cframe = camera.CFrame, focus = camera.Focus,
			fov = camera.FieldOfView, kind = camera.CameraType }
		local bounds, size = clone:GetBoundingBox()
		local radius = size.Magnitude / 2
		local aspect = math.max(camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1), 0.2)
		local halfFov = math.atan(math.tan(math.rad(50) / 2) * math.min(aspect, 1))
		-- Reserve the bottom of the screen for feedback/buttons, including landscape phones.
		local usableHeight = math.max(camera.ViewportSize.Y - 180, 80)
		local framingMargin = math.max(1.7, camera.ViewportSize.Y / usableHeight * 1.15)
		local distance = math.max(12, radius / math.sin(halfFov) * framingMargin)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		camera.CFrame = CFrame.lookAt(bounds.Position + Vector3.new(0, distance, distance * 0.45), bounds.Position)
		local screenOffset = distance * math.tan(math.rad(50) / 2)
			* 172 / math.max(camera.ViewportSize.Y, 1)
		camera.CFrame -= camera.CFrame.UpVector * screenOffset
		camera.Focus = CFrame.new(bounds.Position)
		oldMouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		active = true
		minigame = SpotClear.new(clone, { type = "Wipe", secondsPerSpot = 1.5 }, function(progress, cleared, total)
			fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			label.Text = `Hold and drag over dirt\n{cleared}/{total} spots - {math.floor(progress * 100 + 0.5)}%`
		end, function(_score)
			active = false
			if pointer then
				pointer:Destroy()
				pointer = nil
			end
			label.Text = "Wipe complete!\nTest step only - no items or rewards saved."
			log("complete - no production state changed")
		end)
		pointer = PointerInput.new(clone, minigame, panel)
		log("started")
	end)
	if not ok then
		stopRun()
		label.Text = "Setup error - see Output. Fix the fixture, then press Start."
		if DEBUG then
			warn("[WipeTest] " .. tostring(reason))
		end
	end
end

table.insert(connections, startButton.Activated:Connect(function()
	if not active then
		startRun()
	end
end))
table.insert(connections, restartButton.Activated:Connect(startRun))
table.insert(connections, exitButton.Activated:Connect(function()
	stopRun()
	fill.Size = UDim2.fromScale(0, 1)
	label.Text = "Cancelled - test progress discarded.\nPress Start for a fresh run."
	log("cancelled - input detached, fixture and camera restored")
end))
table.insert(connections, player.CharacterRemoving:Connect(function()
	stopRun()
	fill.Size = UDim2.fromScale(0, 1)
	label.Text = "Character reset - test cancelled. Press Start after spawning."
end))

local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	stopRun()
	for _, connection in connections do
		connection:Disconnect()
	end
	gui:Destroy()
end
table.insert(connections, script.Destroying:Connect(cleanup))
table.insert(connections, gui.Destroying:Connect(cleanup))
log("ready - isolated local Wipe prototype")
