-- RestorationMoreMinigamesController.luau
-- Purpose: registers the Test, Scrape, Reassemble and Replace minigames with RestorationController.RegisterMinigame
-- (Wipe and Polish are registered by Dwayne's RestorationMinigamesController: different file on purpose, so we never edit the same one).
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: RestorationController (RegisterMinigame, RunPlaceholder), Client/Minigames/*,
-- Shared.Config.Items (rarity for the Test green zone), ClientState (to find the item being restored).
--
-- Test needs no model: it draws its own bar and works right now.
-- Scrape / Reassemble / Replace need ctx.model (a local clone of Assets/Items/<ItemId>) and ctx.attachPointer(minigameObject) -> cleanup,
-- which Dwayne's RestorationView supplies through RestorationController.SetViewProvider. Without them the step falls back to the
-- hold-the-button placeholder, so the loop never gets stuck.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config:WaitForChild("Items"))
local Skin = require(Shared.Config:WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Minigames = script.Parent.Parent:WaitForChild("Minigames")
local TestGame = require(Minigames:WaitForChild("Test"))
local ScrapeGame = require(Minigames:WaitForChild("Scrape"))
local ReassembleGame = require(Minigames:WaitForChild("Reassemble"))
local ReplaceGame = require(Minigames:WaitForChild("Replace"))

local RestorationMoreMinigamesController = {}
local DEBUG = true
local player = Players.LocalPlayer
local controller: any = nil
local sounds: any = nil -- SoundController (optional)

local function playSound(name: string)
	if sounds then
		sounds.Play(name)
	end
end

local TEST_LABELS = { Switch = "Flip the switch!", Wind = "Wind it up!", Shake = "Give it a shake!", Play = "Press play!" }

local function log(...)
	if DEBUG then
		print("[RestorationMoreMinigames]", ...)
	end
end

local function rarityOf(uid: string): string?
	local item = ClientState.Get("inventory." .. uid)
	local config = type(item) == "table" and Items[item.itemId] or nil
	return config and config.rarity
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.Parent = parent
	return f
end

-- ===== Test: a retro LED meter with a sweeping light; tap to stop it in the green (redesigned 2026-11-25) =====
-- Not a flat bar any more: a row of LED cells (red edges, yellow, a green middle) with a light that sweeps along and leaves a glowing trail,
-- a little marker above it, and a chunky 3D key that matches the item's test (PLAY / FLIP / WIND / SHAKE) and sinks when pressed.
-- Tap the key, tap the meter or press Space / Enter. A good stop stamps the result for a moment before the step ends.
local TEST_KEYS = {
	Play = { "▶", "PLAY", "Press play, then hit the green!" },
	Switch = { "⏻", "FLIP", "Flip the switch at the right moment!" },
	Wind = { "⟳", "WIND", "Wind it up, stop in the green!" },
	Shake = { "≋", "SHAKE", "Give it a shake, stop in the green!" },
}
local TEST_CELLS = 28

local function runTest(ctx)
	local step = table.clone(ctx.step)
	step.rarity = rarityOf(ctx.uid)
	step.center = 0.5 -- the green zone is always in the middle of the meter (Ace, 2026-11-26); the recipe's own `center` is ignored
	local closed = false
	local pendingScore: number? = nil
	local game_
	game_ = TestGame.new(nil, step, function(fraction)
		if not closed then
			ctx.setProgress(fraction)
		end
	end, function(score)
		pendingScore = score -- the result is shown first; the step ends in a moment (see tap)
	end)

	local C = Skin.COLORS
	local key = TEST_KEYS[step.style] or { "●", "TAP", "Stop the light in the green!" }
	local gui = Instance.new("ScreenGui")
	gui.Name = "RestorationTest"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.IgnoreGuiInset = true

	-- the device: a dark casing with a cream bezel, bottom centre (a little right of centre: the HUD column is on the left)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -18)
	card.Size = UDim2.fromOffset(600, 196)
	card.BackgroundColor3 = C.walnut
	card.BorderSizePixel = 0
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 22)
	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = ColorSequence.new(C.panelTop, C.panelBottom)
	cardGradient.Rotation = 90
	cardGradient.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = C.ink
	cardStroke.Thickness = 3
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardStroke.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local function rescale()
		local view = gui.AbsoluteSize
		if view.X > 0 and view.Y > 0 then
			cardScale.Scale = math.clamp(math.min(view.X * 0.94 / 600, view.Y / 700), 0.55, 1.1)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	local label = Instance.new("TextLabel")
	label.Name = "Prompt"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(0, 10)
	label.Size = UDim2.new(1, 0, 0, 26)
	label.FontFace = Skin.FONT_TITLE
	label.TextSize = 20
	label.TextColor3 = C.edge
	label.Text = key[3]
	label.Parent = card

	-- the LED meter inside a dark window
	local window = frame(card, "Window", UDim2.fromOffset(20, 48), UDim2.new(1, -40, 0, 56), Color3.fromRGB(20, 12, 8))
	Instance.new("UICorner", window).CornerRadius = UDim.new(0, 12)
	local windowStroke = Instance.new("UIStroke")
	windowStroke.Color = C.accentDim
	windowStroke.Thickness = 2
	windowStroke.Parent = window
	local z = game_.zone
	local cells = {}
	local zoneOf = {}
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 3)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = window
	local cellWidth = (560 - 24 - 3 * (TEST_CELLS - 1)) / TEST_CELLS
	for i = 1, TEST_CELLS do
		local centre = (i - 0.5) / TEST_CELLS
		local zone = if centre >= z.greenFrom and centre <= z.greenTo then "green" elseif centre >= z.yellowFrom and centre <= z.yellowTo then "yellow" else "red"
		zoneOf[i] = zone
		local cell = Instance.new("Frame")
		cell.Name = "Cell" .. i
		cell.LayoutOrder = i
		cell.Size = UDim2.fromOffset(cellWidth, if zone == "green" then 34 else if zone == "yellow" then 28 else 22)
		cell.BackgroundColor3 = if zone == "green" then Color3.fromHex("46E07A") elseif zone == "yellow" then Color3.fromHex("FFD43B") else Color3.fromHex("FF5A52")
		cell.BackgroundTransparency = 0.8
		cell.BorderSizePixel = 0
		cell.Parent = window
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 4)
		cells[i] = cell
	end
	-- a marker above the window that follows the light
	local marker = Instance.new("TextLabel")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.BackgroundTransparency = 1
	marker.Size = UDim2.fromOffset(24, 16)
	marker.Position = UDim2.new(0, 32, 0, 50)
	marker.FontFace = Skin.FONT_TITLE
	marker.TextSize = 16
	marker.TextColor3 = C.accent
	marker.Text = "▼"
	marker.Parent = card

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(0, 108)
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.FontFace = Skin.FONT_TEXT
	caption.TextSize = 11
	caption.TextColor3 = C.accentDim
	caption.Text = "STOP THE LIGHT IN THE GREEN"
	caption.Parent = card

	-- the key: a dark base with the key on top, offset up; pressing sinks it
	local KEY_W, KEY_H, LIFT = 250, 50, 6
	local base = frame(card, "KeyBase", UDim2.new(0.5, 0, 1, -14), UDim2.fromOffset(KEY_W, KEY_H), Color3.fromRGB(150, 52, 34))
	base.AnchorPoint = Vector2.new(0.5, 1)
	Instance.new("UICorner", base).CornerRadius = UDim.new(0, 18)
	local button = Instance.new("TextButton")
	button.Name = "TapButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -14 - LIFT)
	button.Size = UDim2.fromOffset(KEY_W, KEY_H)
	button.BackgroundColor3 = Color3.fromHex("FF6A4D")
	button.TextColor3 = Color3.new(1, 1, 1)
	button.FontFace = Skin.FONT_TITLE
	button.TextSize = 26
	button.Text = `{key[1]}  {key[2]}`
	button.AutoButtonColor = false
	button.Parent = card
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 18)
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = C.ink
	buttonStroke.Thickness = 3
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = button
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 215, 215))
	shine.Rotation = 90
	shine.Parent = button

	-- the stamp that pops up with the result
	local stamp = Instance.new("TextLabel")
	stamp.Name = "Stamp"
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.BackgroundTransparency = 1
	stamp.Position = UDim2.new(0.5, 0, 0.5, -34)
	stamp.Size = UDim2.fromOffset(300, 56)
	stamp.FontFace = Skin.FONT_TITLE
	stamp.TextSize = 44
	stamp.Text = ""
	stamp.Visible = false
	stamp.ZIndex = 5
	stamp.Parent = card
	local stampStroke = Instance.new("UIStroke")
	stampStroke.Color = C.ink
	stampStroke.Thickness = 3
	stampStroke.Parent = stamp
	local stampScale = Instance.new("UIScale")
	stampScale.Parent = stamp

	gui.Parent = player:WaitForChild("PlayerGui")
	rescale()

	local resetToken = 0
	local function say(text: string, color: Color3, back: boolean)
		label.Text = text
		label.TextColor3 = color
		resetToken += 1
		local token = resetToken
		if back then
			task.delay(0.9, function()
				if not closed and token == resetToken then
					label.Text = key[3]
					label.TextColor3 = C.edge
				end
			end)
		end
	end
	local function pop(text: string, color: Color3)
		stamp.Text = text
		stamp.TextColor3 = color
		stamp.Visible = true
		stampScale.Scale = 0.4
		TweenService:Create(stampScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local function press(down: boolean)
		TweenService:Create(button, TweenInfo.new(0.06), {
			Position = UDim2.new(0.5, 0, 1, -14 - (if down then 1 else LIFT)),
		}):Play()
	end

	local function tap()
		if closed or pendingScore ~= nil then
			return
		end
		local result = game_:OnPointerDown(nil)
		if result == "red" then
			say("Missed! Try again", Color3.fromHex("FF8A80"), true)
			cardStroke.Color = Color3.fromHex("E0524D")
			task.delay(0.25, function()
				if not closed then
					cardStroke.Color = C.ink
				end
			end)
		elseif result == "yellow" or result == "green" then
			local perfect = result == "green"
			say(if perfect then "Perfect timing!" else "Good one!", if perfect then Color3.fromHex("7DE08D") else Color3.fromHex("FFD43B"), false)
			pop(if perfect then "PERFECT!" else "NICE!", if perfect then Color3.fromHex("7DE08D") else Color3.fromHex("FFD43B"))
			button.Active = false
			button.BackgroundColor3 = if perfect then Color3.fromHex("3DBE6B") else Color3.fromHex("FFB300")
			-- flash the lit zone
			for i, cell in cells do
				if zoneOf[i] == result then
					cell.BackgroundTransparency = 0
				end
			end
			task.delay(0.65, function()
				if not closed and pendingScore ~= nil then
					ctx.complete(pendingScore)
				end
			end)
		end
	end

	local downs = button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(true)
		end
	end)
	local ups = button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press(false)
		end
	end)
	local tapped = button.Activated:Connect(tap)
	local windowTapped = window.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tap()
		end
	end)
	local keys = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			press(true)
			task.delay(0.1, function()
				if not closed then
					press(false)
				end
			end)
			tap()
		end
	end)
	local beat = RunService.Heartbeat:Connect(function(dt)
		game_:Update(dt)
		local needle = game_.needle
		local index = math.clamp(math.floor(needle * TEST_CELLS) + 1, 1, TEST_CELLS)
		if pendingScore == nil then
			for i, cell in cells do
				local glow = math.max(0, 1 - math.abs(i - index) / 3) -- a lit head with a soft trail either side
				cell.BackgroundTransparency = 0.8 - 0.8 * glow
			end
			-- the marker sits exactly over the lit cell and stops with it when you tap (it used to keep sweeping after the tap, so it
			-- drifted far away from the frozen light). The cells span x 32..568 inside the card (window at 20 + 12 padding).
			marker.Position = UDim2.fromOffset(32 + 536 * ((index - 0.5) / TEST_CELLS), 50)
		end
	end)
	return function()
		closed = true
		tapped:Disconnect()
		downs:Disconnect()
		ups:Disconnect()
		windowTapped:Disconnect()
		keys:Disconnect()
		beat:Disconnect()
		game_:Destroy()
		gui:Destroy()
	end
end

-- ===== Repair feedback (Reassemble/Replace): what is selected, where it goes, right or wrong =====
local SELECT_COLOR = Color3.fromHex("FFD43B")
local SOCKET_COLOR = Color3.fromHex("5BC0EB")
local WRONG_COLOR = Color3.fromHex("E0524D")

local function burst(part: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(12)
	Debris:AddItem(attachment, 1.2)
end

-- Returns the fx table Socket.luau calls, plus a cleanup. Highlights live in the item view model, so they go with it.
local function repairFx(model: Instance)
	local made: { Instance } = {}
	local selected = Instance.new("Highlight")
	selected.Name = "SelectedPart"
	selected.FillColor = SELECT_COLOR
	selected.OutlineColor = SELECT_COLOR
	selected.FillTransparency = 0.6
	selected.DepthMode = Enum.HighlightDepthMode.Occluded
	selected.Enabled = false
	selected.Parent = model
	table.insert(made, selected)
	local sockets = model:FindFirstChild("Sockets")
	if sockets then -- the empty spots glow so you can see where parts go
		local glow = Instance.new("Highlight")
		glow.Name = "SocketGlow"
		glow.Adornee = sockets
		glow.FillColor = SOCKET_COLOR
		glow.OutlineColor = SOCKET_COLOR
		glow.FillTransparency = 0.5
		glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- shows through the item: a spot inside the body (the lamp's bulb) must still be visible
		glow.Parent = model
		table.insert(made, glow)
	end
	local fx = {}
	local connections: { RBXScriptConnection } = {}

	-- ===== Where does it go? (Ace + Claude, 2026-11-25) =====
	-- A bobbing arrow over every empty spot says "GOES HERE", a guide line runs from the loose part to its spot, and the part
	-- gets a "PICK ME" arrow. In Replace the tray holds decoys, so which PART is right is the puzzle: its arrow and line stay
	-- hidden until you get one wrong or wait 8 seconds; the spot is always marked. Everything disappears as parts fit.
	local function basePartOf(instance: Instance): BasePart?
		if instance:IsA("BasePart") then
			return instance
		end
		if instance:IsA("Model") then
			return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		end
		return nil
	end
	local function heightOf(instance: Instance): number
		if instance:IsA("Model") then
			return instance:GetExtentsSize().Y
		end
		return if instance:IsA("BasePart") then instance.Size.Y else 1
	end
	local function marker(target: Instance, label: string, color: Color3): BillboardGui?
		local base = basePartOf(target)
		if base == nil then
			return nil
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "RepairGuide"
		gui.Adornee = base
		gui.AlwaysOnTop = false -- (an AlwaysOnTop billboard did not draw in tests, the tutorial arrow hit the same); it floats above the part anyway
		gui.LightInfluence = 0
		gui.Size = UDim2.fromOffset(150, 84)
		-- a spot hidden INSIDE the item (inside a solid part's box, like the lamp's bulb in its foot) gets its arrow above the item's top,
		-- otherwise the arrow would sit inside the item, hidden behind it
		local offsetY = heightOf(target) / 2 + 0.55
		local inside = false
		local topY = -math.huge
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 0.2 and p ~= base and not p:IsDescendantOf(target) then
				local folderName = p.Parent and p.Parent.Name
				if folderName ~= "Sockets" and folderName ~= "LooseParts" and p.Name ~= "Base" then
					topY = math.max(topY, p.Position.Y + p.Size.Y / 2)
					local local_ = p.CFrame:PointToObjectSpace(base.Position)
					if math.abs(local_.X) <= p.Size.X / 2 and math.abs(local_.Y) <= p.Size.Y / 2 and math.abs(local_.Z) <= p.Size.Z / 2 then
						inside = true
					end
				end
			end
		end
		if inside and topY > -math.huge then
			offsetY = math.max(offsetY, topY - base.Position.Y + 0.6)
		end
		gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
		gui:SetAttribute("BaseY", offsetY)
		gui.MaxDistance = 200
		gui.Parent = base -- on the part itself (a gui under a Model did not draw)
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(1, 0, 0, 26)
		text.Font = Enum.Font.GothamBold
		text.Text = label
		text.TextSize = 19
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(43, 27, 20)
		stroke.Parent = text
		local arrow = Instance.new("TextLabel") -- ▼ (the arrow emoji draws nothing in a BillboardGui, the plain glyph does)
		arrow.Name = "Arrow"
		arrow.BackgroundTransparency = 1
		arrow.Position = UDim2.fromOffset(0, 24)
		arrow.Size = UDim2.new(1, 0, 0, 52)
		arrow.Font = Enum.Font.GothamBold
		arrow.Text = "▼"
		arrow.TextSize = 50
		arrow.TextColor3 = color
		arrow.Parent = gui
		local arrowStroke = Instance.new("UIStroke")
		arrowStroke.Thickness = 3
		arrowStroke.Color = Color3.fromRGB(43, 27, 20)
		arrowStroke.Parent = arrow
		table.insert(made, gui)
		return gui
	end
	local function guideBeam(part: Instance, socket: Instance): Beam?
		local a, b = basePartOf(part), basePartOf(socket)
		if a == nil or b == nil then
			return nil
		end
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = a, b
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = 0.11, 0.11
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120))
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Segments = 24
		beam.CurveSize0, beam.CurveSize1 = 0.7, -0.7 -- a gentle arc so it never runs through the item
		beam.Parent = a
		table.insert(made, a0)
		table.insert(made, a1)
		table.insert(made, beam)
		return beam
	end
	-- A flat 2D marker over every empty spot, drawn ON TOP of the whole screen: a pulsing ring and "PUT IT HERE". The 3D arrows can sit
	-- hidden inside the item (the Lava Lamp's bulb spot is inside its foot), so this one is what a lost player can always find. If the
	-- spot is off screen the marker sticks to the nearest edge.
	local function screenMarkers(game_)
		local gui = Instance.new("ScreenGui")
		gui.Name = "RestorationGuide"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 7
		gui.IgnoreGuiInset = true
		local markers: { [string]: { frame: Frame, ring: UIStroke, label: TextLabel, base: BasePart } } = {}
		for name, target in game_.targets do
			local base = basePartOf(target.socket)
			if base then
				local frame = Instance.new("Frame")
				frame.Name = "Spot_" .. name
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				frame.Size = UDim2.fromOffset(56, 56)
				frame.BackgroundTransparency = 1
				frame.Parent = gui
				local ring = Instance.new("Frame")
				ring.AnchorPoint = Vector2.new(0.5, 0.5)
				ring.Position = UDim2.fromScale(0.5, 0.5)
				ring.Size = UDim2.fromScale(1, 1)
				ring.BackgroundTransparency = 1
				ring.Parent = frame
				Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
				local stroke = Instance.new("UIStroke")
				stroke.Color = SELECT_COLOR
				stroke.Thickness = 4
				stroke.Parent = ring
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.fromScale(0.5, 0.5)
				dot.Size = UDim2.fromOffset(10, 10)
				dot.BackgroundColor3 = SELECT_COLOR
				dot.BorderSizePixel = 0
				dot.Parent = frame
				Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
				local label = Instance.new("TextLabel")
				label.AnchorPoint = Vector2.new(0.5, 1)
				label.Position = UDim2.new(0.5, 0, 0, -6)
				label.Size = UDim2.fromOffset(150, 24)
				label.BackgroundColor3 = Skin.COLORS.walnut
				label.TextColor3 = SELECT_COLOR
				label.FontFace = Skin.FONT_TITLE
				label.TextSize = 15
				label.Text = "PUT IT HERE"
				label.Parent = frame
				Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)
				local labelStroke = Instance.new("UIStroke")
				labelStroke.Color = Skin.COLORS.ink
				labelStroke.Thickness = 2
				labelStroke.Parent = label
				markers[name] = { frame = frame, ring = stroke, label = label, base = base }
			end
		end
		gui.Parent = player:WaitForChild("PlayerGui")
		table.insert(made, gui)
		table.insert(connections, RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera == nil then
				return
			end
			local view = camera.ViewportSize
			local t = os.clock()
			local pulse = math.sin(t * 5) * 0.5 + 0.5
			local selectedName = game_.selected and game_.selected.Name
			for name, m in markers do
				local filled = game_.targets[name].filled
				m.frame.Visible = not filled
				if not filled then
					local point, onScreen = camera:WorldToViewportPoint(m.base.Position)
					local x, y = point.X, point.Y
					if point.Z < 0 then
						x, y = view.X - x, view.Y - y -- behind the camera: flip so the marker points back toward it
					end
					x, y = math.clamp(x, 40, view.X - 40), math.clamp(y, 70, view.Y - 40)
					m.frame.Position = UDim2.fromOffset(x, y)
					local size = (if selectedName == name then 64 else 52) + 8 * pulse
					m.frame.Size = UDim2.fromOffset(size, size)
					m.ring.Transparency = 0.1 + 0.5 * (1 - pulse)
				end
			end
		end))
	end

	function fx.init(game_)
		local replacing = game_.stepType == "Replace"
		screenMarkers(game_)
		local guides: { [string]: any } = {}
		for name, target in game_.targets do
			local piece = game_.loose:FindFirstChild(name)
			guides[name] = {
				baseY = heightOf(target.socket) / 2 + 0.55,
				hide3d = false,
				socketGui = marker(target.socket, "GOES HERE", SELECT_COLOR),
				partGui = if piece then marker(piece, "PICK ME", Color3.fromRGB(63, 220, 200)) else nil,
				beam = if piece then guideBeam(piece, target.socket) else nil,
			}
		end
		-- A spot hidden INSIDE the item (the lamp's bulb) gets its 3D arrow floating above the item's top, far from the real spot: the flat ring
		-- (screenMarkers) points at the exact spot, so that arrow only confuses and is switched off.
		for _, g in guides do
			if g.socketGui and (g.socketGui:GetAttribute("BaseY") or g.baseY) > g.baseY + 0.05 then
				g.hide3d = true
			end
		end
		table.insert(connections, RunService.Heartbeat:Connect(function()
			local t = os.clock()
			local hintOn = not replacing or game_.wrongCount >= 1 or t - game_.lastAction > 8
			local selectedName = game_.selected and game_.selected.Name
			for name, g in guides do
				local filled = game_.targets[name].filled
				local bob = math.sin(t * 5) * 0.5 + 0.5
				if g.socketGui then
					g.socketGui.Enabled = not filled and not g.hide3d
					g.socketGui.StudsOffsetWorldSpace = Vector3.new(0, (g.socketGui:GetAttribute("BaseY") or g.baseY) + 0.12 * bob, 0)
					-- the spot of the part you are holding shouts louder
					g.socketGui.Arrow.TextTransparency = if selectedName == name then 0 else 0.15 + 0.3 * (1 - bob)
				end
				if g.partGui then
					g.partGui.Enabled = not filled and hintOn and selectedName ~= name
				end
				if g.beam then
					g.beam.Enabled = not filled and (hintOn or selectedName == name)
					g.beam.Transparency = NumberSequence.new(0.25 + 0.4 * (1 - bob))
				end
			end
		end))
	end

	function fx.select(part: Instance)
		playSound("pick")
		selected.Adornee = part
		selected.FillColor, selected.OutlineColor = SELECT_COLOR, SELECT_COLOR
		selected.Enabled = true
	end
	function fx.place(part: Instance, socket: Instance)
		task.delay(0.2, playSound, "snap")
		selected.Enabled = false
		if socket:IsA("BasePart") then
			socket.Transparency = 1 -- the ghost is filled now
			socket.CanQuery = false
		end
		if part:IsA("BasePart") then
			task.delay(0.25, function()
				if part.Parent then burst(part) end
			end)
		end
	end
	function fx.wrong(part: Instance, _socket: Instance)
		playSound("wrong")
		selected.Adornee = part
		selected.FillColor, selected.OutlineColor = WRONG_COLOR, WRONG_COLOR
		selected.Enabled = true
		task.delay(0.4, function()
			if selected.Parent and selected.FillColor == WRONG_COLOR then selected.Enabled = false end
		end)
	end
	return fx, function()
		for _, c in connections do
			c:Disconnect()
		end
		for _, instance in made do
			instance:Destroy()
		end
	end
end

-- ===== Model minigames: need ctx.model and ctx.attachPointer from the RestorationView =====
local function runWithModel(Game, withRepairFx: boolean?)
	return function(ctx)
		if ctx.model == nil or type(ctx.attachPointer) ~= "function" then
			log(`{ctx.step.type}: no item view yet, using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local fx, cleanupFx = nil, nil
		if withRepairFx then
			fx, cleanupFx = repairFx(ctx.model)
		end
		local ok, game_ = pcall(Game.new, ctx.model, ctx.step, function(fraction)
			ctx.setProgress(fraction)
		end, function(score)
			ctx.complete(score)
		end, fx)
		if not ok then
			if cleanupFx then cleanupFx() end
			warn(`[RestorationMoreMinigames] {ctx.step.type} could not start ({tostring(game_)}), using the placeholder`)
			return controller.RunPlaceholder(ctx)
		end
		local detach = ctx.attachPointer(game_)
		return function()
			if type(detach) == "function" then
				pcall(detach)
			end
			game_:Destroy()
			if cleanupFx then cleanupFx() end
		end
	end
end

function RestorationMoreMinigamesController.Init(others: { [string]: any })
	controller = others.RestorationController
	sounds = others.SoundController
end

function RestorationMoreMinigamesController.Start()
	if controller == nil or type(controller.RegisterMinigame) ~= "function" then
		warn("[RestorationMoreMinigames] RestorationController.RegisterMinigame not found: nothing registered")
		return
	end
	controller.RegisterMinigame("Test", runTest)
	controller.RegisterMinigame("Scrape", runWithModel(ScrapeGame))
	controller.RegisterMinigame("Reassemble", runWithModel(ReassembleGame, true))
	controller.RegisterMinigame("Replace", runWithModel(ReplaceGame, true))
	log("registered Test, Scrape, Reassemble, Replace")
end

return RestorationMoreMinigamesController
