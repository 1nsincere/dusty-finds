-- CashierService.luau
-- Purpose: the till. When the shop owner serves the customer at the counter, the server works out the bill, the
-- customer pays with a rounder amount, and the owner must count out the right change (RequestGiveChange). Right change
-- completes the sale through CustomerService.Checkout; the bonus comes from CashierService.Judge (Dev 3, 2026-11-23):
-- right + fast (first try, within Economy.CashierFastSeconds) = +25%, right first try = +10%, right after a mistake = no
-- bonus (customer upset); the CashierMaxMistakes-th wrong change = the customer gets angry, pays 10% less and leaves.
-- Owner: Dev 1 (Ace), speed/mistake rules Dev 3 (Sean). Depends on: CustomerService (GetCustomers, Checkout),
-- InventoryService.Get, PlotService.GetPlot, CustomerNpcService.SetCashierState (optional, mood bubbles),
-- Shared.Formulas.sellPrice, Shared.Config.Economy (Cashier*), Shared.Config.Items, Remotes RequestGiveChange /
-- RequestCloseCashier / CashierUpdate / Notify, Lib/Validate.
-- CustomerNpcService calls Open() from the counter prompt and IsOpenFor() while the customer waits (no auto-checkout
-- while the owner is at the till for that customer). The client never decides any money: it only sends a count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Economy = require(Shared.Config:WaitForChild("Economy"))
local Items = require(Shared.Config:WaitForChild("Items"))
local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)

local CashierService = {}
local DEBUG = true
local log = Log.new("CashierService", DEBUG)

local CustomerService, InventoryService, PlotService, CustomerNpcService

type Till = { customerId: string, due: number, paid: number, attempts: number, itemName: string, openedAt: number }
local TILL_TIMEOUT = 60 -- seconds a till may stay open before it closes by itself
local tills: { [Player]: Till } = {}
local random = Random.new()

-- The till rules in one pure function (tested by Tests/CashierCheck). `attempts` = wrong hand-overs before this one,
-- `seconds` = since the till opened (server clock). Returns:
--   done      true = the sale happens now; false = wrong change, the customer waits for another try
--   fraction  bonus fraction for CustomerService.Checkout (only when done; negative = pays less)
--   mood      "Delighted" | "Happy" | "Upset" | "Angry" (bubble over the customer)
--   attempts  the wrong count after this hand-over
function CashierService.Judge(isRight: boolean, attempts: number, seconds: number): { [string]: any }
	if isRight then
		if attempts == 0 and seconds <= Economy.CashierFastSeconds then
			return { done = true, fraction = Economy.CashierFastBonusFraction, mood = "Delighted", attempts = 0 }
		elseif attempts == 0 then
			return { done = true, fraction = Economy.CheckoutBonusFraction, mood = "Happy", attempts = 0 }
		end
		return { done = true, fraction = 0, mood = "Upset", attempts = attempts }
	end
	local wrongs = attempts + 1
	if wrongs >= Economy.CashierMaxMistakes then
		return { done = true, fraction = Economy.CashierAngryPenaltyFraction, mood = "Angry", attempts = wrongs }
	end
	return { done = false, fraction = nil, mood = "Upset", attempts = wrongs }
end

local function percent(fraction: number): number
	return math.floor(math.abs(fraction) * 100 + 0.5)
end

-- Mood bubble / "Here's $X" bubble over the customer (CustomerNpcService owns the NPC models). Optional: no NPC service = no bubble.
local function npcState(customerId: string, paid: number?, mood: string?)
	if CustomerNpcService and CustomerNpcService.SetCashierState then
		CustomerNpcService.SetCashierState(customerId, paid, mood)
	end
end

-- What the customer hands over: the price rounded UP to a 5 / 10 / 20 / 50 / 100 (always more than the price), picked
-- at random among the sensible options so the change is never trivially zero.
local function pickPayment(due: number): number
	local options = {}
	for _, step in Economy.CashierPayRoundTo do
		local paid = math.ceil(due / step) * step
		if paid <= due then
			paid += step
		end
		if paid - due <= math.max(100, due) and not table.find(options, paid) then -- no absurd $100 for a $3 item
			table.insert(options, paid)
		end
	end
	if #options == 0 then
		return due + 5
	end
	return options[random:NextInteger(1, #options)]
end

-- `extra` (optional): mood and bonusPercent for "done" (bonusPercent is negative for an angry customer).
local function send(player: Player, state: string, till: Till?, extra: { [string]: any }?)
	if Validate.isPlayer(player) then
		Remotes.CashierUpdate:FireClient(player, {
			state = state,
			due = till and till.due,
			paid = till and till.paid,
			item = till and till.itemName,
			attempts = till and till.attempts,
			bills = Economy.CashierBills,
			fastSeconds = Economy.CashierFastSeconds,
			fastPercent = percent(Economy.CashierFastBonusFraction),
			maxMistakes = Economy.CashierMaxMistakes,
			mood = extra and extra.mood,
			bonusPercent = extra and extra.bonusPercent,
		})
	end
end

-- True while the owner has the till open for this customer (CustomerNpcService holds auto-checkout meanwhile).
function CashierService.IsOpenFor(player: Player, customerId: string): boolean
	local till = tills[player]
	if till and os.clock() - till.openedAt > TILL_TIMEOUT then
		CashierService.Close(player) -- owner walked off: the customer goes back to the normal auto-checkout timer
		return false
	end
	return till ~= nil and till.customerId == customerId
end

-- Opens the till for the customer at the front of the queue. Returns false if that customer has nothing to pay for.
function CashierService.Open(player: Player, customerId: string): boolean
	local customer = (CustomerService.GetCustomers(player) or {})[customerId]
	local item = customer and customer.uid and InventoryService.Get(player, customer.uid)
	if not item or type(item.stars) ~= "number" then
		return false
	end
	local due = Formulas.sellPrice(item.itemId, item.stars, item.golden, customer.wishMatched)
	if due <= 0 then
		return false
	end
	local def = Items[item.itemId]
	local till = { customerId = customerId, due = due, paid = pickPayment(due), attempts = 0, itemName = def and def.name or item.itemId, openedAt = os.clock() }
	tills[player] = till
	send(player, "open", till)
	npcState(customerId, till.paid, nil)
	log.info(player.Name, "till open:", till.itemName, "due", due, "paid", till.paid)
	return true
end

-- Closes the till without selling (owner walked away / closed the window / customer left).
function CashierService.Close(player: Player, notify: boolean?)
	local till = tills[player]
	if till then
		tills[player] = nil
		npcState(till.customerId, nil, nil) -- the bubble goes back to the item; any mood stays
		if notify ~= false then
			send(player, "closed", nil)
		end
	end
end

local function giveChange(player: Player, amount: number)
	local till = tills[player]
	if not till then
		return
	end
	if not (CustomerService.GetCustomers(player) or {})[till.customerId] then
		CashierService.Close(player) -- the customer already left
		return
	end
	local verdict = CashierService.Judge(amount == till.paid - till.due, till.attempts, os.clock() - till.openedAt)
	till.attempts = verdict.attempts
	if not verdict.done then
		send(player, "wrong", till)
		npcState(till.customerId, till.paid, verdict.mood)
		local left = Economy.CashierMaxMistakes - till.attempts
		Remotes.Notify:FireClient(player, "Info", string.format("\"That's not right!\" They paid $%d for $%d. No bonus now; %d more mistake%s and they leave angry.", till.paid, till.due, left, if left == 1 then "" else "s"))
		log.info(player.Name, "wrong change", amount, "attempt", till.attempts)
		return
	end
	tills[player] = nil -- one sale per till, even if two requests arrive
	local firstTry = till.attempts == 0
	local ok, reason, result = CustomerService.Checkout(player, till.customerId, firstTry, nil, true, verdict.fraction)
	npcState(till.customerId, nil, verdict.mood)
	send(player, if ok then "done" else "closed", till, { mood = verdict.mood, bonusPercent = math.floor(verdict.fraction * 100 + 0.5) })
	if ok then
		local message
		if verdict.mood == "Delighted" then
			message = string.format("⚡ Super fast change! +%d%% bonus", percent(verdict.fraction))
		elseif verdict.mood == "Happy" then
			message = string.format("✅ Right change! +%d%% bonus", percent(verdict.fraction))
		elseif verdict.mood == "Angry" then
			message = string.format("😡 Wrong change again! The customer paid %d%% less and left angry.", percent(verdict.fraction))
		else
			message = "✅ Right change, but the customer was upset: no bonus."
		end
		Remotes.Notify:FireClient(player, "Info", message)
	end
	log.info(player.Name, "gave change", amount, "mood:", verdict.mood, "bonus:", verdict.fraction, "sale:", ok, reason or "", result and result.total or "")
end

function CashierService.Init(services)
	CustomerService = services.CustomerService
	InventoryService = services.InventoryService
	PlotService = services.PlotService
	CustomerNpcService = services.CustomerNpcService
	log.info("Init")
end

function CashierService.Start()
	Remotes.RequestGiveChange.OnServerEvent:Connect(function(player, amount)
		if not Validate.rateLimit(player, "RequestGiveChange", 4) then
			return
		end
		if not Validate.isInteger(amount, 0, Economy.CashierMaxChange) then
			return
		end
		local plot = PlotService.GetPlot(player)
		local counter = plot and plot:FindFirstChild("Counter")
		if counter == nil or not Validate.withinDistance(player, counter, Economy.InteractMaxStuds + 4) then
			return
		end
		giveChange(player, amount)
	end)
	Remotes.RequestCloseCashier.OnServerEvent:Connect(function(player)
		if Validate.rateLimit(player, "RequestCloseCashier", 4) then
			CashierService.Close(player, false)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tills[player] = nil
	end)
	log.info("Start")
end

return CashierService
