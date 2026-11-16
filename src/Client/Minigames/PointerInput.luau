-- PointerInput.luau
-- Purpose: shared single-pointer input for production Wipe/Polish, adapted from the tested isolated adapter.
-- Owner: Dev 2 (Dwayne). Depends on: disposable model, minigame and UI exclusion predicate.
-- Menu/focus interruptions require a fresh press; Destroy disconnects every input callback.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PointerInput = {}
PointerInput.__index = PointerInput
local DEBUG = true

function PointerInput.new(model, minigame, isBlocked)
	local self = setmetatable({}, PointerInput)
	self.connections = {}
	self.destroyed = false
	self.pointer = nil
	self.position = Vector2.zero
	self.previous = nil
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Include
	self.params.FilterDescendantsInstances = { model }
	self.params.RespectCanCollide = false

	local function release()
		if self.pointer ~= nil then
			self.pointer = nil
			self.previous = nil
			minigame:OnPointerUp()
		end
	end
	self.release = release

	local function blocked(position)
		return GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil or isBlocked(position)
	end

	local function mousePosition()
		local inset = GuiService:GetGuiInset()
		return UserInputService:GetMouseLocation() - inset
	end

	local function hitAt(position)
		local camera = workspace.CurrentCamera
		if not camera or blocked(position) then
			return nil
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		return workspace:Raycast(ray.Origin, ray.Direction * 500, self.params)
	end

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or self.pointer or self.destroyed then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local position = if kind == Enum.UserInputType.Touch
			then Vector2.new(input.Position.X, input.Position.Y) else mousePosition()
		if blocked(position) then
			return
		end
		self.pointer = input
		self.position = position
		self.previous = position
		minigame:OnPointerDown(hitAt(position))
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if input == self.pointer and input.UserInputType == Enum.UserInputType.Touch then
			self.position = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if input == self.pointer or (self.pointer
			and self.pointer.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1) then
			release()
		end
	end))
	table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(release))
	table.insert(self.connections, GuiService.MenuOpened:Connect(release))
	table.insert(self.connections, Players.LocalPlayer.CharacterRemoving:Connect(release))
	table.insert(self.connections, RunService.RenderStepped:Connect(function(dt)
		local pointer = self.pointer
		if self.destroyed or not pointer then
			return
		end
		if pointer.UserInputState == Enum.UserInputState.Cancel
			or pointer.UserInputState == Enum.UserInputState.End then
			release()
			return
		end
		if pointer.UserInputType == Enum.UserInputType.MouseButton1 then
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				release()
				return
			end
			self.position = mousePosition()
		end
		local delta = self.position - (self.previous or self.position)
		self.previous = self.position
		-- Clamp stalls so returning to a frozen window cannot instantly clear a spot.
		minigame:OnDrag(hitAt(self.position), delta, math.min(dt, 0.1))
	end))
	if DEBUG then
		print("[PointerInput] attached")
	end
	return self
end

function PointerInput:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.release()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if DEBUG then
		print("[PointerInput] detached")
	end
end

return PointerInput
