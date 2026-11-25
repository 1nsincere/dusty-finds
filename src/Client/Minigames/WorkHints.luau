-- WorkHints.luau
-- Purpose: shows the player WHERE to work in Wipe and Scrape: a soft pulsing ring on every dirt / rust spot that still needs
-- cleaning, fading out as the spot gets clean. (Polish uses Highlights in Rub.luau.) Visual only; created by a minigame in
-- :new, driven with :Set(part, strength 0..1) and removed with :Destroy(). One Heartbeat animates every ring.
-- Owner: Dev 1 (Ace) with Claude. Depends on: nothing but the ring picture (tools/blender/unbox_vfx.py, ring.png).

local RunService = game:GetService("RunService")

local RING = "rbxassetid://119128261946876"
local GLOW = "rbxassetid://93831669035461"

local WorkHints = {}
WorkHints.__index = WorkHints

function WorkHints.new(color: Color3)
	local self = setmetatable({ color = color, rings = {}, destroyed = false, t0 = os.clock() }, WorkHints)
	self.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - self.t0
		for _, r in self.rings do
			local pulse = 0.5 + 0.5 * math.sin(t * 3.4 + r.phase)
			-- strong while the spot is dirty, gone when it is clean
			local alpha = r.strength * (0.55 + 0.45 * pulse)
			r.image.ImageTransparency = 1 - alpha * 0.95
			r.halo.ImageTransparency = 1 - alpha * 0.55
			local s = 1 + 0.1 * pulse
			r.gui.Size = UDim2.fromScale(r.size * s, r.size * s)
			r.image.Rotation = (t * 25 + r.phase * 40) % 360
		end
	end)
	return self
end

function WorkHints:Add(part: BasePart)
	if self.destroyed or self.rings[part] then
		return
	end
	local size = math.max(part.Size.X, part.Size.Z) * 1.45
	local gui = Instance.new("BillboardGui")
	gui.Name = "WorkHint"
	gui.Adornee = part
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(size, size)
	gui.MaxDistance = 200
	gui.Parent = part
	local halo = Instance.new("ImageLabel") -- soft glow under the ring so it reads on any colour
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromScale(1, 1)
	halo.BackgroundTransparency = 1
	halo.Image = GLOW
	halo.ImageColor3 = self.color
	halo.ImageTransparency = 1
	halo.Parent = gui
	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = RING
	image.ImageColor3 = self.color
	image.ImageTransparency = 1
	image.ZIndex = 2
	image.Parent = gui
	self.rings[part] = { gui = gui, image = image, halo = halo, size = size, strength = 1, phase = math.random() * 6.28 }
end

-- strength 1 = dirty (ring at full), 0 = clean (ring gone)
function WorkHints:Set(part: BasePart, strength: number)
	local r = self.rings[part]
	if r then
		r.strength = math.clamp(strength, 0, 1)
	end
end

function WorkHints:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.conn:Disconnect()
	for _, r in self.rings do
		r.gui:Destroy()
	end
	table.clear(self.rings)
end

return WorkHints
