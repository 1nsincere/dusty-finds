-- SeasonCheck.luau (ServerScriptService.Server.Tests.SeasonCheck)
-- Purpose: tests the season dates (Config.Seasons) and SeasonService: seasonal decor shows only in season, the special pieces only
-- for owners of the pass. Pure: a COPY of the service on a fake plot; never touches a real shop.
-- Owner: Dev 1 (Ace). Run while Playing (Server): require(game.ServerScriptService.Server.Tests.SeasonCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SeasonCheck = {}

function SeasonCheck.run()
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
		return math.abs(a - b) < 0.001 -- Transparency is stored as a 32-bit float
	end
	local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
	local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)

	-- ===== dates =====
	check("dates: Pasko starts on Dec 1 (Nov 30 is still off)", Seasons.isActive("Pasko", 12, 1) and not Seasons.isActive("Pasko", 11, 30))
	check("dates: Pasko runs over New Year until Jan 6", Seasons.isActive("Pasko", 12, 25) and Seasons.isActive("Pasko", 1, 1) and Seasons.isActive("Pasko", 1, 6) and not Seasons.isActive("Pasko", 1, 7))
	check("dates: summer is not Pasko", not Seasons.isActive("Pasko", 6, 15) and not Seasons.isActive("Pasko", 3, 1))
	check("dates: an unknown season is never active", not Seasons.isActive("Nope", 12, 25))
	check("dates: the Studio override wins over the calendar", Seasons.activeNow("Pasko").Pasko == true and next(Seasons.activeNow("None")) == nil and next(Seasons.activeNow("Nope")) == nil)
	check("dates: the calendar decides when there is no override", Seasons.activeNow(nil, os.time({ year = 2026, month = 12, day = 24, hour = 12 })).Pasko == true and Seasons.activeNow(nil, os.time({ year = 2026, month = 7, day = 4, hour = 12 })).Pasko == nil)
	check("config: every season's pass is a real pass", (function()
		for _, s in Seasons.LIST do
			if s.pass ~= nil and Monetization.BY_PASS[s.pass] == nil then
				return false
			end
		end
		return true
	end)())

	-- ===== SeasonService on a copy, on a fake plot =====
	local kit = Instance.new("Folder")
	kit.Name = "SeasonCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local copy = ServerScriptService.Server.Services.SeasonService:Clone()
	copy.Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local Service = require(copy)
		local plot = Instance.new("Folder")
		plot.Name = "SeasonPlot"
		local facade = Instance.new("Folder")
		facade.Name = "Facade"
		facade.Parent = plot
		local decor = Instance.new("Folder")
		decor.Name = "Decor_Pasko"
		decor.Parent = facade
		local function piece(name: string, requires: string?): Part
			local m = Instance.new("Model")
			m.Name = name
			if requires then
				m:SetAttribute("RequiresPass", requires)
			end
			m.Parent = decor
			local p = Instance.new("Part")
			p.Transparency = 0.2
			p.Parent = m
			local l = Instance.new("PointLight")
			l.Parent = p
			return p
		end
		local lights = piece("Lights", nil)
		local parol = piece("Parol", "ThemePasko")
		plot.Parent = ServerScriptService

		local owns, inSeason = false, true
		Service.SetLookups(function(_, passId)
			return owns and passId == "ThemePasko"
		end, function()
			return if inSeason then { Pasko = true } else {}
		end)

		Service.Refresh(plot)
		check("season on, no pass: the free string lights show, the pass-only parol stays hidden", near(lights.Transparency, 0.2) and parol.Transparency == 1)
		check("lights: a light is on with its piece, off with the hidden one", lights:FindFirstChildWhichIsA("PointLight").Enabled == true and parol:FindFirstChildWhichIsA("PointLight").Enabled == false)
		owns = true
		Service.Refresh(plot)
		check("season on, pass owner: the parol shows too (its own transparency is restored)", near(parol.Transparency, 0.2) and parol:FindFirstChildWhichIsA("PointLight").Enabled == true)
		inSeason = false
		Service.Refresh(plot)
		check("season over: everything is hidden, even for a pass owner", lights.Transparency == 1 and parol.Transparency == 1 and lights:FindFirstChildWhichIsA("PointLight").Enabled == false)
		inSeason = true
		owns = false
		Service.Refresh(plot)
		check("a pass that is gone hides the pass-only piece again, the next season brings the lights back", near(lights.Transparency, 0.2) and parol.Transparency == 1)
		check("decor never changes collision", lights.CanCollide == true and parol.CanCollide == true)
		plot:Destroy()
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[SeasonCheck]", line)
		end
	end
	print(`[SeasonCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return SeasonCheck
