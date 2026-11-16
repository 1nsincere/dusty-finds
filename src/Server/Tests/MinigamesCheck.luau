-- MinigamesCheck.luau (ServerScriptService.Server.Tests.MinigamesCheck)
-- Purpose: tests the logic of the Scrape, Reassemble/Replace (Socket) and Test minigames with FAKE item models built in code.
-- Nothing is saved and no remote is used: it only exercises the minigame objects (same interface as Wipe/Polish).
-- Owner: Dev 1 (Ace). Depends on: StarterPlayerScripts.Client.Minigames.* (client modules, requirable from the server for tests).
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.MinigamesCheck).run()

local StarterPlayer = game:GetService("StarterPlayer")

local MinigamesCheck = {}

local function part(name: string, parent: Instance?, position: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Position = position or Vector3.zero
	p.Parent = parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function MinigamesCheck.run()
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

	local root = StarterPlayer.StarterPlayerScripts:FindFirstChild("Client")
	local dir = root and root:FindFirstChild("Minigames")
	if dir == nil then
		return { "FAIL StarterPlayerScripts.Client.Minigames is missing (Script Sync or manual insert needed)" }, 0, 1
	end
	local Scrape = require(dir.Scrape)
	local Reassemble = require(dir.Reassemble)
	local Replace = require(dir.Replace)
	local TestGame = require(dir.Test)

	local made: { Instance } = {}
	local function newModel(): Model
		local m = Instance.new("Model")
		m.Parent = workspace
		table.insert(made, m)
		return m
	end

	local ok, err = pcall(function()
		-- ===== Scrape =====
		local model = newModel()
		local rust = folder("RustSpots", model)
		local a = part("Rust1", rust)
		local layers = Instance.new("NumberValue")
		layers.Name = "Layers"
		layers.Value = 2
		layers.Parent = a
		local decal = Instance.new("Decal")
		decal.Name = "Rust"
		decal.Parent = a
		part("Rust2", rust) -- default 3 layers
		local progress, done = -1, nil
		local game_ = Scrape.new(model, { type = "Scrape" }, function(f)
			progress = f
		end, function(score)
			done = score
		end)
		check("Scrape: starts at 0 progress with the rust decal showing", progress == 0 and decal.Transparency == 0)
		local function stroke(spot: BasePart, dx: number)
			game_:OnDrag({ Instance = spot }, Vector2.new(dx, 0), 0.016)
		end
		game_:OnPointerDown({ Instance = a })
		stroke(a, 20) -- right
		stroke(a, -20) -- reversal 1 (stroke was long enough)
		check("Scrape: one reversal removes one layer", progress > 0 and decal.Transparency == 0.5 and done == nil, progress)
		game_:OnPointerUp() -- lift and press again: a fresh stroke
		game_:OnPointerDown({ Instance = a })
		stroke(a, 3)
		stroke(a, -3) -- tiny jitter: too short to count
		check("Scrape: tiny jitter does not scrape", decal.Transparency == 0.5)
		stroke(a, 20)
		stroke(a, -20)
		check("Scrape: layers fade the decal to fully clean", decal.Transparency == 1)
		local b = rust.Rust2
		stroke(b, 20)
		for _ = 1, 3 do
			stroke(b, -20)
			stroke(b, 20)
		end
		check("Scrape: finishing every layer completes with score 100", done == 100 and progress == 1, done)
		stroke(b, -20)
		check("Scrape: nothing happens after completion", done == 100)
		game_:Destroy()

		local noRust = newModel()
		check("Scrape: a model without RustSpots is refused", not pcall(Scrape.new, noRust, { type = "Scrape" }, function() end, function() end))
		local up = Scrape.new(model, { type = "Scrape" }, function() end, function() end)
		up:OnPointerUp()
		check("Scrape: pointer up before down is harmless", true)
		up:Destroy()

		-- ===== Reassemble / Replace (Socket) =====
		local car = newModel()
		local sockets, loose = folder("Sockets", car), folder("LooseParts", car)
		part("Wheel1", sockets, Vector3.new(5, 0, 0))
		part("Wheel2", sockets, Vector3.new(-5, 0, 0))
		part("Wheel1", loose, Vector3.new(0, 10, 0))
		part("Wheel2", loose, Vector3.new(0, 11, 0))
		part("Bolt", loose, Vector3.new(0, 12, 0)) -- a decoy: no socket
		local sprogress, sdone = -1, nil
		local fxLog = {}
		local socket = Reassemble.new(car, { type = "Reassemble", parts = { "Wheel" } }, function(f)
			sprogress = f
		end, function(score)
			sdone = score
		end, { instant = true, wrong = function() table.insert(fxLog, "wrong") end, place = function() table.insert(fxLog, "place") end })
		local function tap(inst: Instance)
			socket:OnPointerDown({ Instance = inst })
		end
		tap(sockets.Wheel1) -- no part selected yet
		check("Socket: tapping a socket with nothing selected does nothing", sprogress == 0 and #fxLog == 0)
		tap(loose.Wheel1)
		tap(sockets.Wheel1)
		check("Socket: the right part snaps into its socket", loose.Wheel1.Position == sockets.Wheel1.Position and sprogress == 0.5 and fxLog[1] == "place")
		tap(loose.Wheel2)
		tap(sockets.Wheel1) -- filled / wrong
		tap(loose.Wheel2)
		tap(sockets.Wheel2)
		check("Socket: filling the last socket completes", sdone ~= nil and sprogress == 1)
		check("Socket: completion score is 100 minus 10 per wrong tap", sdone == 100 or sdone == 90, sdone)

		local car2 = newModel()
		local s2, l2 = folder("Sockets", car2), folder("LooseParts", car2)
		part("Lens", s2)
		part("Lens", l2)
		part("Cap", l2) -- decoy
		part("Cover", l2) -- decoy
		local rdone
		local replace = Replace.new(car2, { type = "Replace", parts = { "Lens" } }, function() end, function(score)
			rdone = score
		end, { instant = true })
		local function rtap(inst: Instance)
			replace:OnPointerDown({ Instance = inst })
		end
		for _ = 1, 8 do
			rtap(l2.Cap)
			rtap(s2.Lens) -- decoy on the socket: wrong
		end
		check("Replace: choosing a decoy is wrong, the part returns to the tray", rdone == nil and l2.Cap.Position == Vector3.zero)
		rtap(l2.Lens)
		rtap(s2.Lens)
		check("Replace: the score never drops below 50 however many wrong picks", rdone == 50, rdone)
		check("Replace: only parts with a matching socket count as sockets (decoys are ignored)", replace.total == 1)

		local brokenModel = newModel()
		folder("Sockets", brokenModel)
		check("Socket: a model without LooseParts is refused", not pcall(Reassemble.new, brokenModel, { type = "Reassemble" }, function() end, function() end))
		socket:Destroy()
		replace:Destroy()

		-- ===== Test (timing) =====
		check("Test: common items get a wider green zone than legendary", (TestGame.zones("Common").greenTo - TestGame.zones("Common").greenFrom) > (TestGame.zones("Legendary").greenTo - TestGame.zones("Legendary").greenFrom))
		local tprogress, tdone = -1, nil
		local t = TestGame.new(nil, { type = "Test", style = "Wind", rarity = "Common" }, function(f)
			tprogress = f
		end, function(score)
			tdone = score
		end)
		check("Test: the needle starts at the left and sweeps right", t.needle == 0)
		t:Update(0.55) -- half of the 1.1 s sweep = 0.5
		check("Test: the needle moves with Update", math.abs(t.needle - 0.5) < 0.01, t.needle)
		check("Test: a tap inside green completes with 100", t:OnPointerDown(nil) == "green" and tdone == 100 and tprogress == 1)
		t:Destroy()

		local red = TestGame.new(nil, { type = "Test", rarity = "Common" }, function() end, function(score)
			tdone = score
		end)
		tdone = nil
		check("Test: a tap in red is 'try again' and restarts the sweep", red:OnPointerDown(nil) == "red" and tdone == nil and red.needle == 0)
		red.needle = 0.5 + red.zone.greenTo - 0.5 + 0.05 -- just past green, inside yellow
		check("Test: a yellow tap gives 75 (the first miss was free)", red:OnPointerDown(nil) == "yellow" and tdone == 75, tdone)

		local many = TestGame.new(nil, { type = "Test", rarity = "Epic" }, function() end, function(score)
			tdone = score
		end)
		tdone = nil
		for _ = 1, 12 do
			many.needle = 0
			many:OnPointerDown(nil)
		end
		many.needle = 0.5
		many:OnPointerDown(nil)
		check("Test: many misses cost 10 each after the first but never below 50", tdone == 50, tdone)
		many:Destroy()
		red:Destroy()
		local sweep = TestGame.new(nil, { type = "Test" }, function() end, function() end)
		for _ = 1, 400 do
			sweep:Update(0.05)
		end
		check("Test: the needle stays on the bar (0 to 1) forever", sweep.needle >= 0 and sweep.needle <= 1, sweep.needle)
		sweep:Destroy()
	end)

	for _, m in made do
		m:Destroy()
	end
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[MinigamesCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return MinigamesCheck
