-- Hours.luau (ReplicatedStorage.Shared.Hours)
-- Purpose: the IN-GAME clock and opening hours. The game day is a short cycle shared by every player through server time (about 30
-- minutes, paced by Config.DayNight.SEGMENTS: sunset 3:30-6:30 pm game time, night flies by). It is NOT real time and not tied to any
-- country, so a player anywhere sees the same sunset and the same closing time. This module says what game hour it is and when the
-- Warehouse Market and each player's shop are open. Pure functions: tests pass `hour` / `unixSeconds` in.
-- Owner: Dev 1 (Ace). Used by: LightingController, HudLayoutController (client); HoursService, CustomerService, ShipmentService,
-- SkinService, PaintService (server). Testing aid: set the number attribute PHHourOverride on Workspace (e.g. 18.3) to fake the hour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNight = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("DayNight"))

local Hours = {}

-- Opening hours, in game hours 0-24 (18.25 = 6:15 pm game time).
Hours.MARKET_OPEN = 7.0
Hours.MARKET_CLOSE = 18.25
Hours.SHOP_OPEN = 7.0
Hours.SHOP_CLOSE = 19.0 -- customers stop arriving; the owner can still restore, edit and decorate

local cycleLength = 0
for _, seg in DayNight.SEGMENTS do
	cycleLength += seg.seconds
end
Hours.CYCLE_SECONDS = cycleLength

-- Game hour (0 <= h < 24) for a server time in seconds.
function Hours.hourAt(serverSeconds: number): number
	local t = serverSeconds % cycleLength
	for _, seg in DayNight.SEGMENTS do
		if t < seg.seconds then
			return (seg.from + (seg.to - seg.from) * (t / seg.seconds)) % 24
		end
		t -= seg.seconds
	end
	local last = DayNight.SEGMENTS[#DayNight.SEGMENTS]
	return last.to % 24
end

-- Game day number for a server time (a new day starts every cycle).
function Hours.dayAt(serverSeconds: number): number
	return math.floor(serverSeconds / cycleLength)
end

-- The game hour right now (same for everyone on the server). The attribute is for testing only.
function Hours.now(): number
	local override = workspace:GetAttribute("PHHourOverride")
	if type(override) == "number" then
		return override % 24
	end
	return Hours.hourAt(workspace:GetServerTimeNow())
end

local function inWindow(hour: number, openAt: number, closeAt: number): boolean
	return hour >= openAt and hour < closeAt
end

function Hours.marketOpen(hour: number?): boolean
	return inWindow(hour or Hours.now(), Hours.MARKET_OPEN, Hours.MARKET_CLOSE)
end

function Hours.shopOpen(hour: number?): boolean
	return inWindow(hour or Hours.now(), Hours.SHOP_OPEN, Hours.SHOP_CLOSE)
end

-- "6:15 PM" for the HUD and toasts.
function Hours.format(hour: number): string
	local h = math.floor(hour) % 24
	local minutes = math.floor((hour - math.floor(hour)) * 60)
	local suffix = if h >= 12 then "PM" else "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, minutes, suffix)
end

return Hours
