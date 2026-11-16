-- TutorialCheck.luau (ServerScriptService.Server.Tests.TutorialCheck)
-- Purpose: tests Shared.Tutorial (the "is this step done?" rules) and TutorialService.ReportStep against a COPY of the
-- service and a FAKE in-memory DataService. Never touches a real profile.
-- Owner: Dev 1 (Ace) wrote the test for Dev 3's (Sean) tutorial. Depends on: TutorialService, Shared.Tutorial, Lib.
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.TutorialCheck).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TutorialCheck = {}

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local c = {}
	for k, x in v do
		c[k] = deepCopy(x)
	end
	return c
end

local function newData()
	return {
		inventory = {}, collection = {}, stats = { restored = 0, sold = 0, earned = 0, playSeconds = 0 },
		tutorial = { step = 0, done = false },
	}
end

function TutorialCheck.run()
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

	local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

	-- ===== Shared.Tutorial: the rules =====
	local d = newData()
	check("a brand-new player is on step 1 (open the box)", Tutorial.CurrentStep(d) == 1)
	check("no step is done for an empty profile", not Tutorial.IsStepDone("opened", d) and not Tutorial.IsStepDone("sold", d))
	d.inventory.a = { state = "Unopened" }
	check("an Unopened box alone does not count as opened", not Tutorial.IsStepDone("opened", d))
	d.inventory.a.state = "Dirty"
	check("a Dirty item proves 'opened'", Tutorial.IsStepDone("opened", d) and Tutorial.CurrentStep(d) == 2)
	d.inventory.a.state = "Restored"
	check("a Restored item proves 'restored' (and 'opened')", Tutorial.IsStepDone("restored", d) and Tutorial.IsStepDone("opened", d) and Tutorial.CurrentStep(d) == 3)
	d.inventory.a.state = "Displayed"
	check("a Displayed item proves 'displayed'", Tutorial.IsStepDone("displayed", d) and Tutorial.CurrentStep(d) == 4)
	d.inventory = {}
	d.stats.sold = 1
	check("a sale proves every step even when the item is gone", Tutorial.IsStepDone("sold", d) and Tutorial.IsStepDone("opened", d) and Tutorial.CurrentStep(d) == #Tutorial.Steps + 1)
	check("an unknown step id is never done", not Tutorial.IsStepDone("nope", d) and Tutorial.IndexOf("nope") == nil)
	check("garbage data is never done and does not error", select(1, pcall(Tutorial.IsStepDone, "opened", "x")) == true and not Tutorial.IsStepDone("opened", "x") and not Tutorial.IsStepDone("opened", nil))

	-- ===== TutorialService.ReportStep on a copy with fake data =====
	local kit = Instance.new("Folder")
	kit.Name = "TutorialCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	ServerScriptService.Server.Services.TutorialService:Clone().Parent = services
	kit.Parent = ServerScriptService

	local ok, err = pcall(function()
		local store: { [string]: any } = { p = newData() }
		local fake = {}
		function fake.Get(p)
			return store[p] and deepCopy(store[p])
		end
		function fake.Set(p, path, value)
			local parts = string.split(path, ".")
			local node = store[p]
			for i = 1, #parts - 1 do
				node = node[parts[i]]
			end
			node[parts[#parts]] = value
			return true
		end
		local Service = require(services.TutorialService)
		Service.Init({ DataService = fake })
		local player = "p"

		check("ReportStep: an unproven step is refused (notDone)", select(2, Service.ReportStep(player, "opened")) == "notDone" and store.p.tutorial.step == 0)
		check("ReportStep: an unknown step is refused", select(2, Service.ReportStep(player, "nope")) == "unknownStep")
		check("ReportStep: 'done' too early is refused (notFinished)", select(2, Service.ReportStep(player, "done")) == "notFinished" and store.p.tutorial.done == false)
		store.p.inventory.a = { state = "Dirty" }
		check("ReportStep: a proven step is saved", Service.ReportStep(player, "opened") == true and store.p.tutorial.step == 1)
		check("ReportStep: the step never goes backwards", Service.ReportStep(player, "opened") == true and store.p.tutorial.step == 1)
		store.p.inventory.a.state = "Displayed"
		Service.ReportStep(player, "displayed")
		check("ReportStep: reporting a later step jumps ahead only when proven", store.p.tutorial.step == 3)
		store.p.stats.sold = 1
		check("ReportStep: 'done' after the last step finishes the tutorial", Service.ReportStep(player, "done") == true and store.p.tutorial.done == true)
		check("ReportStep: after done everything is refused (alreadyDone)", select(2, Service.ReportStep(player, "sold")) == "alreadyDone")

		store.q = newData()
		check("ReportStep: skip works at any time", Service.ReportStep("q", "skip") == true and store.q.tutorial.done == true)
		check("ReportStep: a player with no data is refused (notLoaded)", select(2, Service.ReportStep("nobody", "skip")) == "notLoaded")
	end)

	kit:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[TutorialCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return TutorialCheck
