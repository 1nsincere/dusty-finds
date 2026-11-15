-- HudController.luau
-- Purpose: HUD: shows my money, level and XP progress from ClientState, and scales the HUD to the screen size
-- (fits small phones above the thumbstick, not tiny on big monitors). Rating stars stay a placeholder until
-- the server sends rating to the client. Buttons are wired by their own screens later.
-- Owner: Dev 3 (Sean). Depends on: ClientState, Shared.Formulas (xpToNext), Shared.Config.Economy (MaxLevel),
-- StarterGui.HUD (UI contract, docs/03 §8).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))

local HudController = {}
local DEBUG = true

-- The HUD layout is about 325 px tall at scale 1 (top row → last left button) + bottom margin.
-- Scale = usable screen height / REFERENCE_HEIGHT, clamped so buttons never drop below ~44 px (52 × 0.85)
-- and never get comically large on a 4K monitor.
local REFERENCE_HEIGHT = 360
local MIN_SCALE = 0.85
local MAX_SCALE = 1.4

local hud: ScreenGui? = nil
local uiScale: UIScale? = nil
local cameraConnection: RBXScriptConnection? = nil

-- ===== Money / level / XP =====

-- 1250 -> "1,250". Cash is always a whole number (EconomyService only allows integers).
local function formatCash(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text
	repeat
		local count
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return "$" .. formatted
end

local function updateMoney()
	local cash = ClientState.Get("cash")
	if hud == nil or type(cash) ~= "number" then
		return -- not loaded: keep the placeholder text from Studio
	end
	hud.MoneyPill.Amount.Text = formatCash(cash)
end

local function updateXp()
	local level = ClientState.Get("level")
	local xp = ClientState.Get("xp")
	if hud == nil or type(level) ~= "number" or type(xp) ~= "number" then
		return
	end
	local bar = hud.XPBar
	if level >= Economy.MaxLevel then
		bar.Level.Text = `Lv {level} MAX`
		bar.Fill.Size = UDim2.fromScale(1, 1)
		return
	end
	-- `xp` is progress inside the current level (EconomyService subtracts it on level-up).
	local needed = Formulas.xpToNext(level)
	local progress = if needed > 0 then math.clamp(xp / needed, 0, 1) else 0
	bar.Level.Text = `Lv {level}`
	bar.Fill.Size = UDim2.fromScale(progress, 1)
	if DEBUG then
		print(`[HudController] Lv {level}, xp {xp}/{needed}`)
	end
end

-- ===== Screen scaling =====

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

-- ===== Lifecycle =====

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
		local found = playerGui:WaitForChild("HUD", 10)
		if found == nil then
			warn("[HudController] PlayerGui.HUD not found: is StarterGui.HUD missing?")
			return
		end
		hud = found :: ScreenGui

		uiScale = found:FindFirstChildOfClass("UIScale")
		if uiScale then
			workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
			watchCamera()
		else
			warn("[HudController] HUD has no UIScale (UI contract docs/03 §8)")
		end

		-- Show what we have now, then follow every server change.
		updateMoney()
		updateXp()
		ClientState.OnChanged("cash", updateMoney)
		ClientState.OnChanged("level", updateXp)
		ClientState.OnChanged("xp", updateXp)
	end)
end

return HudController
