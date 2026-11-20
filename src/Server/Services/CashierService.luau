-- CashierService.luau
-- Purpose: the till. When the shop owner serves the customer at the counter, the server works out the bill, the
-- customer pays with a rounder amount, and the owner must count out the right change (RequestGiveChange). Right change
-- completes the sale through CustomerService.Checkout (first try = +checkout bonus; tips still possible); wrong change
-- = the customer complains and the owner tries again (bonus lost, never the sale).
-- Owner: Dev 1 (Ace). Depends on: CustomerService (GetCustomers, Checkout), InventoryService.Get, PlotService.GetPlot,
-- Shared.Formulas.sellPrice, Shared.Config.Economy (Cashier*), Shared.Config.Items, Remotes RequestGiveChange /
-- RequestCloseCashier / CashierUpdate, Lib/Validate.
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

local CustomerService, InventoryService, PlotService

type Till = { customerId: string, due: number, paid: number, attempts: number, itemName: string, openedAt: number }
local TILL_TIMEOUT = 60 -- seconds a till may stay open before it closes by itself
local tills: { [Player]: Till } = {}
local random = Random.new()

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

local function send(player: Player, state: string, till: Till?)
	if Validate.isPlayer(player) then
		Remotes.CashierUpdate:FireClient(player, {
			state = state,
			due = till and till.due,
			paid = till and till.paid,
			item = till and till.itemName,
			attempts = till and till.attempts,
			bills = Economy.CashierBills,
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
	log.info(player.Name, "till open:", till.itemName, "due", due, "paid", till.paid)
	return true
end

-- Closes the till without selling (owner walked away / closed the window / customer left).
function CashierService.Close(player: Player, notify: boolean?)
	if tills[player] then
		tills[player] = nil
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
	if amount ~= till.paid - till.due then
		till.attempts += 1
		send(player, "wrong", till)
		Remotes.Notify:FireClient(player, "Info", string.format("\"That's not right!\" They paid $%d for $%d.", till.paid, till.due))
		return
	end
	tills[player] = nil -- one sale per till, even if two requests arrive
	local firstTry = till.attempts == 0
	local ok, reason, result = CustomerService.Checkout(player, till.customerId, firstTry, nil, true)
	send(player, if ok then "done" else "closed", till)
	log.info(player.Name, "gave change", amount, "first try:", firstTry, "sale:", ok, reason or "", result and result.total or "")
end

function CashierService.Init(services)
	CustomerService = services.CustomerService
	InventoryService = services.InventoryService
	PlotService = services.PlotService
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
