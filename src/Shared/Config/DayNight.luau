-- DayNight.luau (ReplicatedStorage.Shared.Config.DayNight)
-- Purpose: the day/night cycle timing and the look (lighting keyframes) the LightingController blends between.
-- Owner: Dev 1 (Ace). Depends on: nothing. Read by Client/Controllers/LightingController.luau only (visual, no gameplay).
-- Time comes from workspace:GetServerTimeNow(), so every player on a server sees the same time of day.
-- Colours are {r, g, b} 0-255. Tune freely: nothing else depends on these numbers.

local DayNight = {}

-- The cycle, in order. Each segment moves the clock from `from` to `to` (hours, may pass 24) in `seconds`.
-- Day and golden hour get most of the time; night is shorter but still long enough to enjoy the lights.
DayNight.SEGMENTS = {
	{ name = "Dawn", from = 5.0, to = 7.5, seconds = 60 },
	{ name = "Day", from = 7.5, to = 15.5, seconds = 300 },
	{ name = "GoldenHour", from = 15.5, to = 18.5, seconds = 150 },
	{ name = "Night", from = 18.5, to = 29.0, seconds = 210 }, -- 29 = 5:00 next morning
}

-- Lamps and window glow switch on when the keyframe `lights` value is above this.
DayNight.LIGHTS_ON_ABOVE = 0.5

-- Nearby lamps get a real PointLight (the closest ones to the camera). 0 when "Reduce effects" is on.
DayNight.LAMP_LIGHT_POOL = 10
DayNight.LAMP_LIGHT = { range = 16, brightness = 0.9, color = { 255, 196, 128 } }
-- Lantern heads glow this warm colour at night (by day they go back to their own colour, not glowing).
DayNight.LAMP_GLOW = { 255, 208, 140 }
-- One warm ceiling light inside every shop at night so the shop floor stays readable.
DayNight.SHOP_LIGHT = { range = 32, brightness = 0.9, height = 11, color = { 255, 214, 160 } }
-- Window glass on houses and landmarks glows this colour at night.
DayNight.WINDOW_GLOW = { 255, 186, 104 }

-- Look keyframes by clock hour (0-24). The controller blends linearly between neighbours (wrapping at 24).
-- ambient = indoor/shadow fill, outdoor = outdoor fill, shiftTop = sun-lit tint, atmo* = Atmosphere, cc* = colour grade.
DayNight.KEYS = {
	{
		clock = 0, brightness = 1.4, exposure = 0.18, ambient = { 78, 80, 112 }, outdoor = { 74, 86, 128 }, shiftTop = { 130, 150, 215 },
		atmoColor = { 70, 82, 128 }, atmoDecay = { 34, 40, 82 }, atmoDensity = 0.34, atmoHaze = 1.4, atmoGlare = 0,
		bloom = 1.1, ccTint = { 206, 218, 255 }, ccSat = 0.12, ccContrast = 0.16, sunRays = 0, lights = 1,
	},
	{
		clock = 5.0, brightness = 1.4, exposure = 0.18, ambient = { 78, 80, 112 }, outdoor = { 74, 86, 128 }, shiftTop = { 130, 150, 215 },
		atmoColor = { 70, 82, 128 }, atmoDecay = { 34, 40, 82 }, atmoDensity = 0.34, atmoHaze = 1.4, atmoGlare = 0,
		bloom = 1.1, ccTint = { 206, 218, 255 }, ccSat = 0.12, ccContrast = 0.16, sunRays = 0, lights = 1,
	},
	{
		clock = 6.2, brightness = 2.2, exposure = 0.1, ambient = { 100, 88, 108 }, outdoor = { 172, 140, 160 }, shiftTop = { 255, 176, 150 },
		atmoColor = { 255, 188, 170 }, atmoDecay = { 150, 104, 160 }, atmoDensity = 0.33, atmoHaze = 1.8, atmoGlare = 0.7,
		bloom = 0.8, ccTint = { 255, 234, 230 }, ccSat = 0.18, ccContrast = 0.14, sunRays = 0.18, lights = 0.7,
	},
	{
		clock = 7.6, brightness = 3.0, exposure = 0.02, ambient = { 112, 106, 116 }, outdoor = { 166, 160, 170 }, shiftTop = { 255, 232, 206 },
		atmoColor = { 214, 226, 240 }, atmoDecay = { 150, 170, 205 }, atmoDensity = 0.27, atmoHaze = 1.0, atmoGlare = 0.35,
		bloom = 0.5, ccTint = { 255, 250, 244 }, ccSat = 0.2, ccContrast = 0.12, sunRays = 0.1, lights = 0,
	},
	{
		clock = 12.0, brightness = 3.3, exposure = 0, ambient = { 116, 114, 120 }, outdoor = { 172, 170, 176 }, shiftTop = { 255, 244, 228 },
		atmoColor = { 204, 222, 242 }, atmoDecay = { 140, 166, 204 }, atmoDensity = 0.24, atmoHaze = 0.8, atmoGlare = 0.2,
		bloom = 0.42, ccTint = { 255, 252, 248 }, ccSat = 0.22, ccContrast = 0.12, sunRays = 0.08, lights = 0,
	},
	{
		clock = 15.0, brightness = 3.2, exposure = 0.03, ambient = { 112, 100, 104 }, outdoor = { 168, 150, 142 }, shiftTop = { 255, 214, 170 },
		atmoColor = { 240, 214, 190 }, atmoDecay = { 190, 140, 160 }, atmoDensity = 0.28, atmoHaze = 1.2, atmoGlare = 0.5,
		bloom = 0.55, ccTint = { 255, 244, 232 }, ccSat = 0.24, ccContrast = 0.14, sunRays = 0.12, lights = 0,
	},
	{
		clock = 16.9, brightness = 2.7, exposure = 0.04, ambient = { 110, 98, 108 }, outdoor = { 168, 150, 148 }, shiftTop = { 255, 206, 160 },
		atmoColor = { 255, 210, 176 }, atmoDecay = { 190, 128, 160 }, atmoDensity = 0.31, atmoHaze = 1.7, atmoGlare = 0.9,
		bloom = 0.7, ccTint = { 255, 242, 230 }, ccSat = 0.22, ccContrast = 0.16, sunRays = 0.2, lights = 0.3,
	},
	{
		clock = 17.9, brightness = 1.8, exposure = 0.12, ambient = { 92, 84, 112 }, outdoor = { 128, 112, 140 }, shiftTop = { 255, 168, 150 },
		atmoColor = { 226, 150, 160 }, atmoDecay = { 104, 70, 132 }, atmoDensity = 0.35, atmoHaze = 1.9, atmoGlare = 0.7,
		bloom = 0.95, ccTint = { 246, 228, 244 }, ccSat = 0.18, ccContrast = 0.16, sunRays = 0.12, lights = 1,
	},
	{
		clock = 18.9, brightness = 1.4, exposure = 0.18, ambient = { 78, 80, 112 }, outdoor = { 74, 86, 128 }, shiftTop = { 130, 150, 215 },
		atmoColor = { 70, 82, 128 }, atmoDecay = { 34, 40, 82 }, atmoDensity = 0.34, atmoHaze = 1.4, atmoGlare = 0,
		bloom = 1.1, ccTint = { 206, 218, 255 }, ccSat = 0.12, ccContrast = 0.16, sunRays = 0, lights = 1,
	},
}

return DayNight
