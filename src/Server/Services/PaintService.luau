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
local Hours = require(ReplicatedStorage.Shared.Hours)
local Paints = require(ReplicatedStorage.Shared.Config.Paints)
local PlotTargets = require(ReplicatedStorage.Shared.PlotTargets)
local Contrast = require(ReplicatedStorage.Shared.Contrast)
local Themes = require(ReplicatedStorage.Shared.Config.Themes)

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
	PlotTargets.paintPart(part, paint.color, paint.material, paint.finish)
end

-- Draws a plot with its owner's paints (or the original look when nobody owns it).
-- The paint to SHOW for a kind. Trim goes through the contrast guard (Shared.Contrast): a trim too close to the wall in lightness is
-- moved lighter or darker so the building's edges never vanish. What the player chose stays saved as it is. Pure, used by DrawPlot and the tests.
function PaintService.Effective(kind: string, paint: any, wallPaint: any): any
	if kind == "Trim" and paint ~= nil and wallPaint ~= nil then
		local color, changed = Contrast.fixTrim(wallPaint.color, paint.color)
		if changed then
			return { color = color, material = paint.material, finish = paint.finish }
		end
	end
	return paint
end

-- Draws a plot with its owner's paints (or the original look when nobody owns it).
function PaintService.DrawPlot(plot: Instance)
	local wallPaint = paintFor(plot, "Wall") or Paints.DEFAULTS.Wall
	for _, kind in Paints.KINDS do
		-- no paint chosen (or nobody owns the shop): every room gets the same default look (Paints.DEFAULTS)
		local paint = PaintService.Effective(kind, paintFor(plot, kind) or Paints.DEFAULTS[kind], wallPaint)
		for _, part in targetsOf(plot, kind) do
			drawPart(part, paint)
		end
	end
end

-- Draws the default look (Paints.DEFAULTS) on one kind. Used by the tests on a copy of a plot.
function PaintService.DrawDefault(plot: Instance, kind: string)
	for _, part in targetsOf(plot, kind) do
		drawPart(part, Paints.DEFAULTS[kind])
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
	if paint.premium then
		return false, "robuxOnly" -- Premium paints are bought with Robux (MonetizationService) or earned as a collector, never for cash
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

-- ===== Themes: four paints in one tap =====

local function ownedTable(data: any): { [string]: boolean }
	return if data and type(data.paints) == "table" and type(data.paints.owned) == "table" then data.paints.owned else {}
end

-- Buys (or claims, for free themes) a whole look. The price is worked out HERE from what the player does not own yet: the client's
-- number is never used. Returns ok, reason ("unknown", "passOnly", "noData", "owned", "far", "cash", "saveFailed"), price paid.
function PaintService.BuyTheme(player: Player, themeId: any): (boolean, string?, number?)
	local theme = type(themeId) == "string" and Themes.BY_ID[themeId] or nil
	if theme == nil then
		return false, "unknown", nil
	end
	if theme.tier == "pass" then
		return false, "passOnly", nil
	end
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" or type(data.paints.owned) ~= "table" then
		return false, "noData", nil
	end
	local owned = ownedTable(data)
	if Themes.ownsAll(theme, owned) then
		return false, "owned", nil
	end
	if not nearCounter(player) then
		return false, "far", nil
	end
	local price = Themes.price(theme, owned) or 0
	if price > 0 and not EconomyService.Spend(player, price, "Shop", theme.id) then
		return false, "cash", nil
	end
	for _, id in Themes.paintIds(theme) do
		if not owned[id] and not DataService.Set(player, "paints.owned." .. id, true) then
			if price > 0 then
				EconomyService.AddCash(player, price, "Refund")
			end
			return false, "saveFailed", nil
		end
	end
	Analytics.Event(player, "ThemeBought", price, theme.tier, theme.id)
	log.info(`{player.Name} got theme {theme.id} for ${price}`)
	return true, nil, price
end

-- Uses a theme the player owns: all four paints at once (one save each, one redraw). "starter" puts the default look back.
-- Returns ok, reason ("unknown", "noData", "notOwned", "saveFailed").
function PaintService.ApplyTheme(player: Player, themeId: any): (boolean, string?)
	local theme = type(themeId) == "string" and Themes.BY_ID[themeId] or nil
	if theme == nil then
		return false, "unknown"
	end
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" or type(data.paints.owned) ~= "table" then
		return false, "noData"
	end
	if not Themes.ownsAll(theme, ownedTable(data)) then
		return false, "notOwned"
	end
	for _, slot in Themes.SLOTS do
		if not DataService.Set(player, "paints." .. Paints.FIELD[slot], theme.looks[slot]) then
			return false, "saveFailed"
		end
	end
	local plot = plotOf(player)
	if plot then
		PaintService.DrawPlot(plot)
	end
	return true, nil
end

-- Premium paints that can be EARNED: given for free once the player's Collector tier reaches paint.earnTier (1 Dusty .. 5 Radiant).
-- Safe to call any time (already owned = nothing happens). Returns the ids newly given.
function PaintService.GrantEarned(player: any, tier: number): { string }
	local given = {}
	local data = DataService.Get(player)
	if data == nil or type(data.paints) ~= "table" or type(data.paints.owned) ~= "table" then
		return given
	end
	for _, paint in Paints.LIST do
		if paint.premium and type(paint.earnTier) == "number" and tier >= paint.earnTier and not data.paints.owned[paint.id] then
			if DataService.Set(player, "paints.owned." .. paint.id, true) then
				table.insert(given, paint.id)
			end
		end
	end
	if #given > 0 then
		local names = {}
		for _, id in given do
			table.insert(names, Paints.BY_ID[id].name)
		end
		notify(player, `Collector reward! You earned: {table.concat(names, ", ")}. Find it in the Paint Bar (Owned).`)
		Analytics.Event(player, "PaintEarned", #given, tostring(tier))
	end
	return given
end

local REASON_TEXT = {
	robuxOnly = "That one is a Premium paint: buy it in the Premium tab, or earn it as a collector.",
	passOnly = "That look comes with a theme pass at the Collector's Corner.",
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
		if not Hours.marketOpen() then
			Remotes.Notify:FireClient(player, "Info", "The Warehouse Market is closed. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
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
	Remotes.RequestBuyTheme.OnServerEvent:Connect(function(player, themeId)
		if not Validate.rateLimit(player, "RequestBuyTheme", 2) then
			return
		end
		if not Hours.marketOpen() then
			Remotes.Notify:FireClient(player, "Info", "The Warehouse Market is closed. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
			return
		end
		local ok, reason = PaintService.BuyTheme(player, themeId)
		if ok then
			notify(player, `You got {Themes.BY_ID[themeId].name}! Use it in the Paint Bar window.`)
		elseif reason == "owned" then
			notify(player, "You already own every paint of that look.")
		elseif reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestApplyTheme.OnServerEvent:Connect(function(player, themeId)
		if not Validate.rateLimit(player, "RequestApplyTheme", 3) then
			return
		end
		local _, reason = PaintService.ApplyTheme(player, themeId)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)

	-- collector rewards: a premium paint with an earnTier is given when the player's Collector tier (CollectorService sets the player
	-- attribute DF_CollectorTier) reaches it, now and later. The profile may still be loading when the tier first appears, so retry briefly.
	local function watchTier(player: Player)
		local function check()
			local tier = player:GetAttribute("DF_CollectorTier")
			if type(tier) == "number" then
				for _ = 1, 20 do
					if DataService.Get(player) ~= nil then
						PaintService.GrantEarned(player, tier)
						return
					end
					task.wait(0.5)
				end
			end
		end
		player:GetAttributeChangedSignal("DF_CollectorTier"):Connect(function()
			task.spawn(check)
		end)
		task.spawn(check)
	end
	Players.PlayerAdded:Connect(watchTier)
	for _, player in Players:GetPlayers() do
		watchTier(player)
	end

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
