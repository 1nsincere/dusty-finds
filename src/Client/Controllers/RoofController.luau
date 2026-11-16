-- RoofController.luau
-- Purpose: hides the roof and upper walls of the shop the local player is standing in (client only, nobody else sees it),
-- so the interior stays visible from the camera. Every other shop keeps its roof.
-- Owner: Dev 1 (Ace) wrote it for the environment pass; the art is Workspace.Plots.PlotN.Facade.{Roof,Upper} (docs/Environment_Art.md).
-- Depends on: Workspace.Plots.PlotN (PrimaryPart Floor, 40x40 studs), Facade.Roof and Facade.Upper folders of parts.
-- Uses LocalTransparencyModifier, so it never changes the real Transparency and nothing replicates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RoofController = {}
local DEBUG = true

local ENTER_HALF = 18.8 -- inside the walls (walls are at +-19.5): start hiding
local EXIT_HALF = 20.8 -- a little outside the doorway: start showing again
local MAX_HEIGHT = 12 -- above the walls = on the roof, not inside
local FADE_SECONDS = 0.3
local CHECK_EVERY = 0.1

type PlotState = { plot: Model, parts: { BasePart }, dirty: boolean, inside: boolean, alpha: number }
local states: { PlotState } = {}

local function collectParts(state: PlotState)
	local parts: { BasePart } = {}
	local facade = state.plot:FindFirstChild("Facade")
	if facade then
		for _, groupName in { "Roof", "Upper" } do
			local group = facade:FindFirstChild(groupName)
			if group then
				for _, descendant in group:GetDescendants() do
					if descendant:IsA("BasePart") then
						table.insert(parts, descendant)
					end
				end
			end
		end
	end
	state.parts = parts
	state.dirty = false
end

local function apply(state: PlotState)
	if state.dirty then
		collectParts(state)
	end
	for _, part in state.parts do
		part.LocalTransparencyModifier = state.alpha
	end
end

local function track(plot: Instance)
	if not plot:IsA("Model") or states[plot :: any] then
		return
	end
	local state: PlotState = { plot = plot, parts = {}, dirty = true, inside = false, alpha = 0 }
	table.insert(states, state)
	-- the art can be rebuilt in Studio while testing: rescan when anything is added or removed under Facade
	plot.DescendantAdded:Connect(function()
		state.dirty = true
	end)
	plot.DescendantRemoving:Connect(function()
		state.dirty = true
	end)
end

function RoofController.Init(_others)
	if DEBUG then
		print("[RoofController] Init")
	end
end

function RoofController.Start()
	local plots = workspace:WaitForChild("Plots", 10)
	if plots == nil then
		warn("[RoofController] no Workspace.Plots: roofs stay visible")
		return
	end
	for _, plot in plots:GetChildren() do
		track(plot)
	end
	plots.ChildAdded:Connect(track)

	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			for _, state in states do
				local floor = state.plot:FindFirstChild("Floor")
				local inside = false
				if root and floor and floor:IsA("BasePart") then
					local p = floor.CFrame:PointToObjectSpace(root.Position)
					-- shops can be scaled (a 56 stud shop is 1.4x): the limits were written for the original 40 stud floor
					local k = floor.Size.X / 40
					local limit = (if state.inside then EXIT_HALF else ENTER_HALF) * k
					inside = math.abs(p.X) < limit and math.abs(p.Z) < limit and p.Y < MAX_HEIGHT * k
				end
				state.inside = inside
			end
		end
		-- fade only the shops that are changing (cheap: at most the shop you are entering or leaving)
		local step = dt / FADE_SECONDS
		for _, state in states do
			local target = if state.inside then 1 else 0
			if state.alpha ~= target or state.dirty then
				if state.alpha < target then
					state.alpha = math.min(target, state.alpha + step)
				elseif state.alpha > target then
					state.alpha = math.max(target, state.alpha - step)
				end
				apply(state)
			end
		end
	end)
	if DEBUG then
		print(`[RoofController] Start: {#states} plots tracked`)
	end
end

return RoofController
