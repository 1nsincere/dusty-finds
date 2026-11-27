-- RobberService.luau (ServerScriptService.Server.Services.RobberService)
-- Purpose: the night robber (WP8 + WP9, design in docs/14_Robber_Design.md; numbers in Shared/Config/Robber). On every N-th night a few
-- "Sneaky Visitor" NPCs walk to different online owners' shops, the shutter is lifted for them (HoursService.Breach), they take ONE item
-- from a shelf / pedestal (pedestals weigh more) and run. The owner shoos them with a proximity prompt (cartoon walis tambo): the item
-- comes back. If one escapes, the item is "Stolen" in server memory only (Lib/StolenItems; the item stays in the saved inventory, so no
-- data change) and can be reclaimed for a small fee at the Tanod post until the recovery window ends, then it simply returns.
-- Owner: Dev 2 (Dwayne) / Dev 1 (Ace). Depends on: Shared.Config.Robber, Shared.Hours, Lib.StolenItems, Lib.AccessGroups, DataService,
-- InventoryService, DisplayService, EconomyService, PlotService, HoursService, CustomerNpcService (walking helper), Remotes.Notify.
-- No new remotes: shoo and reclaim are server-side ProximityPrompts (validated here).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local StolenItems = require(script.Parent.Parent.Lib.StolenItems)
local AccessGroups = require(script.Parent.Parent.Lib.AccessGroups)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hours = require(ReplicatedStorage.Shared.Hours)
local Robber = require(ReplicatedStorage.Shared.Config.Robber)
local Townsfolk = require(ReplicatedStorage.Shared.Config.Townsfolk) -- its canal-level route corners are the escape spots
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local RobberService = {}
local DEBUG = true
local log = Log.new("RobberService", DEBUG)

local DataService, InventoryService, DisplayService, EconomyService, PlotService, HoursService, CustomerNpcService =
	nil, nil, nil, nil, nil, nil, nil

local LIFT = Vector3.new(0, 3, 0) -- markers sit on the floor; a rig stands above them (same as CustomerNpcService)
local FADE_TIME = 0.6
local PLAN_EVERY = 5 -- seconds between checks of the clock / expiry

type Stealable = { uid: string, kind: string, slot: number, itemId: string, stars: number?, golden: boolean? }
type Visit = {
	owner: Player,
	plot: Model,
	model: Model,
	humanoid: Humanoid,
	hits: number,
	lastHit: number,
	shooed: boolean, -- enough hits: the visit thread stops, the shoo thread sends the robber off
	fleeing: boolean, -- the dash after a shoo: the walk helpers may move again
	stolenUid: string?,
	stolenName: string?,
}

local visits: { [Player]: Visit } = {} -- one robber per shop at a time
local lastPlannedNight: number? = nil
local folder: Folder? = nil

-- ===== Pure rules (also used by Tests/RobberCheck) =====

-- Which night is it? Night N starts at closing time of game day N and lasts until the shops open again. nil = daytime.
function RobberService.NightId(hour: number, day: number): number?
	if hour >= Hours.SHOP_CLOSE then
		return day
	elseif hour < Hours.SHOP_OPEN then
		return day - 1
	end
	return nil
end

function RobberService.IsRobberNight(nightId: number): boolean
	return nightId % Robber.EveryNthNight == 0
end

-- A shop is a possible target: the owner is past the first sessions and has more than one item out (the last item is never taken).
function RobberService.Eligible(level: number, stealableCount: number): boolean
	return level >= Robber.MinLevel and stealableCount >= Robber.MinStealable
end

-- Weighted pick: pedestal ("Exhibit") items weigh more than shelf ("Display") items. nil when nothing can be taken.
function RobberService.PickTarget(list: { Stealable }, rng: Random): Stealable?
	local total = 0
	for _, entry in list do
		total += Robber.TargetWeights[entry.kind] or 1
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= Robber.TargetWeights[entry.kind] or 1
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

function RobberService.Fee(itemId: string, stars: number?, golden: boolean?): number
	local price = Formulas.quickSellPrice(itemId, stars or 1, golden)
	return math.max(Robber.FeeMin, math.floor(price * Robber.FeeFraction + 0.5))
end

function RobberService.RecoverySeconds(itemId: string): number
	local item = Items[itemId]
	if item and table.find(Robber.LongRarities, item.rarity) then
		return Robber.LongRecoverySeconds
	end
	return Robber.RecoverySeconds
end

-- ===== Helpers =====

local function notify(player: Player, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, "Info", text)
	end
end

local function itemName(itemId: string): string
	local item = Items[itemId]
	return if item then item.name else itemId
end

local function pathPoint(plot: Instance, name: string): Vector3?
	local path = plot:FindFirstChild("CustomerPath")
	local part = path and path:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part.Position else nil
end

local function plotIndexOf(plot: Instance): number?
	return tonumber(string.match(plot.Name, "^Plot(%d+)$"))
end

-- Everything on this owner's shelves and pedestals that a robber could take.
local function stealableItems(owner: Player): { Stealable }
	local out = {}
	local inventory = DataService.GetValue(owner, "inventory") or {}
	for uid, item in inventory do
		local displayed, exhibited = item.state == "Displayed", item.state == "Exhibited"
		if (displayed or exhibited) and type(item.slot) == "number" and not StolenItems.Is(owner, uid) then
			if exhibited or not DisplayService.IsReservedAt(owner, item.slot) then
				table.insert(out, {
					uid = uid, kind = if exhibited then "Exhibit" else "Display", slot = item.slot,
					itemId = item.itemId, stars = item.stars, golden = item.golden,
				})
			end
		end
	end
	return out
end

-- Where to stand to reach a slot: the shelf's / pedestal's StandSpot attachment (as customers do), else the first browse point.
local function standPoint(plot: Instance, entry: Stealable): Vector3?
	local slots = plot:FindFirstChild(if entry.kind == "Exhibit" then "ExhibitSlots" else "DisplaySlots")
	local slot = slots and slots:FindFirstChild((if entry.kind == "Exhibit" then "Exhibit" else "Slot") .. entry.slot)
	local piece = slot and slot:GetAttribute("Piece")
	for _, holderName in { "Shelves", "Pedestals" } do
		local holder = plot:FindFirstChild(holderName)
		local part = holder and piece ~= nil and holder:FindFirstChild(tostring(piece))
		local spot = part and part:FindFirstChild("StandSpot")
		if part and part:IsA("BasePart") and spot and spot:IsA("Attachment") then
			return Vector3.new(spot.WorldPosition.X, part.Position.Y - part.Size.Y / 2, spot.WorldPosition.Z)
		end
	end
	return pathPoint(plot, "Browse1")
end

local function buildBody(owner: Player, plotIndex: number, at: Vector3): (Model?, Humanoid?)
	local templates = ServerStorage:FindFirstChild("NPCs")
	local template = templates and (templates:FindFirstChild(Robber.NpcTemplate) or templates:FindFirstChildWhichIsA("Model"))
	if not (template and template:IsA("Model")) then
		return nil, nil
	end
	local model = template:Clone()
	model.Name = "SneakyVisitor_" .. owner.UserId
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or model.PrimaryPart == nil then
		model:Destroy()
		return nil, nil
	end
	humanoid.DisplayName = Robber.DisplayName
	humanoid.WalkSpeed = Robber.WalkSpeed
	-- the owner's collision group passes THIS shop's shutter (AccessGroups); everyone else's shutter stays solid for everyone
	local group = AccessGroups.characterGroup(false, plotIndex)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	local glow = Instance.new("Highlight") -- a soft purple outline: obvious, cartoonish, not scary
	glow.FillColor = Color3.fromRGB(90, 60, 130)
	glow.FillTransparency = 0.65
	glow.OutlineColor = Color3.fromRGB(190, 150, 255)
	glow.Parent = model
	model:PivotTo(CFrame.new(at + LIFT))
	model.Parent = folder
	model.PrimaryPart:SetNetworkOwner(nil)
	if CustomerNpcService and CustomerNpcService._startAnimations then
		CustomerNpcService._startAnimations(model, humanoid)
	end
	return model, humanoid
end

local function fadeOut(model: Model)
	for _, d in model:GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			TweenService:Create(d, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
		end
	end
	task.wait(FADE_TIME)
end

-- One straight MoveTo (used at the shutter, where the pathfinder would see a wall). Returns reached.
local function moveDirect(visit: Visit, target: Vector3, timeout: number): boolean
	local finished, success = false, false
	local connection = visit.humanoid.MoveToFinished:Connect(function(ok)
		finished, success = true, ok
	end)
	visit.humanoid:MoveTo(target)
	local started = os.clock()
	while not finished and os.clock() - started < timeout and (visit.fleeing or not visit.shooed) do
		task.wait(0.1)
	end
	connection:Disconnect()
	return finished and success
end

-- Pathfinding walk (CustomerNpcService's helper, as an exit so a blocked route never calls CustomerService.Leave).
local function walkPath(visit: Visit, target: Vector3): boolean
	if visit.shooed and not visit.fleeing then
		return false
	end
	local npc = { id = "robber", player = visit.owner, model = visit.model, humanoid = visit.humanoid, gone = false }
	return CustomerNpcService._walkTo(npc, target, true)
end

-- ===== One visit =====

local function endVisit(visit: Visit)
	visits[visit.owner] = nil
	if visit.model.Parent then
		fadeOut(visit.model)
		visit.model:Destroy()
	end
end

-- Canal-level corners of the scanned townsfolk routes: known walkable ground right by the water (built once).
local canalCorners: { Vector3 }? = nil
local function getCanalCorners(): { Vector3 }
	if canalCorners == nil then
		canalCorners = {}
		for _, text in Townsfolk.Routes do
			for triple in string.gmatch(text, "[^;]+") do
				local x, y, z = string.match(triple, "(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)")
				if x and tonumber(y) < Robber.CanalMaxY then
					table.insert(canalCorners :: { Vector3 }, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
				end
			end
		end
	end
	return canalCorners :: { Vector3 }
end

-- The nearest canal bank this robber can really run to from `from`: nearest corners first, each checked with the pathfinder, the
-- run must be at most Robber.CanalMaxRunStuds long. nil = no canal in reach (the robber runs for the street instead).
function RobberService.PickEscape(from: Vector3): Vector3?
	local corners = table.clone(getCanalCorners())
	table.sort(corners, function(a, b)
		return (a.X - from.X) ^ 2 + (a.Z - from.Z) ^ 2 < (b.X - from.X) ^ 2 + (b.Z - from.Z) ^ 2
	end)
	for i = 1, math.min(#corners, Robber.CanalCandidates) do
		local path = PathfindingService:CreatePath({ AgentRadius = 1.8, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
		local ok = pcall(function()
			path:ComputeAsync(from + LIFT, corners[i] + LIFT)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local length, previous = 0, nil
			for _, waypoint in path:GetWaypoints() do
				if previous then
					length += (waypoint.Position - previous).Magnitude
				end
				previous = waypoint.Position
			end
			if length <= Robber.CanalMaxRunStuds then
				return corners[i]
			end
		end
	end
	return nil
end

-- Runs away: out through the door and approach, then to the nearest canal (or the street if no canal is in reach), at FleeSpeed.
-- Returns the kind of place it ran to ("canal" / "street") for the log.
local function runAway(visit: Visit, door: Vector3?, approach: Vector3?, street: Vector3?, shooDash: boolean?): string
	visit.humanoid.WalkSpeed = if shooDash then Robber.FleeSpeed * 1.2 else Robber.FleeSpeed
	if door then
		moveDirect(visit, door, 8)
	end
	if approach then
		moveDirect(visit, approach, 8)
	end
	local canal = RobberService.PickEscape(approach or door or visit.model:GetPivot().Position)
	if canal and walkPath(visit, canal) then
		return "canal"
	end
	if street then
		walkPath(visit, street)
	end
	return "street"
end

-- The visit thread ends here; after a shoo the shoo thread owns the ending (the dash back to the street), so do nothing.
local function finish(visit: Visit)
	if not visit.shooed then
		endVisit(visit)
	end
end

local function runVisit(visit: Visit)
	local owner, plot = visit.owner, visit.plot
	local door, approach, street = pathPoint(plot, "Door"), pathPoint(plot, "Approach"), pathPoint(plot, "StreetEntry")
	local deadline = os.clock() + Robber.LeaveGiveUpSeconds * 3
	local function alive(): boolean
		return Validate.isPlayer(owner) and visit.model.Parent ~= nil and not visit.shooed and os.clock() < deadline
	end

	notify(owner, "💜 A sneaky visitor is near your shop! Hurry back and shoo them away!")
	task.wait(Robber.WarnSeconds) -- a fair warning: the robber loiters in the street while the owner gets back
	if not alive() then
		return finish(visit)
	end
	if approach and not walkPath(visit, approach) then
		return finish(visit)
	end
	if alive() and door and approach then
		-- breach: the shutter lifts for them (HoursService), they step in and a little way inside
		if HoursService.Breach(plot, Robber.BreachSeconds) then
			notify(owner, "🔔 Your shop's shutter is being pried open!")
		end
		task.wait(1)
		local inside = door + (door - approach).Unit * 4
		if not (moveDirect(visit, door, 8) and moveDirect(visit, inside, 8)) then
			return finish(visit)
		end
	end

	-- choose now (the shelves may have changed since the planning), walk to it and "work" for a moment
	local target = if alive() then RobberService.PickTarget(stealableItems(owner), Random.new()) else nil
	if target and #stealableItems(owner) >= Robber.MinStealable then
		local stand = standPoint(plot, target)
		if stand and walkPath(visit, stand) and alive() then
			task.wait(Robber.GrabSeconds)
			if alive() then
				local ok, _, uid = DisplayService.RemoveFromSlot(owner, target.kind, target.slot)
				if ok and uid then
					visit.stolenUid = uid
					visit.stolenName = itemName(target.itemId)
					local seconds = RobberService.RecoverySeconds(target.itemId)
					StolenItems.Add(owner, uid, target.itemId, RobberService.Fee(target.itemId, target.stars, target.golden), seconds)
					notify(owner, `💜 They took your {visit.stolenName}! Catch them before they get away!`)
					log.info(owner.Name, "robbed:", target.itemId, "recovery", seconds, "s")
				end
			end
		end
	end

	-- run for the street. A shoo at any point ends the visit via the shoo handler.
	local ranTo = "none"
	if not visit.shooed then
		ranTo = runAway(visit, door, approach, street)
	end
	if not visit.shooed and visit.stolenUid and Validate.isPlayer(owner) then
		notify(owner, `💨 They jumped into the {if ranTo == "canal" then "canal" else "crowd"} with your {visit.stolenName}! Find the Tanod post in the plaza to get it back (a small fee).`)
		log.info(owner.Name, "robber escaped with", visit.stolenUid, "via the", ranTo)
	end
	finish(visit)
end

-- The owner taps "Shoo!" on the robber (server checks who, how far, how fast). Enough hits: the robber drops the item and runs.
local function onShoo(visit: Visit, tapper: Player)
	if tapper ~= visit.owner or visit.shooed or not Validate.isPlayer(tapper) then
		return
	end
	local root = visit.model.PrimaryPart
	local character = tapper.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and hrp and (hrp.Position - root.Position).Magnitude <= Robber.ShooRange + 6) then
		return
	end
	local now = os.clock()
	if now - visit.lastHit < Robber.ShooCooldown then
		return
	end
	visit.lastHit = now
	visit.hits += 1
	if visit.hits < Robber.ShooHits then
		notify(tapper, `Shoo! ({visit.hits}/{Robber.ShooHits})`)
		return
	end
	visit.shooed = true
	visit.humanoid:MoveTo(root.Position)
	if visit.stolenUid then
		StolenItems.Remove(visit.owner, visit.stolenUid) -- the item was never lost from the saved inventory
		notify(tapper, `✨ Shoo! They dropped your {visit.stolenName}! It's back in your inventory.`)
	else
		notify(tapper, "✨ Shoo! The sneaky visitor ran away empty handed!")
	end
	log.info(tapper.Name, "shooed the robber", visit.stolenUid and "(item returned)" or "(nothing taken)")
	task.spawn(function()
		-- a quick, silly dash to the canal (or the street), then gone
		local plot = visit.plot
		visit.fleeing = true -- the walk helpers may move again
		runAway(visit, pathPoint(plot, "Door"), pathPoint(plot, "Approach"), pathPoint(plot, "StreetEntry"), true)
		endVisit(visit)
	end)
end

-- Sends a robber to this owner's shop now. `force` (testing) skips the clock and level checks. Returns the visit or nil + reason.
function RobberService.Spawn(owner: Player, force: boolean?): (Visit?, string?)
	if not Validate.isPlayer(owner) then
		return nil, "badPlayer"
	end
	if visits[owner] then
		return nil, "alreadyHere"
	end
	local plot = PlotService.GetPlot(owner)
	local plotIndex = plot and plotIndexOf(plot)
	if not (plot and plotIndex) then
		return nil, "noPlot"
	end
	if not force and not RobberService.Eligible(EconomyService.GetLevel(owner) or 0, #stealableItems(owner)) then
		return nil, "notEligible"
	end
	local start = pathPoint(plot, "StreetEntry") or pathPoint(plot, "Approach") or pathPoint(plot, "Door")
	if not start then
		return nil, "noMarkers"
	end
	local model, humanoid = buildBody(owner, plotIndex, start)
	if not (model and humanoid) then
		return nil, "noBody"
	end
	local visit: Visit = { owner = owner, plot = plot, model = model, humanoid = humanoid, hits = 0, lastHit = -10, shooed = false, fleeing = false }
	visits[owner] = visit
	local prompt = Instance.new("ProximityPrompt") -- the walis tambo: one tap per hit, owner only
	prompt.ActionText = "Shoo!"
	prompt.ObjectText = Robber.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Robber.ShooRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(tapper)
		onShoo(visit, tapper)
	end)
	task.spawn(function()
		local ok, err = pcall(runVisit, visit)
		if not ok then
			warn("[RobberService] visit failed:", err)
			visits[owner] = nil
			if model.Parent then
				model:Destroy()
			end
		end
	end)
	log.info("a robber heads for", owner.Name, "'s", plot.Name)
	return visit, nil
end

-- ===== The nights =====

local function planNight(nightId: number)
	local eligible = {}
	for _, player in Players:GetPlayers() do
		if visits[player] == nil and PlotService.GetPlot(player) then
			local level = EconomyService.GetLevel(player) or 0
			if RobberService.Eligible(level, #stealableItems(player)) then
				table.insert(eligible, player)
			end
		end
	end
	local rng = Random.new()
	for i = #eligible, 2, -1 do -- shuffle: a different few shops each time
		local j = rng:NextInteger(1, i)
		eligible[i], eligible[j] = eligible[j], eligible[i]
	end
	local count = math.min(rng:NextInteger(Robber.RobbersPerNight[1], Robber.RobbersPerNight[2]), #eligible)
	log.info(`night {nightId}: {count} robber(s) of {#eligible} eligible shop(s)`)
	for i = 1, count do
		local owner = eligible[i]
		task.delay(rng:NextNumber(Robber.StartDelay[1], Robber.StartDelay[2]), function()
			if not Hours.shopOpen() then -- still night, owner still here
				RobberService.Spawn(owner)
			end
		end)
	end
end

local function sweep()
	local nightId = RobberService.NightId(Hours.now(), Hours.dayAt(Workspace:GetServerTimeNow()))
	if nightId and nightId ~= lastPlannedNight then
		lastPlannedNight = nightId
		if RobberService.IsRobberNight(nightId) then
			planNight(nightId)
		end
	end
	for _, player in Players:GetPlayers() do
		for _, back in StolenItems.TakeExpired(player) do
			notify(player, `Your {itemName(back.itemId)} found its way back to your inventory.`)
			log.info(player.Name, "stolen item expired, returned:", back.itemId)
		end
	end
end

-- ===== The Tanod post (reclaim) =====

local function claim(player: Player)
	local list = StolenItems.List(player)
	local entry = list[1]
	if entry == nil then
		notify(player, "Nothing waiting for you at the Tanod post.")
		return
	end
	if not InventoryService.Get(player, entry.uid) then
		StolenItems.Remove(player, entry.uid) -- the item is gone from the inventory some other way
		return
	end
	if not EconomyService.CanAfford(player, entry.fee) then
		notify(player, `The Tanod keeps your {itemName(entry.itemId)} safe. Claiming it costs ${entry.fee}.`)
		return
	end
	if not EconomyService.Spend(player, entry.fee, "TanodFee") then
		return
	end
	StolenItems.Remove(player, entry.uid) -- charged exactly once: the entry is gone the moment the money is taken
	notify(player, `✅ You got your {itemName(entry.itemId)} back for ${entry.fee}. Thank you, Tanod!`)
	log.info(player.Name, "reclaimed", entry.itemId, "for", entry.fee)
end

local function buildPost()
	local config = Robber.Post
	local post = Workspace:FindFirstChild(config.Name)
	if post == nil then
		post = Instance.new("Part")
		post.Name = config.Name
		post.Size = Vector3.new(4, 6, 2)
		post.Anchored = true
		post.CanCollide = false
		post.Color = Color3.fromRGB(70, 110, 170)
		post.Material = Enum.Material.SmoothPlastic
		post.Position = config.Position
		post.Parent = Workspace
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(190, 34)
		gui.StudsOffset = Vector3.new(0, 4.5, 0)
		gui.MaxDistance = 80
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 250, 238)
		label.TextColor3 = Color3.fromRGB(40, 70, 120)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = config.Label
		label.Parent = gui
		gui.Parent = post
	end
	local prompt = post:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim lost item"
	prompt.ObjectText = "Tanod"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(claim)
end

-- ===== Lifecycle =====

function RobberService.Init(services)
	DataService = services.DataService
	InventoryService = services.InventoryService
	DisplayService = services.DisplayService
	EconomyService = services.EconomyService
	PlotService = services.PlotService
	HoursService = services.HoursService
	CustomerNpcService = services.CustomerNpcService
	log.info("Init")
end

function RobberService.Start()
	folder = Instance.new("Folder")
	folder.Name = "Robbers"
	folder.Parent = Workspace
	buildPost()
	Players.PlayerRemoving:Connect(function(player)
		local visit = visits[player]
		if visit and visit.model.Parent then
			visit.model:Destroy()
		end
		visits[player] = nil
		StolenItems.Clear(player)
	end)
	task.spawn(function()
		while true do
			task.wait(PLAN_EVERY)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[RobberService] sweep failed:", err)
			end
		end
	end)
	log.info(`Start: robbers every {Robber.EveryNthNight} nights, Tanod post at {Robber.Post.Position}`)
end

-- Testing: RobberService.DebugSpawn(player) sends one robber now, whatever the time or level.
function RobberService.DebugSpawn(player: Player)
	return RobberService.Spawn(player, true)
end

return RobberService
