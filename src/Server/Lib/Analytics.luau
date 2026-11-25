-- Analytics.luau (ServerScriptService.Server.Lib.Analytics)
-- Purpose: ONE safe place that talks to Roblox's AnalyticsService (docs/12 Stage 2): economy flow (cash in / out), the
-- first-time-player funnel, and a few custom events. Every call is wrapped so analytics can NEVER break gameplay, and
-- it does nothing for mock players (tests) or invalid values. Events only reach the dashboard from a PUBLISHED server;
-- in Studio the calls are harmless no-ops.
-- Owner: Dev 1 (Ace). Depends on: Validate (isPlayer). Called by: EconomyService, ShipmentService, RestorationService,
-- DisplayService, InventoryService, SkinService, UpgradeService, CustomerService.
--
-- Limits to respect (Roblox): max 10 currencies (we use 1: "Cash"), max 100 custom event names (we use 4), max 3 custom
-- fields (CustomField01..03, strings), onboarding funnel = one-time per player (we also dedupe in memory to save rate limit).
-- Never log money from Admin / Dev commands.

local AnalyticsService = game:GetService("AnalyticsService")

local Validate = require(script.Parent.Validate)

local Analytics = {}

local CURRENCY = "Cash"

-- EconomyService reason -> Roblox transaction type (Roblox's own names keep the dashboard tidy).
local SOURCE_TYPE = {
	Sale = "Shop", -- a customer or quick-sell paid the player
	Dispose = "Shop",
	LevelUp = "Gameplay",
	Bonus = "Gameplay", -- first-find bonus
	Like = "Gameplay", -- a visitor liked the shop
	Refund = "Gameplay", -- a failed purchase handed back
}
local SILENT_REASON = { Admin = true, Dev = true } -- test / admin money is not real player behaviour

-- Onboarding steps, in order (each is logged once per player). The funnel answers "where do new players stop?".
Analytics.STEP = {
	Joined = 1, -- the save loaded
	OpenedBox = 2,
	RestoredItem = 3,
	DisplayedItem = 4,
	FirstSale = 5,
	BoughtSkin = 6,
	BoughtUpgrade = 7,
}
local STEP_NAME = {}
for name, number in Analytics.STEP do
	STEP_NAME[number] = name
end

local seenSteps: { [any]: { [number]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Analytics] " .. tostring(err))
	end
end

-- Cash gained. `reason` is EconomyService's reason string ("Sale", "LevelUp", ...). endingBalance = cash AFTER the change.
function Analytics.CashIn(player: any, amount: number, endingBalance: number, reason: string?)
	if not Validate.isPlayer(player) or type(amount) ~= "number" or amount <= 0 or (reason and SILENT_REASON[reason]) then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			CURRENCY,
			amount,
			endingBalance,
			SOURCE_TYPE[reason or ""] or "Gameplay",
			reason
		)
	end)
end

-- Cash spent. `sku` = what was bought (crate id, skin id, upgrade id).
function Analytics.CashOut(player: any, amount: number, endingBalance: number, transactionType: string?, sku: string?)
	if not Validate.isPlayer(player) or type(amount) ~= "number" or amount <= 0 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY,
			amount,
			endingBalance,
			transactionType or "Shop",
			sku
		)
	end)
end

-- New-player funnel step (see Analytics.STEP). Safe to call every time: only the first call per player and step goes out.
function Analytics.Step(player: any, step: number)
	if not Validate.isPlayer(player) or STEP_NAME[step] == nil then
		return
	end
	local seen = seenSteps[player]
	if seen == nil then
		seen = {}
		seenSteps[player] = seen
	end
	if seen[step] then
		return
	end
	seen[step] = true
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, STEP_NAME[step])
	end)
end

-- A counted custom event. Fields are strings; only the first three are used (CustomField01..03).
function Analytics.Event(player: any, name: string, value: number?, f1: string?, f2: string?, f3: string?)
	if not Validate.isPlayer(player) or type(name) ~= "string" then
		return
	end
	safe(function()
		local fields = {}
		if f1 then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = f1
		end
		if f2 then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = f2
		end
		if f3 then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = f3
		end
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
end

return Analytics
