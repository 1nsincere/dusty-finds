-- PaintService.luau (ServerScriptService.Server.Services.PaintService)
-- Purpose: wall and floor paints (docs/12 Stage 2): buy at the Paint Bar (RequestBuyPaint), use an owned paint in your shop
-- (RequestApplyPaint), and draw the paints on every shop so visitors see them. Looks only: never changes slots, prices or
-- rating. One wall paint and one floor paint per shop ("" = the original look).
-- Owner: Dev 1 (Ace). Depends on: DataService (paints field), EconomyService (Spend), Shared.Config.Paints,
-- Workspace.Plots (Walls folder, Facade.Shell.Shop_Walls / Shop_Floor models, OwnerUserId attribute), Workspace.PaintCounter.
-- Validation order (buy): known paint -> data loaded -> not owned -> at the Paint Bar -> pay -> save (refund if the save fails).
-- Paints are always in stock (no restock roll): they are the cheap, friendly basics next to the rolling skin stock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Paints = require(ReplicatedStorage.Shared.Config.Paints)
local PlotTargets = require(ReplicatedStorage.Shared.PlotTargets)

local PaintService = {}
local DEBUG = true
local log = Log.new("PaintService", DEBUG)

local DataService, EconomyService = nil, nil
local FIELD = Paints.FIELD
local ORIG_COLOR, ORIG_MATERIAL = "PaintOrigColor", "PaintOrigMaterial"

local function notify(player: any, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, "Info", text)
	end
end

-- Where a player must stand to buy. Replaceable so tests (mock players) can skip the distance check on their own copy.
local nearCounter = function(player: any): boolean
	local counter = workspace:FindFirstChild("PaintCounter")
	return counter ~= nil and counter:IsA("BasePart") and Validate.withinDistance(player, counter, Paints.BuyMaxStuds)
end

function PaintService.SetNearCheck(fn: ((any) -> boolean)?)
	nearCounter = fn or nearCounter
end

-- ===== Drawing =====

-- The parts a kind of paint covers in one plot.
local function targetsOf(plot: Instance, kind: string): { BasePart }
	return PlotTargets.paint(plot, kind) -- shared with the client's 60-second Preview
end

local function paintFor(plot: Instance, kind: string): any
	local userId = plot:GetAttribute("OwnerUserId")
	local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local data = owner and DataService and DataService.Get(owner)
	local id = data and data.paints and data.paints[FIELD[kind]]
	return if type(id) == "string" then Paints.BY_ID[id] else nil
end

-- Draws one part with a paint (nil = restore the original look). The original is remembered in attributes the first time.
local function drawPart(part: BasePart, paint: any)
	if part:GetAttribute(ORIG_COLOR) == nil then
		local original = PlotTargets.snapshot(part) -- a textured part keeps its tint here (SurfaceAppearance.Color), see PlotTargets
		part:SetAttribute(ORIG_COLOR, original.color)
		part:SetAttribute(ORIG_MATERIAL, original.material.Name)
		part:SetAttribute("PaintOrigTransparency", original.transparency) -- the main floor texture is hidden while a floor paint is on
	end
	if paint == nil then
		PlotTargets.restorePart(part, {
			color = part:GetAttribute(ORIG_COLOR),
			material = Enum.Material[part:GetAttribute(ORIG_MATERIAL)] or part.Material,
			transparency = part:GetAttribute("PaintOrigTransparency") or 0,
		})
		return
	end
	PlotTargets.paintPart(part, paint.color, paint.material)
end

-- Draws a plot with its owner's paints (or the original look when nobody owns it).
function PaintService.DrawPlot(plot: Instance)
	for _, kind in Paints.KINDS do
		local paint = paintFor(plot, kind)
		for _, part in targetsOf(plot, kind) do
			drawPart(part, paint)
		end
	end
end

-- Used by the tests on a copy of a plot.
function PaintService.DrawKind(plot: Instance, kind: string, paintId: string)
	local paint = if paintId ~= "" then Paints.BY_ID[paintId] else nil
	for _, part in targetsOf(plot, kind) do
		drawPart(part, paint)
	end
end

local function plotOf(player: Player): Instance?
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- ===== Buy / apply =====

-- Returns ok, reason ("unknown", "noData", "owned", "far", "cash", "saveFailed").
function PaintService.Buy(player: Player, paintId: any): (boolean, string?)
	local paint = type(paintId) == "string" and Paints.BY_ID[paintId] or nil
	if paint == nil then
		return false, "unknown"
	end
	if paint.pass ~= nil then
		return false, "passOnly" -- theme paints come with a Robux pass (MonetizationService), never for cash
	end
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" or type(data.paints.owned) ~= "table" then
		return false, "noData"
	end
	if data.paints.owned[paintId] then
		return false, "owned"
	end
	if not nearCounter(player) then
		return false, "far"
	end
	if not EconomyService.Spend(player, paint.price, "Shop", paintId) then
		return false, "cash"
	end
	if not DataService.Set(player, "paints.owned." .. paintId, true) then
		EconomyService.AddCash(player, paint.price, "Refund")
		return false, "saveFailed"
	end
	Analytics.Event(player, "PaintBought", 1, paint.kind, paintId)
	log.info(`{player.Name} bought {paintId} for ${paint.price}`)
	return true, nil
end

-- kind = "Wall" | "Floor"; paintId = an owned paint of that kind, or "" for the original look.
-- Returns ok, reason ("badKind", "unknown", "wrongKind", "noData", "notOwned", "saveFailed").
function PaintService.Apply(player: Player, kind: any, paintId: any): (boolean, string?)
	local field = type(kind) == "string" and FIELD[kind]
	if not field then
		return false, "badKind"
	end
	if type(paintId) ~= "string" then
		return false, "unknown"
	end
	if paintId ~= "" then
		local paint = Paints.BY_ID[paintId]
		if paint == nil then
			return false, "unknown"
		end
		if paint.kind ~= kind then
			return false, "wrongKind"
		end
	end
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" or type(data.paints.owned) ~= "table" then
		return false, "noData"
	end
	if paintId ~= "" and not data.paints.owned[paintId] then
		return false, "notOwned"
	end
	if not DataService.Set(player, "paints." .. field, paintId) then
		return false, "saveFailed"
	end
	local plot = plotOf(player)
	if plot then
		PaintService.DrawPlot(plot)
	end
	return true, nil
end

-- Admin gift: own a paint for free (no distance / cash checks); use = also put it on. Returns ok, reason.
function PaintService.Grant(player: Player, paintId: string, use: boolean?): (boolean, string?)
	local paint = Paints.BY_ID[paintId]
	if paint == nil then
		return false, "unknown"
	end
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" then
		return false, "noData"
	end
	if not data.paints.owned[paintId] and not DataService.Set(player, "paints.owned." .. paintId, true) then
		return false, "saveFailed"
	end
	if use then
		return PaintService.Apply(player, paint.kind, paintId)
	end
	return true, nil
end

local REASON_TEXT = {
	passOnly = "That paint comes with a theme pass at the Collector's Corner.",
	owned = "You already own that paint.",
	far = "Buy paints at the Paint Bar upstairs in the market.",
	cash = "Not enough cash for that paint.",
	notOwned = "You don't own that paint yet.",
	saveFailed = "Couldn't save that. Try again.",
}

function PaintService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	log.info("Init")
end

function PaintService.Start()
	Remotes.RequestBuyPaint.OnServerEvent:Connect(function(player, paintId)
		if not Validate.rateLimit(player, "RequestBuyPaint", 2) then
			return
		end
		local ok, reason = PaintService.Buy(player, paintId)
		if ok then
			local paint = Paints.BY_ID[paintId]
			notify(player, `You got {paint.name}! Use it in the Paint Bar window.`)
		elseif reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestApplyPaint.OnServerEvent:Connect(function(player, kind, paintId)
		if not Validate.rateLimit(player, "RequestApplyPaint", 4) then
			return
		end
		local _, reason = PaintService.Apply(player, kind, paintId)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)

	-- redraw a shop whenever it changes hands (owner joins: their paints; owner leaves: the original look)
	local plots = workspace:WaitForChild("Plots", 30)
	if plots then
		local function hook(plot: Instance)
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
				PaintService.DrawPlot(plot)
			end)
			-- a room bought later (Back Room, Showroom) is built after the paint was applied: paint it too once it has its parts
			plot.ChildAdded:Connect(function(child)
				if string.sub(child.Name, 1, 10) == "Expansion_" then
					task.delay(1, function()
						if plot.Parent then
							PaintService.DrawPlot(plot)
						end
					end)
				end
			end)
			PaintService.DrawPlot(plot)
		end
		for _, plot in plots:GetChildren() do
			hook(plot)
		end
		plots.ChildAdded:Connect(hook)
	end
	log.info("Start")
end

return PaintService
