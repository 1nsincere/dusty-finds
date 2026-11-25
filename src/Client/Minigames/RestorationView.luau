-- RestorationView.luau
-- Purpose: a disposable local item and bench camera for Wipe/Polish, reconstructed from saved recipe progress.
-- Owner: Dev 2 (Dwayne). Depends on: committed ctx.bench, Config.Items, ClientState and the installed item asset.
-- Never changes the asset, bench or environment. Destroy releases only resources acquired by this view.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ClientState = require(script.Parent.Parent.ClientState)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local PointerInput = require(script.Parent.PointerInput)
local ToolRig = require(script.Parent.ToolRig) -- the tool in the player's view: cloth, scraper, buffing pad (visual only)

local RestorationView = {}
RestorationView.__index = RestorationView
local nextViewId = 0
-- First-person bench camera (studs, before plot scale): how far in front of the item the eyes are, how high above it,
-- and the field of view.
local FP_DISTANCE = 3.4
local FP_HEIGHT = 3.2
local FP_FOV = 62

-- ===== Camera that fits the item (Ace + Claude, 2026-11-25) =====
-- The eye camera used to sit at one fixed distance, so tall items (Lava Lamp) overflowed the screen and had their dirt cut off.
-- Now the distance comes from the item's real visible size at the current step (loose parts on the tray count too), so every
-- item fills the same share of the screen. The eyes stay on the player's side of the bench, looking down at FIT_PITCH degrees.
local FIT_PITCH = 38 -- degrees looking down at the item
local FIT_MARGIN = 1.05 -- 1 = item just touches the safe area; a little air round it
local SAFE_HEIGHT = 0.64 -- share of the screen height the item may use (the first guess)
-- the working area in screen-centred units (-1..1): the hint and chips take the top, the progress bar the bottom
local SAFE_X, SAFE_UP, SAFE_DOWN = 0.92, 0.88, 0.45 -- (2026-11-25: the HUD is a column on the LEFT now, so the top is free; the Test card takes the bottom)

-- Centre and bounding-sphere radius of everything visible on the model (helper carriers like Base/hidden spots don't count).
function RestorationView.VisualBounds(model: Model): (Vector3, number)
	local lo, hi
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Base" and p.Transparency < 0.95 then
			local half = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
						lo = if lo then Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) else c
						hi = if hi then Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) else c
					end
				end
			end
		end
	end
	if lo == nil or hi == nil then
		local cf, size = model:GetBoundingBox()
		return cf.Position, size.Magnitude / 2
	end
	return (lo + hi) / 2, (hi - lo).Magnitude / 2
end

-- flat = horizontal unit vector from the item toward the player's side of the bench.
-- leftReserve (0..1, share of the screen width): the HUD column on the left. The item is fitted into, and centred in, the rest.
-- eyePos (optional): where the player's EYES would be at the bench. The camera starts there (the true first-person view) and is only
-- pulled back along the same line when the item would not fit the screen from there (a tall Lava Lamp), never pushed in.
function RestorationView.FitCamera(model: Model, flat: Vector3, fov: number, aspect: number, leftReserve: number?, eyePos: Vector3?): CFrame
	local center, radius = RestorationView.VisualBounds(model)
	local tanV = math.tan(math.rad(fov) / 2)
	local tanH = tanV * math.max(aspect, 0.3)
	-- every corner of every visible part (the tray with the loose parts counts)
	local corners: { Vector3 } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Base" and p.Transparency < 0.95 then
			local half = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(corners, (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
					end
				end
			end
		end
	end
	-- the free part of the screen in -1..1 units: from the HUD column to just inside the right edge
	local xMin = -1 + 2 * (leftReserve or 0)
	local xMax = 0.96
	local halfWidth = math.min(SAFE_X, (xMax - xMin) / 2)
	local midX = (xMax + xMin) / 2
	local pitch = math.rad(FIT_PITCH)
	local direction = flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
	local distance = (radius * 0.84) / (tanV * SAFE_HEIGHT) * FIT_MARGIN -- a first guess from the size
	-- never pull back through a wall: the first solid thing between the item and the eye line limits the distance
	local maxDistance = math.huge
	if eyePos and (eyePos - center).Magnitude > 0.5 then
		direction = (eyePos - center).Unit -- look at the item from where the player's eyes are
		distance = (eyePos - center).Magnitude
		local ignore: { Instance } = { model }
		local character = Players.LocalPlayer.Character
		if character then
			table.insert(ignore, character)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		for _ = 1, 8 do
			params.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(center, direction * 400, params)
			if hit == nil then
				break
			end
			local part = hit.Instance
			-- only real walls / furniture count: not glass, light fittings or small props
			if part.Transparency < 0.5 and math.max(part.Size.X, part.Size.Y, part.Size.Z) > 3 then
				maxDistance = math.max((hit.Position - center).Magnitude - 0.8, 2)
				break
			end
			table.insert(ignore, part)
		end
		distance = math.min(distance, maxDistance)
	end
	local look = CFrame.lookAt(center + direction * distance, center)
	-- Then pull back until EVERY corner is inside the part of the screen the player can really work in (the hint and chips
	-- take the top, the progress bar the bottom). A tall item with parts on a tray (the Plush Bunny's ears) is not round, so a
	-- bounding sphere left the tray under the progress bar and its parts could not be tapped.
	for _ = 1, 6 do
		look = CFrame.lookAt(center + direction * distance, center)
		-- slide the camera left so the item sits in the middle of the free area (right of the HUD column)
		look = look * CFrame.new(-midX * tanH * distance, 0, 0)
		local worst = 0
		for _, c in corners do
			local v = look:PointToObjectSpace(c)
			if v.Z >= -0.05 then
				worst = math.max(worst, 4)
			else
				local nx, ny = v.X / -v.Z / tanH, v.Y / -v.Z / tanV
				worst = math.max(worst, math.abs(nx - midX) / halfWidth, if ny > 0 then ny / SAFE_UP else -ny / SAFE_DOWN)
			end
		end
		if worst <= 1 then
			break
		end
		distance = math.min(distance * math.min(worst * 1.02, 2), maxDistance)
	end
	return look
end

-- ===== Step state (Ace, 2026-11-20) =====
-- The item must show everything already done in earlier steps (wiped dirt, scraped rust, parts back in their sockets,
-- polish shine) and only the helpers the CURRENT step needs (ghost sockets / decoy parts only during a repair step).
-- Idempotent: safe to run on a fresh model (resume) and on the same model between steps.
local function stepParts(step): { string }?
	return if type(step.parts) == "table" then step.parts else nil
end

local function matchesParts(name: string, parts: { string }?): boolean
	if parts == nil then
		return true
	end
	for _, prefix in parts do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function setPivot(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

local function pivotOf(inst: Instance): CFrame
	return if inst:IsA("Model") then inst:GetPivot() else (inst :: BasePart).CFrame
end

local function setQueryVisible(inst: Instance, visible: boolean, transparency: number?)
	local parts = if inst:IsA("BasePart") then { inst } else inst:GetDescendants()
	for _, p in parts do
		if p:IsA("BasePart") then
			if p:GetAttribute("BaseTransparency") == nil then
				p:SetAttribute("BaseTransparency", p.Transparency)
			end
			p.Transparency = if visible then (transparency or p:GetAttribute("BaseTransparency")) else 1
			p.CanQuery = visible
		end
	end
end

function RestorationView.ApplyStepState(model: Model, recipe: { any }, stepIndex: number)
	local sockets = model:FindFirstChild("Sockets")
	local loose = model:FindFirstChild("LooseParts")
	local filled: { [string]: boolean } = {}
	for i = 1, stepIndex - 1 do -- finished steps: show their result
		local step = recipe[i]
		local kind = step and step.type
		if kind == "Wipe" or kind == "Scrape" then
			local folder = model:FindFirstChild(if kind == "Wipe" then "DirtSpots" else "RustSpots")
			if folder then
				for _, d in folder:GetDescendants() do
					if d:IsA("Decal") then d.Transparency = 1 end
					if d:IsA("BasePart") then d.CanQuery = false end
				end
			end
		elseif kind == "Polish" then
			local folder = model:FindFirstChild("PolishSurfaces")
			if folder then
				for _, p in folder:GetChildren() do
					if p:IsA("BasePart") then p.Reflectance = math.max(p.Reflectance, 0.3) end
				end
			end
		elseif (kind == "Reassemble" or kind == "Replace") and sockets and loose then
			for _, socket in sockets:GetChildren() do
				local piece = loose:FindFirstChild(socket.Name)
				if piece and matchesParts(socket.Name, stepParts(step)) then
					setPivot(piece, pivotOf(socket))
					filled[socket.Name] = true
				end
			end
		end
	end
	-- helpers: ghosts and decoys only for the current repair step; fitted parts stay solid and unclickable
	local current = recipe[stepIndex]
	local repairing = current and (current.type == "Reassemble" or current.type == "Replace")
	-- While repairing, the item's own body must not catch the pointer: a socket often sits INSIDE the body (the Lava Lamp's bulb is
	-- inside its glass and foot), so every tap hit the glass first and the part could never be placed (found in a real session,
	-- 2026-11-25). Other steps get the body's original CanQuery back (Wipe/Scrape spots and Polish surfaces need it).
	local KEEP = { Sockets = true, LooseParts = true, DirtSpots = true, RustSpots = true }
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local helper, node = false, p.Parent
			while node and node ~= model do
				if KEEP[node.Name] then
					helper = true
					break
				end
				node = node.Parent
			end
			if not helper then
				if p:GetAttribute("BaseCanQuery") == nil then
					p:SetAttribute("BaseCanQuery", p.CanQuery)
				end
				p.CanQuery = if repairing then false else (p:GetAttribute("BaseCanQuery") :: boolean)
			end
		end
	end
	if sockets then
		for _, socket in sockets:GetChildren() do
			local active = repairing and not filled[socket.Name] and matchesParts(socket.Name, stepParts(current))
			setQueryVisible(socket, active, 0.65)
		end
	end
	if loose then
		for _, piece in loose:GetChildren() do
			local hasSocket = sockets ~= nil and sockets:FindFirstChild(piece.Name) ~= nil
			if filled[piece.Name] then
				setQueryVisible(piece, true)
				for _, p in (if piece:IsA("BasePart") then { piece } else piece:GetDescendants()) do
					if p:IsA("BasePart") then p.CanQuery = false end -- placed: part of the item now
				end
			elseif not hasSocket then
				setQueryVisible(piece, current ~= nil and current.type == "Replace") -- decoys only while replacing
			else
				setQueryVisible(piece, true) -- the broken-off part waits on the tray
			end
		end
	end
end

-- SetViewProvider contract: plain functions, because the runner and Ace's adapters call them without a receiver.
-- ===== Focus mode while restoring (Ace, 2026-11-25) =====
-- Hides the whole HUD (every screen except the Restoration one) and switches the movement controls off, which also removes the
-- touch thumbstick and jump button on phones / tablets / iPads, so nothing sits on top of the item and nothing can walk you away.
-- Screens that switch themselves back on (a controller, a toast) or appear meanwhile are put away again. Returns the undo function.
-- Every restoring screen (Restoration, RestorationTest, RestorationWork... each minigame makes its own) stays: only the HUD goes.
local KEEP_SCREENS = { MainMenu = true, LoadingScreen = true }
local function keepScreen(screen: Instance): boolean
	return KEEP_SCREENS[screen.Name] == true or string.sub(screen.Name, 1, 11) == "Restoration"
end

local function enterFocusMode(): () -> ()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 1)
	local hiddenByUs: { [ScreenGui]: boolean } = {}
	local connections: { RBXScriptConnection } = {}
	local active = true
	local function hide(screen: Instance)
		if not screen:IsA("ScreenGui") or keepScreen(screen) then
			return
		end
		if screen.Enabled then
			hiddenByUs[screen] = true
			screen.Enabled = false
		end
		table.insert(connections, screen:GetPropertyChangedSignal("Enabled"):Connect(function()
			if active and screen.Enabled then
				hiddenByUs[screen] = true
				screen.Enabled = false
			end
		end))
	end
	for _, screen in playerGui:GetChildren() do
		hide(screen)
	end
	table.insert(connections, playerGui.ChildAdded:Connect(function(screen)
		task.defer(hide, screen)
	end))
	-- movement controls (the touch thumbstick and jump button live in the PlayerModule's controls)
	-- NEVER wait here: WaitForChild("PlayerModule", 5) froze the start of every restoration for 5 seconds whenever the module is not
	-- there (Studio test servers), which was the "wait before I can restore". Take it if it exists, otherwise carry on without.
	local controls
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if module then
		pcall(function()
			controls = require(module):GetControls()
		end)
	end
	if controls then
		controls:Disable()
	end
	return function()
		active = false
		for _, c in connections do
			c:Disconnect()
		end
		for screen in hiddenByUs do
			if screen.Parent then
				screen.Enabled = true
			end
		end
		if controls then
			controls:Enable()
		end
	end
end

function RestorationView.Provider(ctx, onCancel)
	local view = RestorationView.new(ctx, onCancel)
	local disposed = false
	local detachCurrent
	local function attachPointer(minigame)
		assert(not disposed, "Cannot attach input to a disposed restoration view")
		if detachCurrent then detachCurrent() end
		-- the tool hears the same presses as the minigame (so the cloth rubs while you hold), without changing the minigame
		local tool = view.tool
		local proxy = minigame
		if tool then
			proxy = {
				OnPointerDown = function(_, hit) tool:Press(); return minigame:OnPointerDown(hit) end,
				OnDrag = function(_, hit, delta, dt) return minigame:OnDrag(hit, delta, dt) end,
				OnPointerUp = function(_) tool:Release(); return minigame:OnPointerUp() end,
			}
		end
		local pointer = PointerInput.new(view.model, proxy, RestorationView.IsPointerBlocked)
		local detached = false
		local function detach()
			if detached then return end
			detached = true
			if tool then tool:Release() end
			pointer:Destroy()
		end
		detachCurrent = detach
		return detach
	end
	return {
		model = view.model,
		tool = view.tool, -- exposed for dev tests
		attachPointer = attachPointer,
		-- the runner keeps ONE view for the whole session and calls this before each next step
		prepare = function(nextCtx)
			if disposed then return end
			if detachCurrent then detachCurrent() end
			local item = ClientState.Get("inventory." .. nextCtx.uid)
			local def = item and Items[item.itemId]
			if def then
				RestorationView.ApplyStepState(view.model, def.recipe, nextCtx.stepIndex)
				if view.refit then
					view.refit() -- the visible parts changed: frame the item again
				end
				if view.tool and nextCtx.step then
					view.tool:SetStep(nextCtx.step.type) -- the right tool for the next step
				end
			end
		end,
		cleanup = function()
			if disposed then return end
			disposed = true
			if detachCurrent then detachCurrent() end
			view:Destroy()
		end,
	}
end

function RestorationView.new(ctx, onCancel)
	local bench = ctx.bench
	assert(typeof(bench) == "Instance" and bench:IsDescendantOf(workspace), "The session's bench is unavailable; start again near your bench")
	local anchor = bench:FindFirstChild("ItemAnchor")
	local point = bench:FindFirstChild("CameraPoint")
	assert(anchor and anchor:IsA("BasePart") and point and point:IsA("BasePart"), "Bench needs ItemAnchor and CameraPoint Parts")
	local item = ClientState.Get("inventory." .. ctx.uid)
	local def = item and Items[item.itemId]
	assert(def, "The restoration item is unavailable")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	local source = items and items:FindFirstChild(def.model)
	assert(source and source:IsA("Model"), `Missing item model Assets.Items.{def.model}`)
	assert(source.PrimaryPart and source.PrimaryPart.Name == "Base", "Item model needs Base as PrimaryPart")
	for _, part in source:GetDescendants() do
		assert(not part:IsA("LuaSourceContainer"), "Item assets must contain no scripts")
		if part:IsA("BasePart") then
			assert(part.Anchored, `Item part {part.Name} must be anchored`)
		end
	end
	local camera = workspace.CurrentCamera
	assert(camera, "No active camera")
	local self = setmetatable({ destroyed = false, connections = {}, model = nil }, RestorationView)
	-- Keep construction transactional: the runner cannot clean a function that failed before returning cleanup.
	local ok, err = pcall(function()
		self.model = source:Clone()
		assert(self.model, "Item model must be Archivable")
		self.model.Name = "RestorationItemLocal"
		for _, part in self.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanTouch = false
			end
		end
		-- Resume at any step: rebuild everything earlier steps already did (and hide helpers this step doesn't use).
		RestorationView.ApplyStepState(self.model, def.recipe, ctx.stepIndex)
		-- A scaled shop (e.g. 1.4x, a 56 stud floor) has a bigger bench and a farther CameraPoint: scale the item by the same factor
		-- so it looks the same on screen as in an unscaled shop. Plot scale = floor width / 40 (the original shop).
		local plotFloor
		do
			local node: Instance? = bench
			while node and not plotFloor do
				plotFloor = node:FindFirstChild("Floor")
				node = node.Parent
			end
		end
		local plotScale = if plotFloor and plotFloor:IsA("BasePart") then plotFloor.Size.X / 40 else 1
		if math.abs(plotScale - 1) > 0.001 then
			self.model:ScaleTo(plotScale)
		end
		-- ItemAnchor is the resting surface; Base's bottom sits on it, using the plot's actual rotation.
		self.model:PivotTo(anchor.CFrame * CFrame.new(0, anchor.Size.Y / 2 + self.model.PrimaryPart.Size.Y / 2, 0))
		self.model.Parent = workspace
		self.camera = camera
		self.savedCamera = { kind = camera.CameraType, subject = camera.CameraSubject, cframe = camera.CFrame, focus = camera.Focus, fov = camera.FieldOfView }
		self.savedMouse = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		nextViewId += 1
		self.binding = "RestorationView" .. nextViewId
		ContextActionService:BindActionAtPriority(self.binding, function() return Enum.ContextActionResult.Sink end, false, 3000, table.unpack(Enum.PlayerActions:GetEnumItems()))
		-- First-person view (Ace, 2026-11-20): the camera sits where the player's eyes are when standing at the bench (on the
		-- CameraPoint side, closer and lower), looking down at the item; the player's own character is hidden meanwhile.
		local toPoint = point.Position - anchor.Position
		local flatDir = Vector3.new(toPoint.X, 0, toPoint.Z)
		flatDir = if flatDir.Magnitude > 0.01 then flatDir.Unit else anchor.CFrame.LookVector
		local fitted: CFrame? = nil
		local fittedAspect = 0
		function self.refit() -- after a step change (loose parts appear / disappear) or a window resize
			fitted = nil
		end
		local function firstPersonCFrame(): CFrame
			local vs = camera.ViewportSize
			local aspect = if vs.Y > 0 then vs.X / vs.Y else 1.78
			if fitted == nil or math.abs(aspect - fittedAspect) > 0.01 then
				-- the HUD column (Exit, tracker, guide) is about 280 px wide at 720 px high: keep the item out from under it
				local hudScale = math.clamp(vs.Y / 720, 0.62, 1.1)
				fitted = RestorationView.FitCamera(self.model, flatDir, FP_FOV, aspect, math.clamp(282 * hudScale / math.max(vs.X, 1), 0, 0.4),
					point.Position) -- the CameraPoint part at the bench IS where the eyes go: it is placed inside the shop, clear of walls
				fittedAspect = aspect
			end
			return fitted :: CFrame
		end
		self.hidden = {}
		local character = Players.LocalPlayer.Character
		if character then
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") or part:IsA("Decal") then
					self.hidden[part] = part.LocalTransparencyModifier
					part.LocalTransparencyModifier = 1
				end
			end
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FP_FOV
		camera.CFrame = firstPersonCFrame()
		camera.Focus = CFrame.new(anchor.Position)
		RunService:BindToRenderStep(self.binding, Enum.RenderPriority.Camera.Value + 1, function()
			if not self.destroyed and camera == workspace.CurrentCamera and point:IsDescendantOf(workspace) then
				camera.CFrame = firstPersonCFrame()
				camera.Focus = CFrame.new(anchor.Position)
				for part in self.hidden do -- Roblox resets this on some parts while zooming; keep the body hidden
					if part.Parent then part.LocalTransparencyModifier = 1 end
				end
			end
		end)
		-- hide the HUD and the thumbstick while restoring (undone in Destroy)
		local focusOk, undoFocus = pcall(enterFocusMode)
		if focusOk then
			self.undoFocus = undoFocus
		else
			warn("[RestorationView] focus mode failed (restoring continues with the HUD): " .. tostring(undoFocus))
		end
		-- the tool you work with (visual only): a failure here must never stop the restoration
		local toolOk, tool = pcall(ToolRig.new, { model = self.model, stepType = ctx.step and ctx.step.type })
		if toolOk then
			self.tool = tool
		else
			warn("[RestorationView] tool rig failed (restoring continues without it): " .. tostring(tool))
		end
		local function cancel()
			if not self.destroyed then onCancel() end
		end
		table.insert(self.connections, Players.LocalPlayer.CharacterRemoving:Connect(cancel))
		table.insert(self.connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(cancel))
		table.insert(self.connections, bench.AncestryChanged:Connect(function()
			if not bench:IsDescendantOf(workspace) then cancel() end
		end))
	end)
	if not ok then
		self:Destroy()
		error(err, 0)
	end
	return self
end

function RestorationView.IsPointerBlocked(position)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return true end
	local inset = GuiService:GetGuiInset()
	-- Test actual visible rectangles, not a full-screen transparent Restoration ScreenGui.
	for _, object in playerGui:GetDescendants() do
		if object:IsA("GuiObject") and (object:IsA("GuiButton") or object:IsA("TextBox")
			or object.Name == "Hint" or object.Name == "StepChips" or object.Name == "Progress"
			or object.Name == "Window" or object.Name == "FinishCard" or object.Name == "Banner") then
			local ancestor, visible, screen = object, true, nil
			while ancestor and ancestor ~= playerGui do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then visible = false; break end
				if ancestor:IsA("ScreenGui") then screen = ancestor; visible = ancestor.Enabled; break end
				ancestor = ancestor.Parent
			end
			if visible and screen then
				local p = if screen.IgnoreGuiInset then position + inset else position
				local origin, size = object.AbsolutePosition, object.AbsoluteSize
				if p.X >= origin.X and p.Y >= origin.Y and p.X <= origin.X + size.X and p.Y <= origin.Y + size.Y then return true end
			end
		end
	end
	return false
end

function RestorationView:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in self.connections do connection:Disconnect() end
	if self.binding then
		RunService:UnbindFromRenderStep(self.binding)
		ContextActionService:UnbindAction(self.binding)
	end
	if self.tool then self.tool:Destroy() end
	if self.undoFocus then self.undoFocus() end -- the HUD and the controls come back
	if self.model then self.model:Destroy() end
	for part, value in self.hidden or {} do
		if part.Parent then part.LocalTransparencyModifier = value end
	end
	local camera, saved = self.camera, self.savedCamera
	if saved and camera.Parent and workspace.CurrentCamera == camera then
		local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		camera.CameraSubject = if saved.subject and saved.subject.Parent then saved.subject else humanoid
		camera.CFrame, camera.Focus, camera.FieldOfView = saved.cframe, saved.focus, saved.fov
		camera.CameraType = saved.kind
	end
	if self.savedMouse then UserInputService.MouseBehavior = self.savedMouse end
end

return RestorationView
