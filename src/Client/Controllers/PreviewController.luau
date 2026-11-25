-- PreviewController.luau (StarterPlayerScripts.Client.Controllers.PreviewController)
-- Purpose: "Try it for 60 seconds" (docs/11 section 5, docs/12 Stage 3). Shows a paint or a shelf / pedestal skin on YOUR shop
-- for a minute, flying the camera over the shop so you can see it from the market, then puts everything back. CLIENT ONLY:
-- nothing is saved, nothing is sent to the server, nobody else sees it. A banner shows the time left and a Stop button.
-- Owner: Dev 1 (Ace). Depends on: Shared.PlotTargets (same parts as the real paint / skin), Shared.Config (Paints, Skins),
-- UiSkin. Called by: PaintShopController and SkinShopController (their "Try" buttons).
-- Skins preview as colour + material only (no trim, glow or models), so the real thing looks a little richer than the preview.
-- Cashier skins can't be previewed yet (they are models drawn on each screen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlotTargets = require(Shared:WaitForChild("PlotTargets"))
local Paints = require(Shared:WaitForChild("Config"):WaitForChild("Paints"))
local Skins = require(Shared:WaitForChild("Config"):WaitForChild("Skins"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))

local PreviewController = {}
local DEBUG = true

local PREVIEW_SECONDS = 60
local player = Players.LocalPlayer

local active: {
	saved: { [BasePart]: { color: Color3, material: Enum.Material, applied: Color3 } },
	hidden: { [BasePart]: number },
	endsAt: number,
	label: string,
	camera: { type: Enum.CameraType, cframe: CFrame }?,
}? = nil
local gui: ScreenGui? = nil
local timeLabel: TextLabel? = nil
local others: { [string]: any } = {}

local function log(...)
	if DEBUG then
		print("[PreviewController]", ...)
	end
end

local function myPlot(): Instance?
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- ===== Banner =====

local function buildBanner()
	local screen = Instance.new("ScreenGui")
	screen.Name = "PreviewBanner"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 40
	screen.Enabled = false
	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -24)
	frame.Size = UDim2.fromOffset(380, 54)
	frame.BackgroundColor3 = Color3.fromRGB(34, 36, 42)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = screen
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiSkin.COLORS.accent
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, 4)
	label.Size = UDim2.new(1, -120, 1, -8)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.FontFace = UiSkin.FONT_TITLE
	label.TextColor3 = UiSkin.COLORS.text
	label.Text = ""
	label.Parent = frame
	local stop = Instance.new("TextButton")
	stop.Name = "Stop"
	stop.AnchorPoint = Vector2.new(1, 0.5)
	stop.Position = UDim2.new(1, -10, 0.5, 0)
	stop.Size = UDim2.fromOffset(92, 34)
	stop.BackgroundColor3 = UiSkin.COLORS.accent
	stop.BorderSizePixel = 0
	stop.TextScaled = true
	stop.FontFace = UiSkin.FONT_TITLE
	stop.TextColor3 = Color3.fromRGB(30, 24, 20)
	stop.Text = "Stop"
	stop.Parent = frame
	Instance.new("UICorner", stop).CornerRadius = UDim.new(0, 8)
	stop.Activated:Connect(function()
		PreviewController.Stop()
	end)
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, timeLabel = screen, label
end

-- ===== Preview =====

local function remember(state: any, part: BasePart, applied: Color3)
	if state.saved[part] == nil then
		state.saved[part] = { color = part.Color, material = part.Material, applied = applied }
	end
end

function PreviewController.IsActive(): boolean
	return active ~= nil
end

function PreviewController.Stop()
	local state = active
	if state == nil then
		return
	end
	active = nil
	for part, original in state.saved do
		-- only put it back if nobody changed it meanwhile (the server redraws the shop when you really buy and use something)
		if part.Parent and part.Color == original.applied then
			part.Color = original.color
			part.Material = original.material
		end
	end
	for part, transparency in state.hidden do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	local camera = workspace.CurrentCamera
	if camera and state.camera then
		camera.CameraType = state.camera.type
	end
	if gui then
		gui.Enabled = false
	end
	log("stopped")
end

-- Flies the camera over the shop (roof hidden for the minute) so the change can be seen from the market.
local function lookAtShop(state: any, plot: Instance)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local ok, cf, size = pcall(function()
		return plot:GetBoundingBox()
	end)
	if not ok then
		return
	end
	-- the roof and the upper floor (Facade.Roof / Facade.Upper) are hidden for the minute so the inside can be seen
	local facade = plot:FindFirstChild("Facade")
	for _, name in { "Roof", "Upper" } do
		local folder = facade and facade:FindFirstChild(name)
		for _, d in if folder then folder:GetDescendants() else {} do
			if d:IsA("BasePart") then
				state.hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	end
	-- "front" = from the back wall towards the middle of the shop
	local back = plot:FindFirstChild("Walls") and plot.Walls:FindFirstChild("BackWall")
	local front = Vector3.new(0, 0, 1)
	if back and back:IsA("BasePart") then
		local flat = Vector3.new(cf.Position.X - back.Position.X, 0, cf.Position.Z - back.Position.Z)
		if flat.Magnitude > 0.1 then
			front = flat.Unit
		end
	end
	local floorY = cf.Position.Y - size.Y / 2
	local target = Vector3.new(cf.Position.X, floorY + 4, cf.Position.Z)
	local from = target + front * 24 + Vector3.new(0, 52, 0)
	state.camera = { type = camera.CameraType, cframe = camera.CFrame }
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(from, target) }):Play()
end

-- kind = "Wall" | "Floor" (id = a paint) or "Shelf" | "Pedestal" (id = a skin). Returns ok, reason.
function PreviewController.Try(kind: string, id: string): (boolean, string?)
	local plot = myPlot()
	if plot == nil then
		return false, "You don't have a shop to preview in yet."
	end
	local label, targets, color, material
	if kind == "Wall" or kind == "Floor" then
		local paint = Paints.BY_ID[id]
		if paint == nil or paint.kind ~= kind then
			return false, "Unknown paint."
		end
		label, targets, color, material = paint.name, PlotTargets.paint(plot, kind), paint.color, paint.material
	elseif kind == "Shelf" or kind == "Pedestal" then
		local skin = Skins.BY_ID[id]
		if skin == nil or skin.kind ~= kind or skin.look == nil then
			return false, "Unknown skin."
		end
		label, targets, color, material = skin.name, PlotTargets.pieces(plot, kind), skin.look.color, skin.look.material
	else
		return false, "Cashier skins can't be previewed yet."
	end
	if #targets == 0 then
		return false, "Nothing to preview on your shop."
	end
	PreviewController.Stop() -- one preview at a time (puts the last one back first)
	local state = { saved = {}, hidden = {}, endsAt = os.clock() + PREVIEW_SECONDS, label = label, camera = nil }
	active = state
	for _, part in targets do
		remember(state, part, color)
		part.Color = color
		if material then
			part.Material = material
		end
	end
	lookAtShop(state, plot)
	if gui == nil then
		buildBanner()
	end
	(gui :: ScreenGui).Enabled = true
	log("trying", kind, id)
	return true, nil
end

function PreviewController.Init(controllers)
	others = controllers
end

function PreviewController.Start()
	RunService.Heartbeat:Connect(function()
		local state = active
		if state == nil then
			return
		end
		local left = math.ceil(state.endsAt - os.clock())
		if left <= 0 then
			PreviewController.Stop()
			return
		end
		if timeLabel then
			timeLabel.Text = `Trying {state.label} · {left}s`
		end
	end)
end

return PreviewController
