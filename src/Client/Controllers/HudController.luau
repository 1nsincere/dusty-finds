-- HudController.luau
-- Purpose: HUD: money, level, buttons. Right now it only scales the HUD to the screen size so it fits
-- small phones (above the thumbstick) and isn't tiny on big monitors. Money/XP wiring comes with ClientState.
-- Owner: Dev 3 (Sean). Depends on: StarterGui.HUD (UI contract, docs/03 §8).
-- Init = set up and grab other modules (no waiting); Start = connect events.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local HudController = {}
local DEBUG = true

-- The HUD layout is about 325 px tall at scale 1 (top row → last left button) + bottom margin.
-- Scale = usable screen height / REFERENCE_HEIGHT, clamped so buttons never drop below ~44 px (52 × 0.85)
-- and never get comically large on a 4K monitor.
local REFERENCE_HEIGHT = 360
local MIN_SCALE = 0.85
local MAX_SCALE = 1.4

local uiScale: UIScale? = nil
local cameraConnection: RBXScriptConnection? = nil

local function updateScale()
	local camera = workspace.CurrentCamera
	if uiScale == nil or camera == nil then
		return
	end
	-- GetGuiInset().Y = Roblox's topbar height; the HUD starts below it (IgnoreGuiInset = false).
	local usableHeight = camera.ViewportSize.Y - GuiService:GetGuiInset().Y
	local scale = math.clamp(usableHeight / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
	uiScale.Scale = scale
	if DEBUG then
		print(`[HudController] viewport {camera.ViewportSize.X}x{camera.ViewportSize.Y}, scale {string.format("%.2f", scale)}`)
	end
end

local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		-- Fires when the window is resized or a phone rotates.
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()
end

function HudController.Init(_others)
	if DEBUG then
		print("[HudController] Init")
	end
end

function HudController.Start()
	if DEBUG then
		print("[HudController] Start")
	end
	-- Own thread: waiting for the HUD here must not hold up the other controllers' Start().
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD", 10)
		if hud == nil then
			warn("[HudController] PlayerGui.HUD not found: is StarterGui.HUD missing?")
			return
		end
		uiScale = hud:FindFirstChildOfClass("UIScale")
		if uiScale == nil then
			warn("[HudController] HUD has no UIScale (UI contract docs/03 §8)")
			return
		end
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
		watchCamera()
	end)
end

return HudController
