-- PolishTest.local.luau: standalone Polish test runner for a separate, unsynced Studio place.
-- Owner: Dev 2 (Dwayne). Depends on: sibling Rub, unchanged Wipe PointerInput, Workspace.PolishTestItem.
-- Creates temporary test UI/camera and a disposable clone. Never loads production modules or remotes.
-- Install one enabled prototype runner at a time; all movement tuning below is TEST ONLY.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DEBUG = true
local TEST_ONLY_MOVEMENT = {
	requiredTravel = 2, -- accumulated travel / viewport short side; no tool multipliers
	minSampleTravel = 0.0005, -- ignore tiny pointer jitter (0.05% of the short side)
	maxSampleTravel = 0.08, -- reject jumps larger than 8% of the short side
	maxCreditPerSample = 0.02, -- cap credited movement at 2% per rendered sample
}

assert(RunService:IsStudio(), "Polish prototype is Studio-only")
assert(game.PlaceId ~= 113871213495650, "Do not run PolishTest in the production place")
assert(not ReplicatedStorage:FindFirstChild("Shared")
	and not ReplicatedStorage:FindFirstChild("Remotes")
	and not StarterPlayer.StarterPlayerScripts:FindFirstChild("Client"),
	"Use a separate empty place without production scripts")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local function checkOtherRunners()
	assert(not playerGui:FindFirstChild("WipePrototype"), "Stop Play and disable WipeTest before testing Polish")
	for _, descendant in playerScripts:GetDescendants() do
		if descendant:IsA("LocalScript") and descendant ~= script and not descendant.Disabled then
			assert(descendant.Name ~= "WipeTest" and descendant.Name ~= "PolishTest",
				"Stop Play; enable only one WipeTest or PolishTest runner")
		end
	end
end
checkOtherRunners()
assert(not playerGui:FindFirstChild("PolishPrototype"), "Only install one PolishTest LocalScript")
local inputModule = script.Parent:WaitForChild("PointerInput", 5)
local rubModule = script.Parent:WaitForChild("Rub", 5)
assert(inputModule and rubModule, "Install sibling PointerInput and Rub ModuleScripts (see README)")
local PointerInput = require(inputModule)
local Rub = require(rubModule)

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in properties do
		object[key] = value
	end
	object.Parent = parent
	return object
end
local gui = make("ScreenGui", { Name = "PolishPrototype", ResetOnSpawn = false,
	IgnoreGuiInset = false, DisplayOrder = 50 }, playerGui)
local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0.9, 0, 0, 148),
	BackgroundColor3 = Color3.fromRGB(28, 34, 42), Active = true }, gui)
make("UISizeConstraint", { MaxSize = Vector2.new(520, 148) }, panel)
local label = make("TextLabel", { Position = UDim2.fromOffset(10, 6),
	Size = UDim2.new(1, -20, 0, 52), BackgroundTransparency = 1, TextWrapped = true,
	TextSize = 17, TextColor3 = Color3.new(1, 1, 1), Text = "Polish test only - press Start" }, panel)
local track = make("Frame", { Position = UDim2.new(0, 10, 0, 65),
	Size = UDim2.new(1, -20, 0, 16), BackgroundColor3 = Color3.fromRGB(60, 70, 80),
	ClipsDescendants = true }, panel)
local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(130, 200, 245) }, track)
local function button(name, x)
	return make("TextButton", { Name = name, Position = UDim2.new(x, 8, 0, 92),
		Size = UDim2.new(1 / 3, -16, 0, 46), Text = name, TextSize = 17,
		TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(65, 83, 105) }, panel)
end
local startButton = button("Start", 0)
local restartButton = button("Restart", 1 / 3)
local exitButton = button("Exit", 2 / 3)
local pointer, minigame, clone = nil, nil, nil
local source, sourceParent = nil, nil
local savedCamera, oldMouseBehavior = nil, nil
local connections = {}
local active, cleanedUp = false, false

local function log(message)
	if DEBUG then
		print("[PolishTest] " .. message)
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
		checkOtherRunners()
		source = workspace:FindFirstChild("PolishTestItem")
		assert(source and source:IsA("Model"), "Workspace needs a Model named PolishTestItem")
		local base = source:FindFirstChild("Base")
		assert(base and base:IsA("BasePart") and source.PrimaryPart == base,
			"PolishTestItem needs Base as its PrimaryPart")
		assert(source.Archivable, "Set PolishTestItem.Archivable=true")
		for _, descendant in source:GetDescendants() do
			assert(not descendant:IsA("LuaSourceContainer"), "PolishTestItem must contain no scripts")
			assert(descendant.Archivable, `{descendant.Name} must be Archivable`)
			if descendant:IsA("BasePart") then
				assert(descendant.Anchored, `{descendant.Name} must be anchored`)
			end
		end
		clone = source:Clone()
		clone.Name = "PolishTestActive"
		sourceParent = source.Parent
		source.Parent = nil -- this client's Polish fixture only; WipeTestItem is never accessed
		clone.Parent = workspace
		local camera = workspace.CurrentCamera
		assert(camera, "No camera; press Start again after spawning")
		savedCamera = { camera = camera, cframe = camera.CFrame, focus = camera.Focus,
			fov = camera.FieldOfView, kind = camera.CameraType }
		local bounds, size = clone:GetBoundingBox()
		local radius = size.Magnitude / 2
		local aspect = math.max(camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1), 0.2)
		local halfFov = math.atan(math.tan(math.rad(50) / 2) * math.min(aspect, 1))
		local usableHeight = math.max(camera.ViewportSize.Y - 180, 80)
		local margin = math.max(1.7, camera.ViewportSize.Y / usableHeight * 1.15)
		local distance = math.max(12, radius / math.sin(halfFov) * margin)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		camera.CFrame = CFrame.lookAt(bounds.Position + Vector3.new(0, distance, distance * 0.45), bounds.Position)
		camera.CFrame -= camera.CFrame.UpVector * distance * math.tan(math.rad(50) / 2)
			* 172 / math.max(camera.ViewportSize.Y, 1)
		camera.Focus = CFrame.new(bounds.Position)
		oldMouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		minigame = Rub.new(clone, { type = "Polish", testOnlyMovement = TEST_ONLY_MOVEMENT }, function(progress, travel, count)
			fill.Size = UDim2.fromScale(progress, 1)
			label.Text = string.format("Rub to shine: %.1f%% (%d surfaces)\nTEST travel %.3f / %.1f",
				progress * 100, count, travel, TEST_ONLY_MOVEMENT.requiredTravel)
		end, function(score)
			active = false
			if pointer then
				pointer:Destroy()
				pointer = nil
			end
			label.Text = "Polish complete! Local step score 100.\nNo item state, XP, rewards or saving."
			log(`complete: local score {score}; no production state`)
		end)
		pointer = PointerInput.new(clone, minigame, panel)
		active = true
		log("started - TEST ONLY movement tuning, no tools")
	end)
	if not ok then
		stopRun()
		label.Text = "Setup error - see Output. Fix the Polish fixture, then Start."
		if DEBUG then
			warn("[PolishTest] " .. tostring(reason))
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
	label.Text = "Cancelled - shine reset, input detached.\nPress Start for a fresh run."
	log("cancelled - Polish fixture and camera restored")
end))
table.insert(connections, player.CharacterRemoving:Connect(function()
	stopRun()
	fill.Size = UDim2.fromScale(0, 1)
	label.Text = "Character reset - test cancelled. Start after spawning."
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
log("ready - isolated Polish; Studio tests PENDING")
