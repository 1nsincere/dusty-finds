-- FormulasCheck.luau (ReplicatedStorage.Shared.Tests.FormulasCheck)
-- Purpose: tests every function in Formulas (at least 5 cases each, including edge cases). One PASS/FAIL line per case.
-- Owner: Dev 1 (Ace). Depends on: Formulas.
-- Run in the Studio command bar (Edit mode): require(game.ReplicatedStorage.Shared.Tests.FormulasCheck).run()
-- Expected values are worked out BY HAND from docs/02_Economy.md, not read from Config, so a wrong Config number
-- or a wrong formula both show up as a FAIL.

local Formulas = require(script.Parent.Parent:WaitForChild("Formulas"))

local FormulasCheck = {}

function FormulasCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0

	local function expectEqual(name: string, actual: any, expected: any)
		if actual == expected then
			passCount += 1
			table.insert(lines, `PASS {name} = {tostring(actual)}`)
		else
			failCount += 1
			table.insert(lines, `FAIL {name}: expected {tostring(expected)}, got {tostring(actual)}`)
		end
	end

	local NaN = 0 / 0
	local sell, quick, quality, xp, rating =
		Formulas.sellPrice, Formulas.quickSellPrice, Formulas.qualityStars, Formulas.xpToNext, Formulas.ratingStars

	-- ===== sellPrice(itemId, stars, golden, wishMatch) = base x quality x variant x wish, rounded =====
	expectEqual("sellPrice ToyCar 3 stars (doc example, ~$21)", sell("ToyCar", 3, false, false), 21) -- 16 x 1.3 = 20.8
	expectEqual("sellPrice RubberDuck 2 stars (doc example, $12)", sell("RubberDuck", 2, false, false), 12)
	expectEqual("sellPrice RubberDuck 1 star", sell("RubberDuck", 1, false, false), 10) -- 12 x 0.8 = 9.6
	expectEqual("sellPrice RubberDuck 3 stars", sell("RubberDuck", 3, false, false), 16) -- 12 x 1.3 = 15.6
	expectEqual("sellPrice Gramophone 2 stars", sell("Gramophone", 2, false, false), 450)
	expectEqual("sellPrice Jukebox 3 stars", sell("Jukebox", 3, false, false), 2925) -- 2250 x 1.3
	expectEqual("sellPrice Golden Gramophone 2 stars is exactly 3x normal", sell("Gramophone", 2, true, false), 1350)
	expectEqual("sellPrice Golden ToyCar 3 stars", sell("ToyCar", 3, true, false), 62) -- 16 x 1.3 x 3 = 62.4
	expectEqual("sellPrice wish match RubberDuck 2 stars", sell("RubberDuck", 2, false, true), 15) -- 12 x 1.25
	expectEqual("sellPrice Golden + wish RubberDuck 2 stars", sell("RubberDuck", 2, true, true), 45) -- 12 x 3 x 1.25
	expectEqual("sellPrice golden nil counts as normal", sell("RubberDuck", 2, nil, nil), 12)
	expectEqual("sellPrice stars 0 counts as 1 star", sell("RubberDuck", 0, false, false), 10)
	expectEqual("sellPrice negative stars count as 1 star", sell("RubberDuck", -3, false, false), 10)
	expectEqual("sellPrice stars above 3 count as 3", sell("RubberDuck", 7, false, false), 16)
	expectEqual("sellPrice missing stars counts as 1 star", sell("RubberDuck", nil :: any, false, false), 10)
	expectEqual("sellPrice NaN stars counts as 1 star", sell("RubberDuck", NaN, false, false), 10)
	expectEqual("sellPrice 2.9 stars rounds down to 2 stars", sell("RubberDuck", 2.9, false, false), 12)
	expectEqual("sellPrice unknown item is 0", sell("NotAnItem", 2, false, false), 0)
	expectEqual("sellPrice missing item is 0", sell(nil :: any, 2, false, false), 0)
	expectEqual("sellPrice wrong item type is 0", sell(5 :: any, 2, false, false), 0)

	-- ===== quickSellPrice(itemId, stars, golden) = 70% of base x quality x variant, rounded =====
	expectEqual("quickSell RubberDuck 2 stars", quick("RubberDuck", 2, false), 8) -- 8.4
	expectEqual("quickSell ToyCar 3 stars", quick("ToyCar", 3, false), 15) -- 14.56
	expectEqual("quickSell Gramophone 2 stars", quick("Gramophone", 2, false), 315) -- 450 x 0.7
	expectEqual("quickSell Golden RubberDuck 2 stars", quick("RubberDuck", 2, true), 25) -- 25.2
	expectEqual("quickSell RubberDuck missing stars counts as 1 star", quick("RubberDuck", nil :: any, false), 7) -- 6.72
	expectEqual("quickSell Jukebox 3 stars", quick("Jukebox", 3, false), 2048) -- 2925 x 0.7 = 2047.5
	expectEqual("quickSell unknown item is 0", quick("NotAnItem", 3, false), 0)
	expectEqual("quickSell ignores wish (is below the normal price)", quick("Gramophone", 2, false) < sell("Gramophone", 2, false, false), true)
	expectEqual("quickSell negative stars count as 1 star", quick("RubberDuck", -1, false), 7)

	-- ===== qualityStars(averageScore, toolBonus): >=90 -> 3, >=70 -> 2, else 1; bonus 0-10 =====
	expectEqual("qualityStars 100", quality(100, 0), 3)
	expectEqual("qualityStars 90 is 3 stars", quality(90, 0), 3)
	expectEqual("qualityStars 89.9 is 2 stars", quality(89.9, 0), 2)
	expectEqual("qualityStars 70 is 2 stars", quality(70, 0), 2)
	expectEqual("qualityStars 69.9 is 1 star", quality(69.9, 0), 1)
	expectEqual("qualityStars 0 is 1 star", quality(0, 0), 1)
	expectEqual("qualityStars 85 + bonus 5 reaches 3 stars", quality(85, 5), 3)
	expectEqual("qualityStars 65 + bonus 5 reaches 2 stars", quality(65, 5), 2)
	expectEqual("qualityStars 59 + bonus 10 is still 1 star", quality(59, 10), 1)
	expectEqual("qualityStars bonus is capped at 10 (80 + 50 -> 90)", quality(80, 50), 3)
	expectEqual("qualityStars bonus cap really is 10 (79 + 50 -> 89)", quality(79, 50), 2)
	expectEqual("qualityStars negative bonus counts as 0", quality(95, -10), 3)
	expectEqual("qualityStars negative score counts as 0", quality(-50, 0), 1)
	expectEqual("qualityStars score above 100 counts as 100", quality(250, 0), 3)
	expectEqual("qualityStars missing score is 1 star", quality(nil :: any, nil), 1)
	expectEqual("qualityStars missing bonus counts as 0", quality(90, nil), 3)
	expectEqual("qualityStars NaN score is 1 star", quality(NaN, 0), 1)

	-- ===== xpToNext(level) = round(40 x level^1.6); at the level cap (15) nothing more is needed =====
	expectEqual("xpToNext level 1", xp(1), 40)
	expectEqual("xpToNext level 2", xp(2), 121) -- 40 x 3.0314
	expectEqual("xpToNext level 3", xp(3), 232) -- 40 x 5.7995
	expectEqual("xpToNext level 4", xp(4), 368) -- 40 x 9.1896
	expectEqual("xpToNext level 5", xp(5), 525) -- 40 x 13.1326
	expectEqual("xpToNext level 10", xp(10), 1592) -- 40 x 39.8107
	expectEqual("xpToNext level 14", xp(14), 2728)
	expectEqual("xpToNext level 15 (cap) is infinite", xp(15), math.huge)
	expectEqual("xpToNext level 16 (above cap) is infinite", xp(16), math.huge)
	expectEqual("xpToNext level 0 counts as level 1", xp(0), 40)
	expectEqual("xpToNext negative level counts as level 1", xp(-4), 40)
	expectEqual("xpToNext missing level counts as level 1", xp(nil :: any), 40)
	expectEqual("xpToNext NaN counts as level 1", xp(NaN), 40)
	expectEqual("xpToNext 1.9 rounds down to level 1", xp(1.9), 40)
	-- Cumulative XP, worked out separately (sum of the rounded per-level values above)
	local function cumulative(toLevel: number): number
		local sum = 0
		for level = 1, toLevel - 1 do
			sum += xp(level)
		end
		return sum
	end
	expectEqual("cumulative XP to reach level 5 (doc says ~760)", cumulative(5), 761)
	expectEqual("cumulative XP to reach level 10 (doc says ~5,350)", cumulative(10), 5348)
	expectEqual("cumulative XP to reach level 15 (doc says ~16,100)", cumulative(15), 16078)

	-- ===== ratingStars(points): 1 star 0, 2 stars 8, 3 stars 20, 4 stars 40, 5 stars 65 =====
	expectEqual("ratingStars 0 points", rating(0), 1)
	expectEqual("ratingStars 7 points", rating(7), 1)
	expectEqual("ratingStars 8 points", rating(8), 2)
	expectEqual("ratingStars 19 points", rating(19), 2)
	expectEqual("ratingStars 20 points", rating(20), 3)
	expectEqual("ratingStars 39 points", rating(39), 3)
	expectEqual("ratingStars 40 points", rating(40), 4)
	expectEqual("ratingStars 64 points", rating(64), 4)
	expectEqual("ratingStars 65 points", rating(65), 5)
	expectEqual("ratingStars 1000 points", rating(1000), 5)
	expectEqual("ratingStars 7.9 points", rating(7.9), 1)
	expectEqual("ratingStars negative points", rating(-5), 1)
	expectEqual("ratingStars missing points", rating(nil :: any), 1)
	expectEqual("ratingStars NaN points", rating(NaN), 1)

	-- ===== customer helpers (docs/02 §5): worked out by hand =====
	local function r3(x: number): number -- 3 decimals, so 0.30000000000000004 compares equal to 0.3
		return math.floor(x * 1000 + 0.5) / 1000
	end
	local tipChance, tipAmount, checkoutBonus, spawnInterval =
		Formulas.tipChance, Formulas.tipAmount, Formulas.checkoutBonus, Formulas.customerSpawnInterval

	-- inventoryCapacity: 8 -> 16 -> 24 -> 40, bad input = starting capacity
	expectEqual("inventoryCapacity 0", Formulas.inventoryCapacity(0), 8)
	expectEqual("inventoryCapacity 1", Formulas.inventoryCapacity(1), 16)
	expectEqual("inventoryCapacity 2", Formulas.inventoryCapacity(2), 24)
	expectEqual("inventoryCapacity 3", Formulas.inventoryCapacity(3), 40)
	expectEqual("inventoryCapacity 9 (beyond max) falls back", Formulas.inventoryCapacity(9), 8)
	expectEqual("inventoryCapacity nil-ish input", Formulas.inventoryCapacity(0/0), 8)

	-- tipChance = 5% + 5% x rating stars (+ customer bonus), clamped 0-1
	expectEqual("tipChance 1 star", r3(tipChance(1)), 0.1)
	expectEqual("tipChance 3 stars", r3(tipChance(3)), 0.2)
	expectEqual("tipChance 5 stars", r3(tipChance(5)), 0.3)
	expectEqual("tipChance 5 stars + Collector bonus 0.05", r3(tipChance(5, 0.05)), 0.35)
	expectEqual("tipChance 0 stars counts as 1 star", r3(tipChance(0)), 0.1)
	expectEqual("tipChance 9 stars counts as 5 stars", r3(tipChance(9)), 0.3)
	expectEqual("tipChance missing stars counts as 1 star", r3(tipChance(nil :: any)), 0.1)
	expectEqual("tipChance NaN stars counts as 1 star", r3(tipChance(NaN)), 0.1)
	expectEqual("tipChance huge bonus is capped at 1", tipChance(3, 5), 1)
	expectEqual("tipChance negative bonus is floored at 0", tipChance(1, -5), 0)

	-- tipAmount = round(price x fraction), fraction clamped to 10%-25%
	expectEqual("tipAmount $100 at 10%", tipAmount(100, 0.1), 10)
	expectEqual("tipAmount $100 at 25%", tipAmount(100, 0.25), 25)
	expectEqual("tipAmount fraction above 25% is capped", tipAmount(100, 0.5), 25)
	expectEqual("tipAmount fraction below 10% is raised", tipAmount(100, 0.01), 10)
	expectEqual("tipAmount $21 at 10% (2.1) rounds to 2", tipAmount(21, 0.1), 2)
	expectEqual("tipAmount $15 at 25% (3.75) rounds to 4", tipAmount(15, 0.25), 4)
	expectEqual("tipAmount price 0", tipAmount(0, 0.2), 0)
	expectEqual("tipAmount negative price", tipAmount(-50, 0.2), 0)
	expectEqual("tipAmount NaN fraction uses 10%", tipAmount(100, NaN), 10)

	-- checkoutBonus = round(10% of price)
	expectEqual("checkoutBonus $100", checkoutBonus(100), 10)
	expectEqual("checkoutBonus $21 (2.1) rounds to 2", checkoutBonus(21), 2)
	expectEqual("checkoutBonus $25 (2.5) rounds up to 3", checkoutBonus(25), 3)
	expectEqual("checkoutBonus price 0", checkoutBonus(0), 0)
	expectEqual("checkoutBonus negative price", checkoutBonus(-5), 0)
	expectEqual("checkoutBonus NaN price", checkoutBonus(NaN), 0)

	-- customerSpawnInterval = 30 x 0.9^sign x ratingMult (1.0, 0.9, 0.8, 0.7, 0.6), minimum 10 s
	expectEqual("spawn interval sign 0, 1 star", r3(spawnInterval(0, 1)), 30)
	expectEqual("spawn interval sign 1, 1 star", r3(spawnInterval(1, 1)), 27)
	expectEqual("spawn interval sign 0, 5 stars", r3(spawnInterval(0, 5)), 18)
	expectEqual("spawn interval sign 3, 1 star", r3(spawnInterval(3, 1)), 21.87)
	expectEqual("spawn interval sign 3, 5 stars", r3(spawnInterval(3, 5)), 13.122)
	expectEqual("spawn interval 9 stars counts as 5", r3(spawnInterval(3, 9)), 13.122)
	expectEqual("spawn interval negative sign counts as 0", r3(spawnInterval(-2, 1)), 30)
	expectEqual("spawn interval never below 10 s", spawnInterval(40, 5), 10)
	expectEqual("spawn interval NaN sign counts as 0", r3(spawnInterval(NaN, 1)), 30)

	for _, line in lines do
		print(line)
	end
	print(`[FormulasCheck] {passCount} passed, {failCount} failed`)
	return passCount, failCount, table.concat(lines, "\n") .. `\n[FormulasCheck] {passCount} passed, {failCount} failed`
end

return FormulasCheck
