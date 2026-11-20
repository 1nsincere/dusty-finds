-- DayNight.luau (ReplicatedStorage.Shared.Config.DayNight)
-- Purpose: the day/night cycle timing and the look (lighting keyframes) the LightingController blends between.
-- Owner: Dev 1 (Ace). Depends on: nothing. Read by Client/Controllers/LightingController.luau only (visual, no gameplay).
-- Time comes from workspace:GetServerTimeNow(), so every player on a server sees the same time of day.
-- Colours are {r, g, b} 0-255. Tune freely: nothing else depends on these numbers.
--
-- Look (2026-11-20): a calm "tycoon" grade. The map is already colourful, so the grade adds NO extra saturation,
-- day is soft and even, golden hour is only a gentle warm tint, and night is lit by the sky (cool moonlight +
-- ambient), not by lamps. Lamps and windows only take a warm tint at night; nothing glows (no Neon/bloom pile-up)
-- and no lights switch on/off as you walk around.

local DayNight = {}

-- The cycle, in order. Each segment moves the clock from `from` to `to` (hours, may pass 24) in `seconds`.
DayNight.SEGMENTS = {
	{ name = "Dawn", from = 5.0, to = 7.5, seconds = 60 },
	{ name = "Day", from = 7.5, to = 15.5, seconds = 300 },
	{ name = "GoldenHour", from = 15.5, to = 18.5, seconds = 150 },
	{ name = "Night", from = 18.5, to = 29.0, seconds = 210 }, -- 29 = 5:00 next morning
}

-- Lamp/window night tint and the shop ceiling light switch on when the keyframe `lights` value is above this.
DayNight.LIGHTS_ON_ABOVE = 0.5

-- Philippine-style street lights (Workspace.TownT2.StreetLights, template ServerStorage.StreetLightPH): each has
-- one fixed SpotLight in its SodiumLens. At night every one is on (never depends on camera distance): a soft
-- orange sodium light, kept low so a row of them reads as warm pools, not floodlights. The lens glows lightly.
DayNight.STREET_LIGHT = {
	color = { 255, 168, 92 }, brightness = 0.9, range = 28, angle = 115,
	lensNight = { 255, 178, 104 }, -- small Neon lens at night (dim orange, so bloom stays soft)
	lensDay = { 220, 214, 200 },
}

-- Invisible night fill lights (Workspace.TownT2.NightFill, one PointLight every ~60 studs, 14 studs above the ground at
-- every level). They give the town soft warm pools at night instead of flat blue moonlight. All on together at night,
-- no distance logic; turned off with "Reduce effects" for weak devices.
DayNight.NIGHT_FILL = { color = { 255, 214, 172 }, brightness = 0.42, range = 55 }

-- Inside a shop: a warm, cozy grade on top of the time-of-day look (blended in/out as you walk through the door).
-- Shop interior lights themselves are placed parts (Plots.PlotN.ShopProps.ShopLights, attributes Day / Night =
-- brightness): pendant lamps, shelf washes, counter spot; the workbench lamp is part of the Workbench model.
DayNight.INDOOR = { ccTint = { 255, 236, 214 }, tintAmount = 0.6, ccSat = 0.04, ccContrast = 0.04, bloom = 0.08 }

-- Decorative lantern heads/bulbs at night: a DIM orange glow (dark enough that a plaza full of them doesn't bloom into
-- a wall of bright dots). They give no real light; the street lights do that. glow = false = matte warm tint only.
DayNight.LAMP_NIGHT = { color = { 196, 120, 62 }, glow = true }
-- House/landmark window glass at night: a dim warm tint, same rule (no Neon).
DayNight.WINDOW_NIGHT = { color = { 196, 150, 100 }, glow = false }
-- One fixed warm ceiling light inside every shop at night so the shop floor stays readable (it never moves or
-- turns off with distance). Kept low so shops look cosy, not floodlit.
DayNight.SHOP_LIGHT = { range = 30, brightness = 0.55, height = 11, color = { 255, 222, 180 } }

-- Look keyframes by clock hour (0-24). The controller blends linearly between neighbours (wrapping at 24).
-- ambient = indoor/shadow fill, outdoor = outdoor fill, shiftTop = sun/moon-lit tint, atmo* = Atmosphere,
-- cc* = colour grade (ccSat 0 = the map's own colours), bloom = glow on bright pixels.
-- Night: a dimmer, less blue sky fill than before (the fill lights + street lights now do the lighting).
local NIGHT = {
	brightness = 0.9, exposure = 0.05, ambient = { 76, 78, 96 }, outdoor = { 82, 88, 112 }, shiftTop = { 140, 154, 196 },
	atmoColor = { 56, 64, 92 }, atmoDecay = { 34, 40, 70 }, atmoDensity = 0.3, atmoHaze = 0.9, atmoGlare = 0,
	bloom = 0.22, ccTint = { 230, 230, 248 }, ccSat = -0.06, ccContrast = 0.06, sunRays = 0, lights = 1,
}

local function at(clock: number, look)
	local key = table.clone(look)
	key.clock = clock
	return key
end

DayNight.KEYS = {
	at(0, NIGHT),
	at(5.0, NIGHT),
	{ -- dawn: soft pink-blue, still dim
		clock = 6.2, brightness = 1.6, exposure = 0, ambient = { 104, 100, 116 }, outdoor = { 140, 128, 146 }, shiftTop = { 246, 196, 176 },
		atmoColor = { 214, 184, 182 }, atmoDecay = { 130, 110, 150 }, atmoDensity = 0.28, atmoHaze = 1.0, atmoGlare = 0.15,
		bloom = 0.25, ccTint = { 255, 244, 240 }, ccSat = -0.04, ccContrast = 0.05, sunRays = 0.04, lights = 0.7,
	},
	{ -- morning: day look arrives
		clock = 7.6, brightness = 2.0, exposure = -0.1, ambient = { 124, 124, 130 }, outdoor = { 138, 138, 146 }, shiftTop = { 255, 246, 232 },
		atmoColor = { 206, 220, 236 }, atmoDecay = { 150, 168, 196 }, atmoDensity = 0.22, atmoHaze = 0.5, atmoGlare = 0.05,
		bloom = 0.15, ccTint = { 255, 253, 250 }, ccSat = -0.06, ccContrast = 0.05, sunRays = 0.03, lights = 0,
	},
	{ -- midday: soft and even, a little under the old brightness, no extra saturation
		clock = 12.0, brightness = 2.1, exposure = -0.12, ambient = { 128, 128, 134 }, outdoor = { 140, 140, 148 }, shiftTop = { 255, 250, 242 },
		atmoColor = { 204, 220, 238 }, atmoDecay = { 146, 166, 198 }, atmoDensity = 0.2, atmoHaze = 0.4, atmoGlare = 0.03,
		bloom = 0.12, ccTint = { 255, 255, 255 }, ccSat = -0.06, ccContrast = 0.05, sunRays = 0.02, lights = 0,
	},
	{ -- afternoon
		clock = 15.0, brightness = 2.0, exposure = -0.1, ambient = { 126, 122, 128 }, outdoor = { 140, 134, 140 }, shiftTop = { 255, 240, 220 },
		atmoColor = { 220, 214, 210 }, atmoDecay = { 160, 150, 170 }, atmoDensity = 0.22, atmoHaze = 0.6, atmoGlare = 0.08,
		bloom = 0.15, ccTint = { 255, 251, 246 }, ccSat = -0.06, ccContrast = 0.05, sunRays = 0.03, lights = 0,
	},
	{ -- golden hour: only a gentle warm tint, not orange
		clock = 16.9, brightness = 1.85, exposure = -0.06, ambient = { 122, 114, 118 }, outdoor = { 138, 126, 128 }, shiftTop = { 255, 224, 188 },
		atmoColor = { 228, 208, 192 }, atmoDecay = { 168, 138, 150 }, atmoDensity = 0.25, atmoHaze = 0.9, atmoGlare = 0.2,
		bloom = 0.2, ccTint = { 255, 246, 236 }, ccSat = -0.05, ccContrast = 0.06, sunRays = 0.05, lights = 0.3,
	},
	{ -- dusk: blue hour, lamps take their tint
		clock = 17.9, brightness = 1.5, exposure = 0, ambient = { 100, 98, 120 }, outdoor = { 118, 114, 142 }, shiftTop = { 220, 176, 170 },
		atmoColor = { 150, 132, 150 }, atmoDecay = { 80, 70, 110 }, atmoDensity = 0.28, atmoHaze = 1.0, atmoGlare = 0.1,
		bloom = 0.22, ccTint = { 236, 232, 250 }, ccSat = -0.07, ccContrast = 0.06, sunRays = 0.02, lights = 1,
	},
	at(18.9, NIGHT),
}

return DayNight
