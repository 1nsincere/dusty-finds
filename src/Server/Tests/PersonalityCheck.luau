-- PersonalityCheck.luau (ServerScriptService.Server.Tests.PersonalityCheck)
-- Purpose: tests the customer personality config and the haggle roll (CustomerService.HaggleOffer) plus Formulas.buyChance.
-- Pure: no player, no profile, no Studio objects. Owner: Dev 1 (Ace).
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.PersonalityCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PersonalityCheck = {}

function PersonalityCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0
	local function check(name: string, cond: boolean, detail: any?)
		if cond then
			passCount += 1
			table.insert(lines, "PASS " .. name)
		else
			failCount += 1
			table.insert(lines, `FAIL {name}{if detail ~= nil then " -> " .. tostring(detail) else ""}`)
		end
	end

	local Customers = require(ReplicatedStorage.Shared.Config.Customers)
	local Lines = require(ReplicatedStorage.Shared.Config.CustomerLines)
	local Economy = require(ReplicatedStorage.Shared.Config.Economy)
	local Formulas = require(ReplicatedStorage.Shared.Formulas)
	local CustomerService = require(ServerScriptService.Server.Services.CustomerService)

	-- ===== config =====
	local allHaveWeight, allHavePersonality = true, true
	for _, def in Customers do
		if type(def) ~= "table" or type(def.weight) ~= "number" then
			allHaveWeight = false -- PickType adds up every entry's weight: a non-customer entry here breaks spawning
		elseif type(def.patienceMult) ~= "number" or type(def.browseMult) ~= "number" or type(def.buyBonus) ~= "number" or type(def.haggleChance) ~= "number" then
			allHavePersonality = false
		end
	end
	check("config: every Customers entry is a customer with a weight (no stray data tables)", allHaveWeight)
	check("config: every customer type has a full personality", allHavePersonality)
	check("config: Kid never haggles", Customers.Kid.haggleChance == 0)
	check("config: a haggler has a discount range", Customers.Teen.haggleDiscount ~= nil and Customers.Teen.haggleDiscount[1] < Customers.Teen.haggleDiscount[2])
	check("config: speech lines exist for haggling", #Lines.haggle > 0 and #Lines.deal > 0 and #Lines.refused > 0 and #Lines.grumble > 0)
	local formatsOk = true
	for _, template in Lines.haggle do
		local ok = pcall(string.format, template, 15)
		formatsOk = formatsOk and ok
	end
	check("config: every haggle line takes the percent", formatsOk)
	check("config: leaving chance factor is below 1 (declining is the better bet)", Economy.HaggleLeaveFactor > 0 and Economy.HaggleLeaveFactor < 1)

	-- ===== the haggle roll =====
	check("haggle: an unknown type never haggles", CustomerService.HaggleOffer("Nobody", Random.new(1)) == nil)
	local kidAsked = false
	for seed = 1, 200 do
		if CustomerService.HaggleOffer("Kid", Random.new(seed)) ~= nil then
			kidAsked = true
		end
	end
	check("haggle: a Kid never asks", not kidAsked)
	local asked, inRange, onStep = 0, true, true
	local def = Customers.Teen
	for seed = 1, 400 do
		local ask = CustomerService.HaggleOffer("Teen", Random.new(seed))
		if ask then
			asked += 1
			if ask < def.haggleDiscount[1] - 0.026 or ask > def.haggleDiscount[2] + 0.026 then
				inRange = false
			end
			if math.abs(ask / Economy.HaggleStep - math.floor(ask / Economy.HaggleStep + 0.5)) > 1e-6 then
				onStep = false
			end
		end
	end
	check("haggle: a Teen asks about half the time", asked > 140 and asked < 260, asked)
	check("haggle: the discount stays in the type's range", inRange)
	check("haggle: discounts are whole 5% steps", onStep)

	-- ===== buy chance: rating is only a gentle factor =====
	local low, high = Formulas.buyChance(1, 2, true), Formulas.buyChance(5, 2, true)
	check("buyChance: a better shop sells more", high > low)
	check("buyChance: even a 1-star shop still sells most of the time", Formulas.buyChance(1, 2, false) >= 0.6, Formulas.buyChance(1, 2, false))
	check("buyChance: stays between 15% and 98%", Formulas.buyChance(5, 3, true, 1) <= 0.98 and Formulas.buyChance(1, 1, false, -1) >= 0.15)
	check("buyChance: an impulse bonus helps", Formulas.buyChance(3, 2, false, 0.08) > Formulas.buyChance(3, 2, false, 0))

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[PersonalityCheck]", line)
		end
	end
	print(`[PersonalityCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return PersonalityCheck
