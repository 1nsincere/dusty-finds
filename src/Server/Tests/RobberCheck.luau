-- RobberCheck.luau (ServerScriptService.Server.Tests.RobberCheck)
-- Purpose: WP8/WP9 rules without needing a night or a live robber: which nights, target weights (pedestals favoured, never the last
-- item), fee and recovery window, the server-only stolen set (expires, removed once), the breach (shutter stays solid for everyone).
-- Owner: Dev 2 (Dwayne) / Dev 1 (Ace). Depends on: Services.RobberService, Lib.StolenItems, Config.Robber, HoursService (optional).
-- Run (Play, server): require(game.ServerScriptService.Server.Tests.RobberCheck).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local RobberCheck = {}

function RobberCheck.run()
	local lines, passed, failed = {}, 0, 0
	local function check(label: string, ok: boolean, detail: any?)
		if ok then
			passed += 1
			table.insert(lines, "PASS " .. label)
		else
			failed += 1
			table.insert(lines, "FAIL " .. label .. (if detail ~= nil then ": " .. tostring(detail) else ""))
		end
	end

	local Robber = require(ReplicatedStorage.Shared.Config.Robber)
	local Hours = require(ReplicatedStorage.Shared.Hours)
	local StolenItems = require(ServerScriptService.Server.Lib.StolenItems)
	local RobberService = require(ServerScriptService.Server.Services.RobberService)

	-- config sanity
	check("robbers per night is a sane range", Robber.RobbersPerNight[1] >= 1 and Robber.RobbersPerNight[2] >= Robber.RobbersPerNight[1])
	check("a few robbers, not one (default range tops out above 1)", Robber.RobbersPerNight[2] > 1)
	check("pedestals weigh more than shelves", Robber.TargetWeights.Exhibit > Robber.TargetWeights.Display)
	check("never the last item: at least 2 stealable required", Robber.MinStealable >= 2)
	check("long recovery is longer than normal", Robber.LongRecoverySeconds > Robber.RecoverySeconds)

	-- nights: every N-th night, evening and early morning belong to the same night, daytime is none
	check("evening is night N", RobberService.NightId(Hours.SHOP_CLOSE + 1, 5) == 5)
	check("after midnight is still the previous night", RobberService.NightId(Hours.SHOP_OPEN - 1, 6) == 5)
	check("daytime has no night", RobberService.NightId(Hours.SHOP_OPEN + 1, 5) == nil)
	local robberNights = 0
	for n = 1, 10 do
		if RobberService.IsRobberNight(n) then
			robberNights += 1
		end
	end
	check("every other night is a robber night", robberNights == 10 / Robber.EveryNthNight, robberNights)

	-- eligibility: first sessions and bare shops are safe
	check("low level shops are never targeted", not RobberService.Eligible(Robber.MinLevel - 1, 10))
	check("a shop with one item is never targeted", not RobberService.Eligible(Robber.MinLevel + 5, 1))
	check("an experienced shop with items is eligible", RobberService.Eligible(Robber.MinLevel, Robber.MinStealable))

	-- weighted target: pedestal items are picked more often, an empty list gives nothing
	local list = {
		{ uid = "p", kind = "Exhibit", slot = 1, itemId = "RubberDuck" },
		{ uid = "a", kind = "Display", slot = 1, itemId = "RubberDuck" },
		{ uid = "b", kind = "Display", slot = 2, itemId = "RubberDuck" },
		{ uid = "c", kind = "Display", slot = 3, itemId = "RubberDuck" },
	}
	local rng, pedestal, picks = Random.new(7), 0, 4000
	for _ = 1, picks do
		local t = RobberService.PickTarget(list, rng)
		if t and t.uid == "p" then
			pedestal += 1
		end
	end
	local share = pedestal / picks
	local expected = Robber.TargetWeights.Exhibit / (Robber.TargetWeights.Exhibit + 3 * Robber.TargetWeights.Display)
	check("the pedestal item is taken more than a plain quarter of the time", share > 0.3, share)
	check("the pedestal share matches the weights", math.abs(share - expected) < 0.05, `{share} vs {expected}`)
	check("nothing to take gives no target", RobberService.PickTarget({}, Random.new(1)) == nil)

	-- the run: faster than walking (16) but slower than a sprint (26), so the owner must sprint; a fair warning of 8-10 s
	check("the robber flees faster than a walk and slower than a sprint", Robber.FleeSpeed > 16 and Robber.FleeSpeed < 26, Robber.FleeSpeed)
	check("the warning is 8-10 seconds", Robber.WarnSeconds >= 8 and Robber.WarnSeconds <= 10, Robber.WarnSeconds)
	-- the escape: every shop either has a reachable canal bank (canal level) or falls back to the street
	local plotsFolder = Workspace:FindFirstChild("Plots")
	local canalOk, canalCount, plotCount = true, 0, 0
	for _, plot in if plotsFolder then plotsFolder:GetChildren() else {} do
		local approach = plot:FindFirstChild("CustomerPath") and plot.CustomerPath:FindFirstChild("Approach")
		if approach then
			plotCount += 1
			local spot = RobberService.PickEscape(approach.Position)
			if spot then
				canalCount += 1
				if spot.Y >= Robber.CanalMaxY then
					canalOk = false
				end
			end
		end
	end
	if plotCount > 0 then
		check("escape spots are canal level", canalOk)
		check("at least one shop has a reachable canal", canalCount > 0, `{canalCount} of {plotCount}`)
	else
		table.insert(lines, "SKIP escape spots (no plots loaded)")
	end

	-- fee and recovery
	check("the fee is never below the minimum", RobberService.Fee("RubberDuck", 1, false) >= Robber.FeeMin)
	check("rare items get the long window", RobberService.RecoverySeconds("RubberDuck") == Robber.RecoverySeconds)

	-- the stolen set: server memory only, expires, can be removed once
	local owner = {}
	StolenItems.Add(owner, "u1", "RubberDuck", 7, 100, 0)
	check("a stolen item is marked", StolenItems.Is(owner, "u1", 50))
	check("it is still marked just before the end", StolenItems.Is(owner, "u1", 99))
	check("it is normal again once the window ends", not StolenItems.Is(owner, "u1", 100))
	check("the owner is told once, then it is gone", #StolenItems.TakeExpired(owner, 100) == 1 and #StolenItems.TakeExpired(owner, 101) == 0)
	StolenItems.Add(owner, "u2", "RubberDuck", 7, 100, 0)
	check("a reclaim removes it exactly once", StolenItems.Remove(owner, "u2") and not StolenItems.Remove(owner, "u2"))
	check("another player's item is not stolen", not StolenItems.Is({}, "u2", 1))
	StolenItems.Clear(owner)

	-- the breach: only when closed, lifts the slab but the shutter stays solid; puts itself back
	local HoursService = ServerScriptService.Server.Services:FindFirstChild("HoursService") and require(ServerScriptService.Server.Services.HoursService)
	local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild("Plot1")
	local shutter = plot and plot:FindFirstChild("ShopShutter")
	if HoursService and shutter and shutter:IsA("BasePart") and Workspace:GetAttribute("ShopOpen") == false then
		local before = shutter.Position.Y
		check("breach starts on a closed shop", HoursService.Breach(plot, 1) == true)
		check("a second breach is refused while one is on", HoursService.Breach(plot, 1) == false)
		task.wait(1.1)
		check("the shutter is lifted", shutter.Position.Y > before + 1, shutter.Position.Y - before)
		check("the shutter is STILL solid for everyone", shutter.CanCollide == true)
		task.wait(1.6)
		check("the shutter is back down", math.abs(shutter.Position.Y - before) < 0.2, shutter.Position.Y - before)
		check("the breach is over", HoursService.IsBreached(plot) == false)
	elseif HoursService and Workspace:GetAttribute("ShopOpen") == true then
		check("breach does nothing while the shop is open", plot ~= nil and HoursService.Breach(plot, 1) == false)
	else
		table.insert(lines, "SKIP breach (needs Play with Plot1's shutter)")
	end

	for _, line in lines do
		print("[RobberCheck] " .. line)
	end
	print("[RobberCheck]", passed, "passed;", failed, "failed")
	return lines, passed, failed
end

return RobberCheck
