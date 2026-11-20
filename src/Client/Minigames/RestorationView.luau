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

local RestorationView = {}
RestorationView.__index = RestorationView
local nextViewId = 0
-- First-person bench camera (studs, before plot scale): how far in front of the item the eyes are, how high above it,
-- and the field of view.
local FP_DISTANCE = 3.4
local FP_HEIGHT = 3.2
local FP_FOV = 62

-- SetViewProvider contract: plain functions, because the runner and Ace's adapters call them without a receiver.
function RestorationView.Provider(ctx, onCancel)
	local view = RestorationView.new(ctx, onCancel)
	local disposed = false
	local detachCurrent
	local function attachPointer(minigame)
		assert(not disposed, "Cannot attach input to a disposed restoration view")
		if detachCurrent then detachCurrent() end
		local pointer = PointerInput.new(view.model, minigame, RestorationView.IsPointerBlocked)
		local detached = false
		local function detach()
			if detached then return end
			detached = true
			pointer:Destroy()
		end
		detachCurrent = detach
		return detach
	end
	return {
		model = view.model,
		attachPointer = attachPointer,
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
		-- Every view is fresh, including resume directly at Polish. Cleared invisible targets must not occlude it.
		local completedWipe = false
		for i = 1, ctx.stepIndex - 1 do
			if def.recipe[i].type == "Wipe" then completedWipe = true end
		end
		if completedWipe then
			local dirt = self.model:FindFirstChild("DirtSpots")
			if dirt then
				for _, part in dirt:GetDescendants() do
					if part:IsA("Decal") then part.Transparency = 1 end
					if part:IsA("BasePart") then part.CanQuery = false end
				end
			end
		end
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
		local function firstPersonCFrame(): CFrame
			local toPoint = point.Position - anchor.Position
			local flat = Vector3.new(toPoint.X, 0, toPoint.Z)
			flat = if flat.Magnitude > 0.01 then flat.Unit else anchor.CFrame.LookVector
			local itemCentre = anchor.Position + Vector3.new(0, anchor.Size.Y / 2 + 0.9 * plotScale, 0)
			local eye = anchor.Position + flat * FP_DISTANCE * plotScale + Vector3.new(0, FP_HEIGHT * plotScale, 0)
			return CFrame.lookAt(eye, itemCentre)
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
