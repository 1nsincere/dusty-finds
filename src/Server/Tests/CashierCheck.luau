-- CashierCheck.luau (ServerScriptService.Server.Tests.CashierCheck)
-- Purpose: tests the till rules: CashierService.Judge (fast bonus, normal bonus, upset after a mistake, angry penalty)
-- and the Config numbers behind them. Pure: no data, no players, never touches a profile.
-- Owner: Dev 3 (Sean). Depends on: Services.CashierService (Judge), Shared.Config.Economy.
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.CashierCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashierCheck = {}

function CashierCheck.run()
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

	local Economy = require(ReplicatedStorage.Shared.Config.Economy)
	local CashierService = require(script.Parent.Parent.Services.CashierService)
	local Judge = CashierService.Judge

	-- ===== Config sanity =====
	check("bills are 1, 5, 10, 20, 50", table.concat(Economy.CashierBills, ",") == "1,5,10,20,50")
	check("fast bonus (+25%) is bigger than the normal checkout bonus (+10%)", Economy.CashierFastBonusFraction > Economy.CheckoutBonusFraction)
	check("fast window is a few seconds", Economy.CashierFastSeconds >= 3 and Economy.CashierFastSeconds <= 20)
	check("angry penalty is negative and small", Economy.CashierAngryPenaltyFraction < 0 and Economy.CashierAngryPenaltyFraction >= -0.5)
	check("at least 2 mistakes before angry", Economy.CashierMaxMistakes >= 2)

	-- ===== Right change =====
	local fast = Judge(true, 0, Economy.CashierFastSeconds - 1)
	check("right + fast, first try = done, fast bonus, Delighted", fast.done and fast.fraction == Economy.CashierFastBonusFraction and fast.mood == "Delighted", fast.mood)
	local edge = Judge(true, 0, Economy.CashierFastSeconds)
	check("right at exactly the fast limit still counts as fast", edge.mood == "Delighted")
	local slow = Judge(true, 0, Economy.CashierFastSeconds + 0.5)
	check("right but slow, first try = done, +10%, Happy", slow.done and slow.fraction == Economy.CheckoutBonusFraction and slow.mood == "Happy", slow.fraction)
	local late = Judge(true, 1, 1)
	check("right after a mistake (even fast) = done, no bonus, Upset", late.done and late.fraction == 0 and late.mood == "Upset" and late.attempts == 1)

	-- ===== Wrong change =====
	local wrong1 = Judge(false, 0, 2)
	check("first wrong = not done, Upset, 1 mistake, no fraction", not wrong1.done and wrong1.mood == "Upset" and wrong1.attempts == 1 and wrong1.fraction == nil)
	local wrongLast = Judge(false, Economy.CashierMaxMistakes - 1, 5)
	check("the last allowed wrong = done, penalty, Angry", wrongLast.done and wrongLast.fraction == Economy.CashierAngryPenaltyFraction and wrongLast.mood == "Angry" and wrongLast.attempts == Economy.CashierMaxMistakes)
	local wrongSlow = Judge(false, 0, 999)
	check("being slow never makes a wrong answer right", not wrongSlow.done or wrongSlow.mood == "Angry")

	-- ===== What a sale pays with each result (price $40, the same rounding InventoryService.CompleteSale uses) =====
	local function bonusOn(price: number, fraction: number): number
		return math.floor(price * math.clamp(fraction, -0.5, 0.5) + 0.5)
	end
	check("$40 fast = +$10", bonusOn(40, fast.fraction) == 10, bonusOn(40, fast.fraction))
	check("$40 right = +$4", bonusOn(40, slow.fraction) == 4, bonusOn(40, slow.fraction))
	check("$40 upset = +$0", bonusOn(40, late.fraction) == 0)
	check("$40 angry = -$4 (pays $36)", bonusOn(40, wrongLast.fraction) == -4, bonusOn(40, wrongLast.fraction))

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[CashierCheck]", line)
		end
	end
	print(`[CashierCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return CashierCheck
