-- Socket.luau (StarterPlayerScripts.Client.Minigames.Socket)
-- Purpose: the shared logic of Reassemble and Replace (docs/01 C3): tap a loose part, then tap its socket; it snaps in.
-- A wrong socket (or a decoy part) costs 10 points (never below 50) and the part goes back to the tray.
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: model.LooseParts and model.Sockets (docs/Item_Model_Contract_DRAFT.md):
-- a loose part and its socket share a name (LooseParts/Wheel1 <-> Sockets/Wheel1). LooseParts without a matching socket are DECOYS.
-- Same interface as every minigame: Socket.new(model, stepConfig, onProgress, onComplete, fx?), :OnPointerDown(hit), :OnDrag(), :OnPointerUp(), :Destroy().
-- No physics: parts are anchored and placed by CFrame (tweened unless fx.instant). fx = { select, place, wrong } are optional feedback callbacks.

local TweenService = game:GetService("TweenService")

local Socket = {}
Socket.__index = Socket
local DEBUG = true

local PENALTY_PER_WRONG = 10
local MIN_SCORE = 50

local function childOf(folder: Instance, descendant: Instance): Instance?
	local node: Instance? = descendant
	while node and node.Parent ~= folder do
		node = node.Parent
	end
	return node
end

function Socket.new(model: Instance, stepConfig: { [string]: any }, onProgress, onComplete, fx)
	local sockets = model:FindFirstChild("Sockets")
	local loose = model:FindFirstChild("LooseParts")
	assert(sockets and loose, "the item model needs Sockets and LooseParts folders")
	local self = setmetatable({
		sockets = sockets, loose = loose, model = model,
		targets = {}, -- socket name -> { socket = Instance, filled = bool }
		total = 0, filled = 0, wrong = 0, selected = nil :: Instance?,
		onProgress = onProgress, onComplete = onComplete, fx = fx or {},
		destroyed = false, completed = false,
		stepType = stepConfig.type, -- "Reassemble" (one part, one place: tapping the part puts it there) or "Replace" (pick the right part among decoys)
		wrongCount = 0, lastAction = os.clock(),
	}, Socket)
	local wanted = if type(stepConfig.parts) == "table" then stepConfig.parts else nil
	for _, socket in sockets:GetChildren() do
		local matches = wanted == nil
		for _, prefix in wanted or {} do
			if string.sub(socket.Name, 1, #prefix) == prefix then
				matches = true
			end
		end
		if matches and loose:FindFirstChild(socket.Name) then
			self.targets[socket.Name] = { socket = socket, filled = false }
			self.total += 1
		end
	end
	assert(self.total > 0, "no Sockets/<Name> has a matching LooseParts/<Name>")
	if self.fx.init then
		self.fx.init(self) -- the feedback layer shows where each part goes (arrows, a guide line, hints)
	end
	onProgress(0, 0, self.total)
	if DEBUG then
		print(`[Socket] ready: {self.total} sockets, {#loose:GetChildren() - self.total} decoys`)
	end
	return self
end

local function pivotOf(instance: Instance): CFrame
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	return (instance :: BasePart).CFrame
end

local function moveTo(self, part: Instance, cframe: CFrame)
	if self.fx.instant then
		if part:IsA("Model") then
			part:PivotTo(cframe)
		else
			(part :: BasePart).CFrame = cframe
		end
	elseif part:IsA("BasePart") then
		TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Back), { CFrame = cframe }):Play()
	else
		part:PivotTo(cframe)
	end
end

function Socket:Score(): number
	return math.max(MIN_SCORE, 100 - PENALTY_PER_WRONG * self.wrong)
end

-- puts a loose part into its own socket (used by a correct tap, and by a tap on the part itself in Reassemble)
function Socket:Place(chosen: Instance, socket: Instance)
	local target = self.targets[socket.Name]
	if target == nil or target.filled then
		return
	end
	target.filled = true
	self.filled += 1
	self.selected = nil
	self.lastAction = os.clock()
	moveTo(self, chosen, pivotOf(socket))
	if self.fx.place then
		self.fx.place(chosen, socket)
	end
	self.onProgress(self.filled / self.total, self.filled, self.total)
	if self.filled == self.total then
		self.completed = true
		self.onComplete(self:Score())
	end
end

function Socket:OnPointerDown(hit)
	if self.destroyed or self.completed or not hit or not hit.Instance then
		return
	end
	self.lastAction = os.clock()
	local part = childOf(self.loose, hit.Instance)
	if part then
		local target = self.targets[part.Name]
		if target and target.filled then
			return -- already placed
		end
		self.selected = part
		if self.fx.select then
			self.fx.select(part)
		end
		-- Reassemble has no decoys: the part you tapped can only go to one place, so it goes there (no second tap to find)
		if self.stepType == "Reassemble" and target then
			self:Place(part, target.socket)
		end
		return
	end
	local socket = childOf(self.sockets, hit.Instance)
	if socket == nil or self.selected == nil then
		return
	end
	local target = self.targets[socket.Name]
	if target == nil or target.filled then
		return
	end
	local chosen = self.selected
	self.selected = nil
	if chosen.Name == socket.Name then
		self:Place(chosen, socket)
	else
		self.wrong += 1
		self.wrongCount += 1
		if self.fx.wrong then
			self.fx.wrong(chosen, socket)
		end
		if DEBUG then
			print(`[Socket] wrong: {chosen.Name} on {socket.Name} (wrong x{self.wrong}, score would be {self:Score()})`)
		end
	end
end

function Socket:OnDrag() end

function Socket:OnPointerUp() end

function Socket:Destroy()
	self.destroyed = true
	self.selected = nil
	self.onProgress = function() end
	self.onComplete = function() end
end

return Socket
