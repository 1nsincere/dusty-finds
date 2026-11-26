-- PreviewController.luau (StarterPlayerScripts.Client.Controllers.PreviewController)
-- Purpose: "Try it for 60 seconds" (docs/11 section 5, docs/12 Stage 3). Shows a paint, a skin or a whole theme on YOUR shop for a
-- minute and takes you INTO your shop (normal third-person camera, walk around and look): when the minute ends, or you press
-- "Go back", everything is put back and you are taken to where you were (the market). CLIENT ONLY: nothing is saved, nothing is
-- sent to the server, nobody else sees the look. A banner shows the time left.
-- (Version 1 flew the camera over the shop; it failed on real shops, so it was replaced by this walk-in preview.)
-- Owner: Dev 1 (Ace). Depends on: Shared.PlotTargets (same parts as the real paint / skin), Shared.Config (Paints, Skins),
-- UiSkin. Called by: PaintShopController and SkinShopController (their "Try" buttons).
-- Skins preview as colour + material only (no trim, glow or models), so the real thing looks a little richer than the preview.
-- Cashier skins can't be previewed yet (they are models drawn on each screen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlotTargets = require(Shared:WaitForChild("PlotTargets"))
local Paints = require(Shared:WaitForChild("Config"):WaitForChild("Paints"))
local Skins = require(Shared:WaitForChild("Config"):WaitForChild("Skins"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Contrast = require(Shared:WaitForChild("Contrast"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local PreviewController = {}
local DEBUG = true

local PREVIEW_SECONDS = 60
local player = Players.LocalPlayer

local active: {
	saved: { [BasePart]: { color: Color3, material: Enum.Material, transparency: number, applied: Color3 } },
	endsAt: number,
	label: string,
	returnTo: CFrame?, -- where you stood before the preview took you into your shop (nil = you were already in it)
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
	stop.Text = "Go back"
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
		local original = PlotTargets.snapshot(part)
		state.saved[part] = { color = original.color, material = original.material, transparency = original.transparency, applied = applied }
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
		if part.Parent and PlotTargets.shownColor(part) == original.applied then
			PlotTargets.restorePart(part, original)
		end
	end
	if gui then
		gui.Enabled = false
	end
	-- take you back to where you were (the market)
	local character = player.Character
	if state.returnTo and character and character.Parent then
		character:PivotTo(state.returnTo)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end
	log("stopped")
end

-- Takes you into your shop (unless you are already standing in it) and remembers where you were, so Stop can take you back.
-- You keep the normal third-person camera and can walk around while the look is on.
local function goToShop(state: any, plot: Instance)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local floor = plot:FindFirstChild("Floor")
	if not (character and hrp and hrp:IsA("BasePart") and floor and floor:IsA("BasePart")) then
		return
	end
	local dx = math.abs(hrp.Position.X - floor.Position.X)
	local dz = math.abs(hrp.Position.Z - floor.Position.Z)
	local dy = math.abs(hrp.Position.Y - floor.Position.Y)
	if dx < floor.Size.X / 2 and dz < floor.Size.Z / 2 and dy < 14 then
		return -- already inside your shop: stay where you are, nothing to go back to
	end
	state.returnTo = hrp.CFrame
	local spawn = plot:FindFirstChild("Spawn")
	local spot = if spawn and spawn:IsA("BasePart") then spawn.Position else floor.Position
	local at = Vector3.new(spot.X, floor.Position.Y + floor.Size.Y / 2 + 3.5, spot.Z)
	character:PivotTo(CFrame.lookAt(at, Vector3.new(floor.Position.X, at.Y, floor.Position.Z)))
	hrp.AssemblyLinearVelocity = Vector3.zero
end

-- What one thing looks like on the shop: the parts it covers + its colour / material. nil, reason if it can't be previewed.
local function describe(plot: Instance, kind: string, id: string): (any?, string?)
	if Paints.FIELD[kind] ~= nil then -- Wall, Floor, Trim, Accent
		local paint = Paints.BY_ID[id]
		if paint == nil or paint.kind ~= kind then
			return nil, "Unknown paint."
		end
		return { kind = kind, label = paint.name, targets = PlotTargets.paint(plot, kind), color = paint.color, material = paint.material,
			finish = paint.finish }, nil
	elseif kind == "Shelf" or kind == "Pedestal" then
		local skin = Skins.BY_ID[id]
		if skin == nil or skin.kind ~= kind or skin.look == nil then
			return nil, "Unknown skin."
		end
		return { label = skin.name, targets = PlotTargets.pieces(plot, kind), color = skin.look.color, material = skin.look.material }, nil
	end
	return nil, "Cashier skins can't be previewed yet."
end

-- Shows a list of { kind, id } on the shop together (one preview): a single paint or skin, or a whole theme.
local function start(label: string, items: { { string } }): (boolean, string?)
	local plot = myPlot()
	if plot == nil then
		return false, "You don't have a shop to preview in yet."
	end
	local parts = {}
	for _, item in items do
		local what, reason = describe(plot, item[1], item[2])
		if what == nil then
			if item[1] ~= "Cashier" then
				return false, reason
			end
		elseif #what.targets > 0 then
			table.insert(parts, what)
		end
	end
	if #parts == 0 then
		return false, "Nothing to preview on your shop."
	end
	-- the trim contrast guard, like the real shop (PaintService.Effective): the trim in the preview is moved lighter or darker if it would
	-- blend into the wall. If the preview changes the wall but not the trim, the trim you have now is re-checked against the new wall.
	local saved = ClientState.Get("paints")
	local function chosen(kind: string): any
		local id = if type(saved) == "table" then saved[Paints.FIELD[kind]] else nil
		return (if type(id) == "string" then Paints.BY_ID[id] else nil) or Paints.DEFAULTS[kind]
	end
	local wallColor, trimItem, wallItem = chosen("Wall").color, nil, nil
	for _, what in parts do
		if what.kind == "Wall" then
			wallColor, wallItem = what.color, what
		elseif what.kind == "Trim" then
			trimItem = what
		end
	end
	if trimItem == nil and wallItem ~= nil then
		local current = chosen("Trim")
		trimItem = { kind = "Trim", label = "Trim", targets = PlotTargets.paint(plot, "Trim"), color = current.color, material = current.material, finish = current.finish }
		table.insert(parts, trimItem)
	end
	if trimItem ~= nil then
		trimItem.color = Contrast.fixTrim(wallColor, trimItem.color)
	end
	-- one preview at a time: put the last one back first, but keep WHERE you came from (no trip back to the market in between)
	local carry = if active then active.returnTo else nil
	if active then
		active.returnTo = nil
	end
	PreviewController.Stop()
	local state = { saved = {}, endsAt = os.clock() + PREVIEW_SECONDS, label = label, returnTo = carry }
	active = state
	for _, what in parts do
		for _, part in what.targets do
			remember(state, part, what.color)
			PlotTargets.paintPart(part, what.color, what.material, what.finish) -- textured parts are tinted (SurfaceAppearance; a premium finish swaps its maps), plain parts recoloured
		end
	end
	goToShop(state, plot)
	if gui == nil then
		buildBanner()
	end
	(gui :: ScreenGui).Enabled = true
	log("trying", label)
	return true, nil
end

-- kind = "Wall" | "Floor" (id = a paint) or "Shelf" | "Pedestal" (id = a skin). Returns ok, reason.
function PreviewController.Try(kind: string, id: string): (boolean, string?)
	local plot = myPlot()
	local what = if plot then describe(plot, kind, id) else nil
	return start(if what then what.label else "it", { { kind, id } })
end

-- A whole theme (Config.Monetization pass with `grants`): its wall, floor, shelf and pedestal skin together. Returns ok, reason.
function PreviewController.TryTheme(label: string, paintIds: { string }, skinIds: { string }): (boolean, string?)
	local items = {}
	for _, id in paintIds do
		local paint = Paints.BY_ID[id]
		if paint then
			table.insert(items, { paint.kind, id })
		end
	end
	for _, id in skinIds do
		local skin = Skins.BY_ID[id]
		if skin and skin.kind ~= "Cashier" then
			table.insert(items, { skin.kind, id })
		end
	end
	return start(label, items)
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
