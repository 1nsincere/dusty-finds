-- AutoRunController.luau
-- Purpose: Auto Run. Toggle it (Menu -> Auto Run, the green "AUTO RUN" pill, or press R) and your character keeps
-- walking forward in the direction the camera faces, so you can steer by turning the camera. It stops by itself when
-- you give any manual movement input (keys / thumbstick), sit, die, respawn, or the camera is taken over (restoring).
-- Works together with Sprint (Sprint only changes walk speed). Client only: it just feeds the player's own Humanoid, like
-- the normal controls do, so there is nothing for the server to trust.
-- Owner: Dev 1 (Ace). Depends on: PlayerModule (Roblox's default controls, to read manual input). UI is HudLayoutController.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MOVE_KEYS = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true,
}

local AutoRunController = {}
local DEBUG = true
local MANUAL_INPUT_DEADZONE = 0.2 -- how hard the stick / keys must be pushed to count as "I took over"
local GRACE_SECONDS = 0.15 -- ignore input for a moment after turning on (the tap that turned it on)

local on = false
local startedAt = 0
local controls: any = nil
local listeners: { (boolean, string?) -> () } = {}

local function log(...)
	if DEBUG then
		print("[AutoRunController]", ...)
	end
end

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setOn(value: boolean, reason: string?)
	if value == on then
		return
	end
	on = value
	if on then
		startedAt = os.clock()
	end
	log(if on then "ON" else "OFF", reason or "")
	for _, callback in listeners do
		task.spawn(callback, on, reason)
	end
end

function AutoRunController.IsOn(): boolean
	return on
end

function AutoRunController.Set(value: boolean)
	setOn(value, "set")
end

function AutoRunController.Toggle()
	setOn(not on, "toggle")
end

-- callback(isOn, reason). Returns an object with :Disconnect().
function AutoRunController.OnChanged(callback: (boolean, string?) -> ())
	table.insert(listeners, callback)
	return {
		Disconnect = function()
			local index = table.find(listeners, callback)
			if index then
				table.remove(listeners, index)
			end
		end,
	}
end

-- Runs every frame AFTER Roblox's own controls (which write the player's input into the Humanoid), so ours wins
-- whenever there is no manual input.
local function step()
	if not on then
		return
	end
	local humanoidInstance = humanoid()
	local camera = workspace.CurrentCamera
	if
		humanoidInstance == nil
		or humanoidInstance.Health <= 0
		or humanoidInstance.SeatPart ~= nil
		or (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable)
	then
		setOn(false, "blocked")
		return
	end
	if controls ~= nil and os.clock() - startedAt > GRACE_SECONDS then
		local ok, moveVector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(moveVector) == "Vector3" and moveVector.Magnitude > MANUAL_INPUT_DEADZONE then
			setOn(false, "manual input")
			return
		end
	end
	humanoidInstance:Move(Vector3.new(0, 0, -1), true) -- forward, relative to the camera
end

function AutoRunController.Init(_controllers) end

function AutoRunController.Start()
	-- Roblox's default control module: lets us tell "the player is pushing the stick" from "nothing pressed".
	task.spawn(function()
		local ok, result = pcall(function()
			local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
			local playerModule = require(playerScripts:WaitForChild("PlayerModule", 15))
			return playerModule:GetControls()
		end)
		if ok then
			controls = result
		else
			-- No PlayerModule here (e.g. some Studio test clients): the direct input checks below still stop Auto Run.
			log("default controls not available, using direct input detection only")
		end
	end)

	-- Manual input detection that does not depend on the default control module: movement keys, a touch on the
	-- left half of the screen (the thumbstick side) that no button used, or the gamepad stick.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not on or processed or os.clock() - startedAt <= GRACE_SECONDS then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and MOVE_KEYS[input.KeyCode] then
			setOn(false, "manual input")
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local camera = workspace.CurrentCamera
			if camera and input.Position.X < camera.ViewportSize.X * 0.5 then
				setOn(false, "manual input")
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if on and input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.35 then
			setOn(false, "manual input")
		end
	end)

	RunService:BindToRenderStep("DF_AutoRun", Enum.RenderPriority.Input.Value + 1, step)
	ContextActionService:BindAction("DF_AutoRunKey", function(_, state)
		if state == Enum.UserInputState.Begin then
			AutoRunController.Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		setOn(false, "respawn")
	end)
	log("ready: Menu -> Auto Run, or press R")
end

return AutoRunController
