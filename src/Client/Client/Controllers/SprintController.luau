-- SprintController.luau
-- Purpose: sprinting. Hold Left Shift (PC) or tap the lightning HUD button (phone / any device, toggles) to run faster,
-- with a small camera FOV kick. Stops by itself while seated (jeepney/tricycle) or restoring (scriptable camera).
-- Owner: Dev 1 (Ace). Depends on: HudSkinController (HUD button), Shared.Config.UiSkin. Client only: a player's own
-- walk speed is theirs to control in Roblox, and it gives no advantage in money or items.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Skin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UiSkin"))

local SprintController = {}
local DEBUG = true
local WALK, RUN = 16, 26
local FOV_KICK = 8

local others: { [string]: any } = {}
local held, toggled = false, false
local running = false
local baseFov: number? = nil
local button: GuiButton? = nil

local function log(...)
	if DEBUG then
		print("[SprintController]", ...)
	end
end

local function humanoid(): Humanoid?
	local c = Players.LocalPlayer.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function setRunning(on: boolean)
	if on == running then
		return
	end
	running = on
	local h = humanoid()
	if h then
		h.WalkSpeed = if on then RUN else WALK
	end
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		baseFov = baseFov or camera.FieldOfView
		TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Sine), { FieldOfView = baseFov + (if on then FOV_KICK else 0) }):Play()
	end
	if button then
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if on then Skin.COLORS.accent else Skin.COLORS.edge
			stroke.Transparency = if on then 0.1 else Skin.COLORS.edgeTransparency
		end
	end
end

function SprintController.Init(controllers)
	others = controllers
end

function SprintController.Start()
	ContextActionService:BindAction("DF_Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			held = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held = false
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	task.spawn(function()
		local skin = others.HudSkinController
		button = skin and skin.HudButton("Sprint", Skin.ICONS.Sprint)
		if button then
			button.Activated:Connect(function()
				toggled = not toggled
			end)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		running = false
		toggled = false
		baseFov = nil
	end)
	RunService.Heartbeat:Connect(function()
		local h = humanoid()
		local camera = workspace.CurrentCamera
		local blocked = h == nil or h.SeatPart ~= nil or h.Health <= 0 or (camera and camera.CameraType == Enum.CameraType.Scriptable)
		local want = (held or toggled) and not blocked
		setRunning(want)
		if running and h and h.WalkSpeed ~= RUN then
			h.WalkSpeed = RUN -- another script reset it
		end
	end)
	log("ready: hold Shift or tap the lightning button")
end

return SprintController
