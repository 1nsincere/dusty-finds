-- Sounds.luau (ReplicatedStorage.Shared.Config.Sounds)
-- Purpose: every music track, ambience loop and sound effect the game plays, as data (ids, volumes, pitch).
-- Owner: Dev 1 (Ace). Read by Client/Controllers/SoundController.luau only (client-side audio, no gameplay).
-- All ids are Roblox-licensed library audio (APM / DistroKid Official / Pro Sound Effects) that any experience may use,
-- checked to load in this place on 2026-11-20. To swap a sound, change its id here; nothing else needs to change.

local Sounds = {}

-- Mix levels (multiplied with each sound's own volume). The Settings switches turn music / sfx fully off.
Sounds.MIX = { music = 0.32, ambience = 0.22, sfx = 0.6 }

-- Music: a cozy shop playlist by day, a calmer one at night (follows the LightingController clock). Shuffled, crossfaded.
Sounds.MUSIC = {
	day = {
		{ id = 121736147160985, name = "Lofi Bakery R&B" },
		{ id = 71518458210800, name = "Cat Coffee Lofi" },
		{ id = 1839578771, name = "Charming View Ukulele" },
	},
	night = {
		{ id = 130654070538280, name = "Quiet Bakery R&B" },
		{ id = 85570715947607, name = "Desert Calm" },
		{ id = 126675971380853, name = "Violin Cat Hush" },
	},
	-- inside any shop (standing over a plot's Floor): a light jazz / sax store playlist, day or night
	shop = {
		{ id = 93549862426122, name = "Get it Down Smoothly" },
		{ id = 102651414325854, name = "Sax Tocando MPB N° 17" },
		{ id = 9044636195, name = "Salute-In-Jazz" },
	},
	crossfade = 4, -- seconds
	nightFrom = 18.5, -- clock hours: night playlist + night ambience between these
	nightTo = 5.5,
}

-- Ambience: town by day (birds, quiet street), crickets at night; gentle waves heard near the lagoon only (3D).
Sounds.AMBIENCE = {
	day = { id = 9117064941, volume = 0.8 },
	night = { id = 9112764040, volume = 0.9 },
	waves = { id = 78025480791776, volume = 0.9, position = Vector3.new(-50, 2, -380), range = 140 },
}

-- Effects. pitch = { min, max } gives a little variation so repeats don't sound robotic.
Sounds.SFX = {
	click = { id = 9125654847, volume = 0.35, pitch = { 1.35, 1.5 } }, -- every UI button
	coins = { id = 9113849583, volume = 0.7, pitch = { 1.0, 1.1 } }, -- a sale
	purchase = { id = 9113849583, volume = 0.55, pitch = { 0.85, 0.9 } }, -- bought an upgrade / crate
	levelUp = { id = 9044739323, volume = 0.6 }, -- short happy sting
	restored = { id = 9044739323, volume = 0.5, pitch = { 1.05, 1.05 } }, -- item fully restored
	reveal = { id = 9120217544, volume = 0.45, pitch = { 1.1, 1.2 } }, -- box opened / rare find
	stepDone = { id = 9120217544, volume = 0.35, pitch = { 1.5, 1.6 } }, -- one restoration step finished
	boxOpen = { id = 9114054266, volume = 0.7 },
	delivery = { id = 9113578876, volume = 0.6 },
	doorbell = { id = 9125935023, volume = 0.55, rolloff = 60 }, -- 3D: a customer walks in
	snap = { id = 9113591001, volume = 0.6, pitch = { 1.2, 1.3 } }, -- part fits its socket
	pick = { id = 9125654847, volume = 0.45, pitch = { 1.0, 1.1 } }, -- picked up a loose part
	wrong = { id = 9125654847, volume = 0.6, pitch = { 0.6, 0.65 } }, -- wrong socket
}

-- Work loops while a restoration minigame is making progress (start on progress, fade out ~0.25 s after it stops).
Sounds.WORK = {
	Wipe = { id = 9113597285, volume = 0.5 },
	Scrape = { id = 9116822056, volume = 0.45 },
	Polish = { id = 9118740884, volume = 0.4 },
}

return Sounds
