-- HoursService.luau (ServerScriptService.Server.Services.HoursService)
-- Purpose: opening hours on the in-game clock (Shared.Hours, same for every player, not real time). Once a second it checks the clock; when the Warehouse Market opens or
-- closes it turns the market's prompts (tag "MarketPrompt": Supply Desk, Skins Stall, Shelves & Pedestals, Collector's Corner, Paint
-- Bar) on or off and tells players; when shops close, each shop's door shutter rolls down (only that shop's owner can pass), visitors inside
-- are walked out, and customer arrivals stop (CustomerService).
-- It also publishes Workspace attributes MarketOpen / ShopOpen for UI and tests. The buy handlers check Hours.marketOpen() themselves,
-- so a hacked client cannot buy at night. Owner: Dev 1 (Ace). Depends on: Shared.Hours, Remotes.Notify, Studio tag MarketPrompt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Log = require(script.Parent.Parent.Lib.Log)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hours = require(ReplicatedStorage.Shared.Hours)
local AccessGroups = require(script.Parent.Parent.Lib.AccessGroups)

local HoursService = {}
local DEBUG = true
local log = Log.new("HoursService", DEBUG)

local PROMPT_TAG = "MarketPrompt"
local marketOpen: boolean? = nil
local shopOpen: boolean? = nil
local openText: { [Instance]: string } = {} -- the prompt's normal ActionText, put back at opening

local function setPrompt(prompt: Instance, open: boolean)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if openText[prompt] == nil then
		openText[prompt] = prompt.ActionText
	end
	prompt.Enabled = open
	prompt.ActionText = if open then openText[prompt] else "Closed"
end

local function applyMarket(open: boolean)
	for _, prompt in CollectionService:GetTagged(PROMPT_TAG) do
		setPrompt(prompt, open)
	end
end

local function tell(text: string)
	for _, player in Players:GetPlayers() do
		Remotes.Notify:FireClient(player, "Info", text)
	end
end

-- ===== door shutters (shops and the Warehouse Market) =====
-- Every shop gets a roll-down shutter across its doorway (built here from CustomerPath.Door / Approach, so nothing is Studio-only),
-- and so does the Warehouse Market's big front door (MARKET_DOOR below, measured from the hall's WalkCollision.DoorLintel).
-- Closed: visible "CLOSED" shutter. A shop's is solid for everyone except its owner (collision groups, Lib/AccessGroups); the market's
-- is solid for everybody. Open: rolled up.
local SHUTTER = { width = 11.6, height = 11, thickness = 0.6, openHeight = 0.3 }
local MARKET_DOOR = {
	center = Vector3.new(-50, 4.9, 203.6), -- x/z middle of the doorway just outside the front wall; y = floor top
	dir = Vector3.new(0, 0, -1), -- pointing out to the street
	width = 16.6,
	height = 17.4, -- floor to the door lintel
	inside = { minX = -112, maxX = 12, minZ = 206, maxZ = 316, maxY = 48 }, -- the hall (anyone in here is walked out at closing)
	exit = Vector3.new(-50, 6.5, 196),
}

type ShutterInfo = { part: Part, gui: SurfaceGui, floorTop: number, dir: Vector3, centerXZ: Vector3, width: number, height: number, openAttr: string }
local shutters: { [Model]: ShutterInfo } = {} -- one per shop
local marketShutter: ShutterInfo? = nil

local function plotIndexOf(plot: Instance): number?
	return tonumber(string.match(plot.Name, "^Plot(%d+)$"))
end

local function shutterCFrame(info: ShutterInfo, height: number): CFrame
	local center = Vector3.new(info.centerXZ.X, info.floorTop + height / 2, info.centerXZ.Z)
	return CFrame.lookAt(center, center + info.dir)
end

-- Where a shop's door is: outward direction, the doorway centre and the floor height (from CustomerPath.Door/Approach and Floor).
local function doorGeometry(plot: Instance): { floorTop: number, dir: Vector3, centerXZ: Vector3 }?
	local path = plot:FindFirstChild("CustomerPath")
	local floor = plot:FindFirstChild("Floor")
	local door = path and path:FindFirstChild("Door")
	local approach = path and path:FindFirstChild("Approach")
	if not (floor and door and approach) then
		return nil
	end
	local dir = ((approach :: BasePart).Position - (door :: BasePart).Position) * Vector3.new(1, 0, 1)
	dir = dir.Unit
	return {
		floorTop = (floor :: BasePart).Position.Y + (floor :: BasePart).Size.Y / 2,
		dir = dir,
		centerXZ = (door :: BasePart).Position + dir * 0.45,
	}
end

-- The visible shutter: a metal slab with slat lines and a CLOSED sign on its street side.
local function makeShutterPart(info: ShutterInfo, name: string, group: string, subText: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(86, 96, 92)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(info.width, info.height, SHUTTER.thickness)
	part.CollisionGroup = group
	part.CFrame = shutterCFrame(info, info.height)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = part
	for i = 1, 7 do -- slat lines, so it reads as a roll-down door
		local line = Instance.new("Frame")
		line.BackgroundColor3 = Color3.fromRGB(70, 80, 76)
		line.BorderSizePixel = 0
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Position = UDim2.fromScale(0, i / 8)
		line.Parent = gui
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.9, 0.3)
	label.Position = UDim2.fromScale(0.05, 0.26)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "CLOSED"
	label.TextColor3 = Color3.fromRGB(235, 90, 70)
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.8, 0.12)
	sub.Position = UDim2.fromScale(0.1, 0.58)
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.Text = subText
	sub.TextColor3 = Color3.fromRGB(240, 236, 226)
	sub.Parent = gui
	info.gui = gui
	return part
end

function HoursService.BuildShutter(plot: Model): Part?
	local index = plotIndexOf(plot)
	local geo = doorGeometry(plot)
	if not (geo and index) then
		return nil
	end
	local old = plot:FindFirstChild("ShopShutter")
	if old then
		old:Destroy()
	end
	local info = { floorTop = geo.floorTop, dir = geo.dir, centerXZ = geo.centerXZ, width = SHUTTER.width, height = SHUTTER.height, openAttr = "ShopOpen" } :: any
	local part = makeShutterPart(info, "ShopShutter", AccessGroups.shutterGroup(index), "Back at " .. Hours.format(Hours.SHOP_OPEN))
	info.part = part
	part.Parent = plot
	shutters[plot] = info
	return part
end

-- The Warehouse Market's front door shutter (a Part in Workspace named MarketShutter; solid for everyone).
function HoursService.BuildMarketShutter(): Part
	local old = Workspace:FindFirstChild("MarketShutter")
	if old then
		old:Destroy()
	end
	local info = {
		floorTop = MARKET_DOOR.center.Y, dir = MARKET_DOOR.dir, centerXZ = MARKET_DOOR.center,
		width = MARKET_DOOR.width, height = MARKET_DOOR.height, openAttr = "MarketOpen",
	} :: any
	local part = makeShutterPart(info, "MarketShutter", "Default", "Opens at " .. Hours.format(Hours.MARKET_OPEN))
	info.part = part
	part.Parent = Workspace
	marketShutter = info
	return part
end

-- Roll a shutter down (closed) or up (open). `instant` skips the animation (server start).
local function setShutter(info: ShutterInfo, closed: boolean, instant: boolean)
	local part = info.part
	local height = if closed then info.height else SHUTTER.openHeight
	-- the top edge stays fixed: open = a slim slab hugging the top of the doorway, closed = reaches the floor
	local cf = shutterCFrame(info, info.height)
	if not closed then
		cf = cf * CFrame.new(0, (info.height - SHUTTER.openHeight) / 2, 0)
	end
	local size = Vector3.new(info.width, height, SHUTTER.thickness)
	if instant then
		part.Size, part.CFrame = size, cf
		part.CanCollide = closed
		part.Transparency = if closed then 0 else 1
		info.gui.Enabled = closed
		return
	end
	if closed then
		part.CanCollide = true
		part.Transparency = 0
		info.gui.Enabled = true
	else
		part.CanCollide = false
		info.gui.Enabled = false
	end
	TweenService:Create(part, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = size, CFrame = cf }):Play()
	if not closed then
		task.delay(1.5, function()
			if part.Parent and Workspace:GetAttribute(info.openAttr) == true then
				part.Transparency = 1
			end
		end)
	end
end

-- True when a world position is inside the shop behind this plot's door (ground and upper floors, back rooms included).
function HoursService.IsInsideShop(plot: Model, position: Vector3): boolean
	local info = doorGeometry(plot)
	local floor = plot:FindFirstChild("Floor") :: BasePart?
	if info == nil or floor == nil then
		return false
	end
	local offset = position - info.centerXZ
	local depth = -offset:Dot(info.dir) -- how far behind the door (into the shop)
	local lateral = math.abs(offset:Dot(info.dir:Cross(Vector3.yAxis)))
	local half = math.max(floor.Size.X, floor.Size.Z) / 2
	return depth > 0.8 and depth < half * 2.6 and lateral < half and position.Y > info.floorTop - 6 and position.Y < info.floorTop + 45
end

-- True when a world position is inside the Warehouse Market hall.
function HoursService.IsInsideMarket(position: Vector3): boolean
	local b = MARKET_DOOR.inside
	return position.X > b.minX and position.X < b.maxX and position.Z > b.minZ and position.Z < b.maxZ and position.Y < b.maxY
end

-- Anyone inside a closed shop who is not its owner is walked out to the street (the shutter stops anyone coming in).
local function emptyClosedShops()
	for plot in shutters do
		local ownerId = plot:GetAttribute("OwnerUserId")
		local exit = (plot:FindFirstChild("CustomerPath") and plot.CustomerPath:FindFirstChild("Exit")) :: BasePart?
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and player.UserId ~= ownerId and HoursService.IsInsideShop(plot, root.Position) then
				if exit then
					(player.Character :: Model):PivotTo(CFrame.new(exit.Position + Vector3.new(0, 3, 0)))
				end
				Remotes.Notify:FireClient(player, "Info", "This shop is closed. Come back at " .. Hours.format(Hours.SHOP_OPEN) .. ".")
			end
		end
	end
end

-- Everyone still in the Warehouse Market when it is closed is walked out the front door.
local function emptyClosedMarket()
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and HoursService.IsInsideMarket(root.Position) then
			(player.Character :: Model):PivotTo(CFrame.new(MARKET_DOOR.exit + Vector3.new(0, 3, 0)))
			Remotes.Notify:FireClient(player, "Info", "The Warehouse Market is closed. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
		end
	end
end

-- Compare with the last state; announce only real changes (not at server start).
function HoursService.Refresh(hour: number?)
	local h = hour or Hours.now()
	local m, s = Hours.marketOpen(h), Hours.shopOpen(h)
	if m ~= marketOpen then
		local first = marketOpen == nil
		marketOpen = m
		Workspace:SetAttribute("MarketOpen", m)
		applyMarket(m)
		if marketShutter then
			setShutter(marketShutter, not m, first)
		end
		if not first then
			tell(if m then "The Warehouse Market is open!" else "The Warehouse Market is closed for the night. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
		end
		log.info("market", if m then "open" else "closed")
	end
	if s ~= shopOpen then
		local first = shopOpen == nil
		shopOpen = s
		Workspace:SetAttribute("ShopOpen", s)
		for _, info in shutters do
			setShutter(info, not s, first)
		end
		if not first then
			tell(if s then "Shops are open: customers are arriving again!" else "Closing time: the shops are closed until " .. Hours.format(Hours.SHOP_OPEN) .. ". Visitors are walked out; owners can still restore and decorate.")
		end
		log.info("shops", if s then "open" else "closed")
	end
	if not s then
		emptyClosedShops()
	end
	if not m then
		emptyClosedMarket()
	end
end

-- ===== Breach (WP9, docs/14): the night robber's way in =====
-- The shutter stays SOLID for everyone (visitors still cannot enter, only the owner passes; HoursCheck rules unchanged). Breach only
-- LIFTS the slab a few studs for a moment (a visible gap + the warning the owner sees) while the robber, who is put in the owner's
-- collision group by RobberService, walks through. It never touches CanCollide, never opens the shop, and puts itself back.
local BREACH_LIFT = 3 -- studs the shutter slab is raised
local breached: { [Model]: boolean } = {}

function HoursService.IsBreached(plot: Model): boolean
	return breached[plot] == true
end

-- Raises this shop's closed shutter for `seconds`. Returns false if the shop has no shutter, is open (nothing to breach) or already breached.
function HoursService.Breach(plot: Model, seconds: number): boolean
	local info = shutters[plot]
	if info == nil or breached[plot] or Workspace:GetAttribute(info.openAttr) == true then
		return false
	end
	breached[plot] = true
	local part = info.part
	TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = shutterCFrame(info, info.height) + Vector3.new(0, BREACH_LIFT, 0),
	}):Play()
	log.info(plot.Name, "shutter breached for", seconds, "s")
	task.delay(seconds, function()
		breached[plot] = nil
		-- the morning may have opened it meanwhile: then setShutter already placed it, leave it alone
		if part.Parent and Workspace:GetAttribute(info.openAttr) ~= true then
			TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				CFrame = shutterCFrame(info, info.height),
			}):Play()
		end
	end)
	return true
end

function HoursService.Init(_services)
	log.info("Init")
end

function HoursService.Start()
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(function(prompt)
		setPrompt(prompt, marketOpen ~= false)
	end)
	AccessGroups.register()
	local plots = Workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:IsA("Model") then
			HoursService.BuildShutter(plot)
		end
	end
	HoursService.BuildMarketShutter()
	HoursService.Refresh()
	task.spawn(function()
		while true do
			task.wait(1)
			HoursService.Refresh()
		end
	end)
	log.info("Start")
end

return HoursService
