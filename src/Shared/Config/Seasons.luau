-- Seasons.luau (ReplicatedStorage.Shared.Config.Seasons)
-- Purpose: when seasonal shop decor is shown (docs/12, Christmas "Pasko"). DATA + one pure date rule, no game state.
-- Owner: Dev 1 (Ace). Read by: SeasonService (server), SeasonCheck.
-- A season is active between from (month, day) and to (month, day), both days included; it may wrap over New Year (Dec 1 to Jan 6).
-- `pass` = the Config.Monetization pass that unlocks the season's special decor (nil = free for everyone). In Studio the test
-- override attribute `Workspace.SeasonOverride` ("Pasko" = on, "None" = off) beats the calendar.

local Seasons = {}

Seasons.LIST = {
	Pasko = {
		id = "Pasko",
		name = "Pasko (Christmas)",
		fromMonth = 12, fromDay = 1, -- the "Ber months" start earlier in real life; the decor starts Dec 1
		toMonth = 1, toDay = 6, -- Three Kings
		pass = "ThemePasko", -- parol, wreath and belen; the string lights are free for everyone
	},
}

local function dayNumber(month: number, day: number): number
	return month * 100 + day
end

-- Is `id` active on this date? Pure.
function Seasons.isActive(id: string, month: number, day: number): boolean
	local s = Seasons.LIST[id]
	if s == nil then
		return false
	end
	local now = dayNumber(month, day)
	local from, to = dayNumber(s.fromMonth, s.fromDay), dayNumber(s.toMonth, s.toDay)
	if from <= to then
		return now >= from and now <= to
	end
	return now >= from or now <= to -- wraps over New Year
end

-- The ids of every season active right now (UTC calendar). `override` ("Pasko" / "None" / nil) is for Studio tests.
function Seasons.activeNow(override: string?, nowTime: number?): { [string]: boolean }
	local active = {}
	if override ~= nil and override ~= "" then
		if override ~= "None" and Seasons.LIST[override] then
			active[override] = true
		end
		return active
	end
	local d = os.date("!*t", nowTime or os.time())
	for id in Seasons.LIST do
		if Seasons.isActive(id, d.month, d.day) then
			active[id] = true
		end
	end
	return active
end

return Seasons
