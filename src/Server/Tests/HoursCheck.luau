-- HoursCheck.luau (ServerScriptService.Server.Tests.HoursCheck)
-- Purpose: tests Shared.Hours (the game clock and opening hours) and the HoursService refresh. Pure: fake hours are passed in.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.HoursCheck).run()   Also part of DevTools testAll.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Hours = require(ReplicatedStorage.Shared.Hours)

local HoursCheck = {}

function HoursCheck.run()
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
	local function near(a: number, b: number): boolean
		return math.abs(a - b) < 1e-6
	end

	-- the game clock follows DayNight.SEGMENTS (Dawn 5-7.5 in 100 s, Day to 15.5 in 500 s, GoldenHour to 18.5 in 250 s, Night to 29 in 350 s)
	local cycle = Hours.CYCLE_SECONDS
	check("clock: a full cycle is 1200 s (config pacing)", cycle == 1200, cycle)
	check("clock: cycle start is 5:00 (dawn)", near(Hours.hourAt(0), 5))
	check("clock: dawn ends at 7:30 after 100 s", near(Hours.hourAt(100), 7.5))
	check("clock: midday after 350 s is 11:30", near(Hours.hourAt(350), 11.5))
	check("clock: golden hour begins at 3:30 PM after 600 s", near(Hours.hourAt(600), 15.5))
	check("clock: sunset is slow and around 5 PM (725 s in is 5:00 PM)", near(Hours.hourAt(725), 17.0))
	check("clock: night starts at 6:30 PM after 850 s", near(Hours.hourAt(850), 18.5))
	check("clock: it wraps past midnight (about 21 s later is after 18:30)", Hours.hourAt(1000) > 22 or Hours.hourAt(1000) < 3)
	check("clock: the cycle repeats", near(Hours.hourAt(77), Hours.hourAt(77 + cycle)))
	check("clock: the game day number changes every cycle", Hours.dayAt(cycle - 1) == 0 and Hours.dayAt(cycle) == 1)
	check("time: format 6:15 PM / 12:00 AM / 7:00 AM", Hours.format(18.25) == "6:15 PM" and Hours.format(0) == "12:00 AM" and Hours.format(7) == "7:00 AM")
	local closedSeconds = 0
	for s = 0, cycle - 1 do
		if not Hours.marketOpen(Hours.hourAt(s)) then
			closedSeconds += 1
		end
	end
	check("clock: the market is closed for a reasonable part of each cycle (20-45%)", closedSeconds > cycle * 0.2 and closedSeconds < cycle * 0.45, closedSeconds)

	check("market: closed before 7:00, open at 7:00", not Hours.marketOpen(6.99) and Hours.marketOpen(7.0))
	check("market: open at 6:14 PM, closed at 6:15 PM", Hours.marketOpen(18.24) and not Hours.marketOpen(18.25))
	check("market: closed all night (11 PM, 3 AM)", not Hours.marketOpen(23) and not Hours.marketOpen(3))
	check("shop: open at 7:00 AM and 6:59 PM, closed at 7:00 PM", Hours.shopOpen(7.0) and Hours.shopOpen(18.99) and not Hours.shopOpen(19.0))
	check("shop: closed at 2 AM", not Hours.shopOpen(2))

	local tagged = #CollectionService:GetTagged("MarketPrompt")
	check("studio: five market prompts are tagged MarketPrompt (Studio-only tags)", tagged == 5, tagged)
	local Service = require(ServerScriptService.Server.Services.HoursService)
	local keep = workspace:GetAttribute("PHHourOverride")
	workspace:SetAttribute("PHHourOverride", 22)
	Service.Refresh()
	local allOff = true
	for _, p in CollectionService:GetTagged("MarketPrompt") do
		if (p :: ProximityPrompt).Enabled then
			allOff = false
		end
	end
	check("service: at 10 PM the market prompts are off and MarketOpen is false", allOff and workspace:GetAttribute("MarketOpen") == false and workspace:GetAttribute("ShopOpen") == false)
	workspace:SetAttribute("PHHourOverride", 10)
	Service.Refresh()
	local allOn = true
	for _, p in CollectionService:GetTagged("MarketPrompt") do
		if not (p :: ProximityPrompt).Enabled then
			allOn = false
		end
	end
	check("service: at 10 AM the prompts are back on and both are open", allOn and workspace:GetAttribute("MarketOpen") == true and workspace:GetAttribute("ShopOpen") == true)
	workspace:SetAttribute("PHHourOverride", keep)
	Service.Refresh()

	-- shop shutters: one per shop, only that shop's owner passes (collision groups), and the "inside the shop" test
	local PhysicsService = game:GetService("PhysicsService")
	local plots = workspace:FindFirstChild("Plots")
	local shutterCount, okGroups, okInside = 0, true, true
	for _, plot in if plots then plots:GetChildren() else {} do
		local shutter = plot:FindFirstChild("ShopShutter") :: BasePart?
		local index = tonumber(string.match(plot.Name, "^Plot(%d+)$"))
		if shutter and index then
			shutterCount += 1
			local g = shutter.CollisionGroup
			local other = if index == 1 then 2 else 1
			okGroups = okGroups
				and g == "ShopShutter" .. index
				and PhysicsService:CollisionGroupsAreCollidable(g, "Default")
				and PhysicsService:CollisionGroupsAreCollidable(g, "VipMember")
				and PhysicsService:CollisionGroupsAreCollidable(g, "ShopOwner" .. other)
				and not PhysicsService:CollisionGroupsAreCollidable(g, "ShopOwner" .. index)
				and not PhysicsService:CollisionGroupsAreCollidable(g, "VipOwner" .. index)
				and not PhysicsService:CollisionGroupsAreCollidable("VipGate", "VipOwner" .. index)
			local door = plot.CustomerPath.Door.Position
			local out = ((plot.CustomerPath.Approach.Position - door) * Vector3.new(1, 0, 1)).Unit
			okInside = okInside
				and Service.IsInsideShop(plot, door - out * 6 + Vector3.new(0, 3, 0))
				and not Service.IsInsideShop(plot, door + out * 6 + Vector3.new(0, 3, 0))
				and not Service.IsInsideShop(plot, door - out * 6 + Vector3.new(0, 3, 0) + out:Cross(Vector3.yAxis) * 60)
		end
	end
	check("shutters: all six shops have a door shutter (built at start)", shutterCount == 6, shutterCount)
	check("shutters: a shutter blocks everyone but that shop's owner (also a VIP owner, who still passes the VIP gate)", okGroups)
	check("shutters: inside-the-shop test: inside yes, street no, next door no", okInside)
	local marketShutter = workspace:FindFirstChild("MarketShutter") :: BasePart?
	check("market door: the Warehouse Market has a front-door shutter in Workspace", marketShutter ~= nil and marketShutter.Size.X > 10)
	check("market door: inside the hall yes, the street and next to the hall no", Service.IsInsideMarket(Vector3.new(-50, 7, 240)) and not Service.IsInsideMarket(Vector3.new(-50, 7, 195)) and not Service.IsInsideMarket(Vector3.new(60, 7, 240)))

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[HoursCheck]", line)
		end
	end
	print(`[HoursCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return HoursCheck
