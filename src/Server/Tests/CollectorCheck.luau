-- CollectorCheck.luau (ServerScriptService.Server.Tests.CollectorCheck)
-- Purpose: tests the collector score formula, the tiers and CollectorService.Refresh (docs/12 Stage 4). Pure: a COPY of the
-- service with fake DataService / CollectionBookService and a fake player; never touches a real profile.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.CollectorCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CollectorCheck = {}

function CollectorCheck.run()
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

	local Settings = require(ReplicatedStorage.Shared.Config.Collector)
	local Collector = require(ReplicatedStorage.Shared.Collector)
	local Items = require(ReplicatedStorage.Shared.Config.Items)

	-- ===== config =====
	local tiersOk, ascending = #Settings.TIERS >= 2 and Settings.TIERS[1].min == 0 and Settings.TIERS[1].color == nil, true
	for i = 2, #Settings.TIERS do
		local t = Settings.TIERS[i]
		if t.min <= Settings.TIERS[i - 1].min or typeof(t.color) ~= "Color3" or type(t.rate) ~= "number" or type(t.light) ~= "number" then
			ascending = false
		end
	end
	check("config: the first tier starts at 0 and has no aura", tiersOk)
	check("config: tiers go up and every aura tier has a colour, rate and light", ascending)
	local allRarities = true
	for _, def in Items do
		if type(def) == "table" and def.rarity and Settings.RarityPoints[def.rarity] == nil then
			allRarities = false
		end
	end
	check("config: every item rarity has points", allRarities)

	-- ===== score =====
	local firstCommon, firstRare
	for id, def in Items do
		if type(def) == "table" and def.rarity == "Common" and not firstCommon then
			firstCommon = id
		end
		if type(def) == "table" and def.rarity == "Rare" and not firstRare then
			firstRare = id
		end
	end
	check("score: an empty book and no rating scores 0", Collector.score({}, 0) == 0 and Collector.score(nil, nil) == 0)
	check("score: found Common, no stars = its points (1)", Collector.score({ [firstCommon] = { found = true, bestStars = 0, golden = false } }, 0) == Settings.RarityPoints.Common)
	check("score: 3 restore stars = x2.5", Collector.score({ [firstRare] = { found = true, bestStars = 3, golden = false } }, 0) == math.floor(Settings.RarityPoints.Rare * 2.5 + 0.5))
	check("score: golden counts 1.5x", Collector.score({ [firstRare] = { found = true, bestStars = 0, golden = true } }, 0) == math.floor(Settings.RarityPoints.Rare * 1.5 + 0.5))
	check("score: each rating star adds 20", Collector.score({}, 3) == 3 * Settings.RatingStarPoints and Collector.score({}, 9) == 5 * Settings.RatingStarPoints)
	check("score: unknown items and garbage entries add nothing", Collector.score({ NotAnItem = { found = true }, [firstCommon] = "x" }, 0) == 0)
	check("score: a better restore never lowers the score", Collector.score({ [firstRare] = { bestStars = 3 } }, 0) > Collector.score({ [firstRare] = { bestStars = 1 } }, 0))
	local everything = {}
	for id, def in Items do
		if type(def) == "table" and def.rarity then
			everything[id] = { found = true, bestStars = 3, golden = true }
		end
	end
	local top = Collector.score(everything, 5)
	check("score: owning everything perfectly reaches the top tier", select(2, Collector.tier(top)) == #Settings.TIERS, top)

	-- ===== tiers =====
	local t0, n0, next0 = Collector.tier(0)
	check("tier: 0 points is the first tier and the next one is its min away", n0 == 1 and t0.id == "Dusty" and next0 == Settings.TIERS[2].min)
	check("tier: exactly the minimum reaches the tier", select(2, Collector.tier(Settings.TIERS[3].min)) == 3 and select(2, Collector.tier(Settings.TIERS[3].min - 1)) == 2)
	local _, nTop, nextTop = Collector.tier(1e9)
	check("tier: the top tier has no next tier", nTop == #Settings.TIERS and nextTop == nil)

	-- ===== service on a copy with fakes =====
	local kit = Instance.new("Folder")
	kit.Name = "CollectorCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local copy = ServerScriptService.Server.Services.CollectorService:Clone()
	copy.Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local data = { collection = {} }
		local stars = 0
		local fakeDS = {
			GetValue = function(_, path)
				return data[path]
			end,
		}
		local fakeBook = {
			GetRatingStars = function()
				return stars
			end,
		}
		local Service = require(copy)
		Service.Init({ DataService = fakeDS, CollectionBookService = fakeBook })
		local mock = { Name = "CollectorMock", UserId = 4242 } -- not a real Player: attributes are skipped, the maths still returns
		local score, tier = Service.Refresh(mock, true)
		check("service: an empty book is score 0, tier 1", score == 0 and tier == 1)
		data.collection[firstRare] = { found = true, bestStars = 3, golden = true }
		stars = 5
		local score2, tier2 = Service.Refresh(mock, false)
		check("service: the score follows the data and the rating", score2 == Collector.score(data.collection, 5) and tier2 == select(2, Collector.tier(score2)))
		data.collection = nil
		local score3 = Service.Refresh(mock, true)
		check("service: a profile with no collection yet is skipped safely", score3 == nil)
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[CollectorCheck]", line)
		end
	end
	print(`[CollectorCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return CollectorCheck
