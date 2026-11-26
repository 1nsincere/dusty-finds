-- CameraWallController.luau (StarterPlayerScripts.Client.Controllers.CameraWallController)
-- Purpose: the third-person camera must not slip through the shop walls. The visible walls are meshes that never collide, and the
-- solid walls are invisible (Transparency 1), and Roblox's camera only bumps into parts that are solid AND not transparent. So the
-- camera used to pass through, and you saw outside (or the Back Room that is not unlocked yet). This controller pushes the camera in
-- front of any part tagged "ShellCamBlock" that lies between the player and the camera.
-- Owner: Dev 1 (Ace). Depends on: CollectionService tag ShellCamBlock (set in Studio on the plots' Walls, Facade.Collision, BackCapBlock
-- and on the Expansions templates' invisible walls). Parts with CanCollide false (an opened wall) are ignored.
-- Client only: nothing is replicated.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraWallController = {}
local DEBUG = true

local TAG = "ShellCamBlock"
local HEAD_HEIGHT = 1.5 -- the ray starts at the player's head
local WALL_GAP = 0.6 -- the camera stops this far in front of the wall (studs)

local player = Players.LocalPlayer
local blockers: { Instance } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.RespectCanCollide = true

local function refresh()
	blockers = CollectionService:GetTagged(TAG)
	params.FilterDescendantsInstances = blockers
end

local function step()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera == nil or root == nil or #blockers == 0 then
		return
	end
	local focus = root.Position + Vector3.new(0, HEAD_HEIGHT, 0)
	local camPos = camera.CFrame.Position
	local offset = camPos - focus
	if offset.Magnitude < 1 then
		return
	end
	local hit = workspace:Raycast(focus, offset, params)
	if hit then
		local newPos = hit.Position - offset.Unit * WALL_GAP
		camera.CFrame = CFrame.new(newPos) * (camera.CFrame - camera.CFrame.Position)
	end
end

function CameraWallController.Init(_others)
	if DEBUG then
		print("[CameraWallController] Init")
	end
end

function CameraWallController.Start()
	refresh()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
	-- right after the default camera has moved (priority Camera), before the frame is drawn
	RunService:BindToRenderStep("CameraWallGuard", Enum.RenderPriority.Camera.Value + 1, step)
	if DEBUG then
		print(`[CameraWallController] Start: {#blockers} wall parts keep the camera inside`)
	end
end

return CameraWallController
