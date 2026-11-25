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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config:WaitForChild("Items"))
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

-- ===== Test: a bar with a green zone and a sweeping needle; tap to stop =====
local function runTest(ctx)
	local step = table.clone(ctx.step)
	step.rarity = rarityOf(ctx.uid)
	local finished = false
	local game_
	game_ = TestGame.new(nil, step, function(fraction)
		ctx.setProgress(fraction)
	end, function(score)
		finished = true
		ctx.complete(score)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RestorationTest"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.IgnoreGuiInset = true
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.66)
	label.Size = UDim2.fromScale(0.6, 0.07)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("1F2D3A")
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = TEST_LABELS[step.style] or "Does it work?"
	label.Parent = gui
	local bar = frame(gui, "Bar", UDim2.fromScale(0.5, 0.74), UDim2.fromScale(0.6, 0.06), Color3.fromHex("E0524D"))
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)
	local z = game_.zone
	local yellow = frame(bar, "Yellow", UDim2.fromScale(z.yellowFrom, 0), UDim2.fromScale(z.yellowTo - z.yellowFrom, 1), Color3.fromHex("FFD43B"))
	local green = frame(bar, "Green", UDim2.fromScale(z.greenFrom, 0), UDim2.fromScale(z.greenTo - z.greenFrom, 1), Color3.fromHex("3DBE6B"))
	local needle = frame(bar, "Needle", UDim2.fromScale(0, -0.4), UDim2.new(0, 6, 1.8, 0), Color3.fromHex("1F2D3A"))
	needle.AnchorPoint = Vector2.new(0.5, 0)
	local button = Instance.new("TextButton")
	button.Name = "TapButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.fromScale(0.5, 0.79)
	button.Size = UDim2.fromScale(0.3, 0.12)
	button.BackgroundColor3 = Color3.fromHex("F2784B")
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Font = Enum.Font.FredokaOne
	button.Text = "TAP!"
	button.AutoButtonColor = true
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.3, 0)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(180, 64)
	limit.MaxSize = Vector2.new(380, 110)
	limit.Parent = button
	gui.Parent = player:WaitForChild("PlayerGui")
	_ = yellow
	_ = green

	local tapped = button.Activated:Connect(function()
		local result = game_:OnPointerDown(nil)
		if result == "red" then
			label.Text = "Missed! Try again"
		elseif result == "yellow" then
			label.Text = "Good!"
		elseif result == "green" then
			label.Text = "Perfect!"
		end
	end)
	local beat = RunService.Heartbeat:Connect(function(dt)
		game_:Update(dt)
		needle.Position = UDim2.fromScale(game_.needle, -0.4)
		if finished then
			button.Active = false
		end
	end)
	return function()
		tapped:Disconnect()
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
	function fx.init(game_)
		local replacing = game_.stepType == "Replace"
		local guides: { [string]: any } = {}
		for name, target in game_.targets do
			local piece = game_.loose:FindFirstChild(name)
			guides[name] = {
				baseY = heightOf(target.socket) / 2 + 0.55,
				socketGui = marker(target.socket, "GOES HERE", SELECT_COLOR),
				partGui = if piece then marker(piece, "PICK ME", Color3.fromRGB(63, 220, 200)) else nil,
				beam = if piece then guideBeam(piece, target.socket) else nil,
			}
		end
		table.insert(connections, RunService.Heartbeat:Connect(function()
			local t = os.clock()
			local hintOn = not replacing or game_.wrongCount >= 1 or t - game_.lastAction > 8
			local selectedName = game_.selected and game_.selected.Name
			for name, g in guides do
				local filled = game_.targets[name].filled
				local bob = math.sin(t * 5) * 0.5 + 0.5
				if g.socketGui then
					g.socketGui.Enabled = not filled
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
