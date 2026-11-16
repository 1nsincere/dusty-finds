-- AdminController.luau
-- Purpose: dev exploring tools as chat commands (/fly, /noclip, /speed, /jump, /tp, /plot, /zoom, /cmds) for the three devs.
-- Owner: Dev 1 (Ace). Depends on: TextChatService (chat commands), Players, the PlayerModule controls (for fly input).
-- STUDIO ONLY: outside Studio this controller does nothing at all (no commands, no input), so players on the live game never get it.
-- Client only, no remotes, nothing on the server changes. Movement is of your OWN character, which Roblox lets the client do anyway.
-- Money, items and levels stay server-side: use ServerStorage.DevTools for those (docs/08, docs/STUDIO_TESTING.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local AdminController = {}
local DEBUG = true

local DEFAULT_FLY_SPEED = 60
local MAX_SPEED = 500
local player = Players.LocalPlayer

local flying = false
local flySpeed = DEFAULT_FLY_SPEED
local noclip = false
local flyConnection: RBXScriptConnection? = nil
local noclipConnection: RBXScriptConnection? = nil

local function say(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		system:DisplaySystemMessage("[admin] " .. text)
	end
	if DEBUG then
		print("[AdminController] " .. text)
	end
end

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return char, humanoid, root
	end
	return nil, nil, nil
end

local function numberArg(text: string?): number?
	local n = tonumber(text)
	if n == nil or n ~= n or math.abs(n) > 1e6 then
		return nil
	end
	return n
end

local function splitArgs(unfiltered: string): { string }
	local args = {}
	for word in string.gmatch(unfiltered, "%S+") do
		table.insert(args, word)
	end
	table.remove(args, 1) -- the command itself
	return args
end

-- ===== Fly =====
local function moveVector(): Vector3
	local ok, controls = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)
	if ok and controls then
		return controls:GetMoveVector() -- x = right, z = back (negative z = forward)
	end
	return Vector3.zero
end

local function stopFly()
	flying = false
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
	local _, humanoid, root = character()
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function startFly()
	local _, humanoid = character()
	if humanoid == nil then
		return
	end
	flying = true
	humanoid.PlatformStand = true
	flyConnection = RunService.RenderStepped:Connect(function()
		local _, hum, root = character()
		local camera = workspace.CurrentCamera
		if hum == nil or root == nil or camera == nil then
			return
		end
		hum.PlatformStand = true
		local input = moveVector()
		local direction = camera.CFrame.RightVector * input.X + camera.CFrame.LookVector * -input.Z
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			direction += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			direction -= Vector3.yAxis
		end
		root.AssemblyLinearVelocity = if direction.Magnitude > 0 then direction.Unit * flySpeed else Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- ===== Noclip =====
local function setNoclip(on: boolean)
	noclip = on
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
	if on then
		noclipConnection = RunService.Stepped:Connect(function()
			local char = player.Character
			if char then
				for _, part in char:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanCollide = false
					end
				end
			end
		end)
	end
end

-- ===== Commands =====
local commands: { [string]: { help: string, run: (args: { string }) -> () } } = {}

commands.cmds = {
	help = "/cmds : list the commands",
	run = function()
		local names = {}
		for _, def in commands do
			table.insert(names, def.help)
		end
		table.sort(names)
		say("commands:\n" .. table.concat(names, "\n"))
	end,
}

commands.fly = {
	help = "/fly [speed] : toggle flying (WASD, Space up, Ctrl or Q down)",
	run = function(args)
		local speed = if args[1] then numberArg(args[1]) else nil
		if speed then
			flySpeed = math.clamp(speed, 5, MAX_SPEED)
		end
		if flying and speed == nil then
			stopFly()
			say("fly OFF")
		else
			if not flying then
				startFly()
			end
			say(`fly ON, speed {flySpeed}`)
		end
	end,
}

commands.noclip = {
	help = "/noclip : toggle walking through walls",
	run = function()
		setNoclip(not noclip)
		say(if noclip then "noclip ON" else "noclip OFF")
	end,
}

commands.speed = {
	help = "/speed n : walk speed (default 16)",
	run = function(args)
		local n = numberArg(args[1])
		local _, humanoid = character()
		if n == nil or humanoid == nil then
			return say("usage: /speed 50")
		end
		humanoid.WalkSpeed = math.clamp(n, 0, MAX_SPEED)
		say(`walk speed {humanoid.WalkSpeed}`)
	end,
}

commands.jump = {
	help = "/jump n : jump height in studs (default 7.2)",
	run = function(args)
		local n = numberArg(args[1])
		local _, humanoid = character()
		if n == nil or humanoid == nil then
			return say("usage: /jump 30")
		end
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = math.clamp(n, 0, 1000)
		say(`jump height {humanoid.JumpHeight}`)
	end,
}

commands.zoom = {
	help = "/zoom n : camera max zoom-out (the game limits it to 20)",
	run = function(args)
		local n = numberArg(args[1])
		if n == nil then
			return say("usage: /zoom 200")
		end
		player.CameraMaxZoomDistance = math.clamp(n, 1, 5000)
		say(`max zoom {player.CameraMaxZoomDistance}`)
	end,
}

commands.tp = {
	help = "/tp x y z  or  /tp playerName : teleport",
	run = function(args)
		local _, _, root = character()
		if root == nil then
			return
		end
		local x, y, z = numberArg(args[1]), numberArg(args[2]), numberArg(args[3])
		if x and y and z then
			root.CFrame = CFrame.new(x, y, z)
			return say(`teleported to {x}, {y}, {z}`)
		end
		local wanted = args[1] and string.lower(args[1])
		if wanted then
			for _, other in Players:GetPlayers() do
				local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if other ~= player and otherRoot and (string.find(string.lower(other.Name), wanted, 1, true) or string.find(string.lower(other.DisplayName), wanted, 1, true)) then
					root.CFrame = otherRoot.CFrame + Vector3.new(0, 3, 4)
					return say("teleported to " .. other.Name)
				end
			end
			return say("no player matches " .. args[1])
		end
		say("usage: /tp 0 10 0   or   /tp playerName")
	end,
}

commands.plot = {
	help = "/plot n : teleport to shop n (1-6)",
	run = function(args)
		local n = numberArg(args[1])
		local plots = workspace:FindFirstChild("Plots")
		local plot = plots and n and plots:FindFirstChild("Plot" .. math.floor(n))
		local spawnPart = plot and plot:FindFirstChild("Spawn")
		local _, _, root = character()
		if root and spawnPart and spawnPart:IsA("BasePart") then
			root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
			say("teleported to Plot" .. math.floor(n))
		else
			say("usage: /plot 1 (needs Workspace.Plots.PlotN.Spawn)")
		end
	end,
}

commands.normal = {
	help = "/normal : turn everything off (fly, noclip, speed, jump)",
	run = function()
		if flying then
			stopFly()
		end
		setNoclip(false)
		local _, humanoid = character()
		if humanoid then
			humanoid.WalkSpeed = 16
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = 7.2
		end
		say("back to normal")
	end,
}

function AdminController.Init(_controllers) end

function AdminController.Start()
	if not RunService:IsStudio() then
		return -- live game: no commands, no input, nothing
	end
	local folder = TextChatService:WaitForChild("TextChatCommands", 10)
	if folder == nil then
		warn("[AdminController] TextChatService.TextChatCommands not found: admin commands are off")
		return
	end
	for name, def in commands do
		local command = Instance.new("TextChatCommand")
		command.Name = "Admin_" .. name
		command.PrimaryAlias = "/" .. name
		command.Triggered:Connect(function(_source, unfilteredText)
			local ok, err = pcall(def.run, splitArgs(unfilteredText))
			if not ok then
				warn("[AdminController] /" .. name .. " failed: " .. tostring(err))
			end
		end)
		command.Parent = folder
	end
	-- the character is replaced on respawn: fly and noclip would silently stop, so reset them honestly
	player.CharacterAdded:Connect(function()
		flying = false
		if flyConnection then
			flyConnection:Disconnect()
			flyConnection = nil
		end
	end)
	if DEBUG then
		print("[AdminController] Studio only: type /cmds in chat")
	end
end

return AdminController
