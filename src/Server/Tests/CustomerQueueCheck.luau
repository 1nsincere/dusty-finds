-- CustomerQueueCheck.luau (ServerScriptService.Server.Tests.CustomerQueueCheck)
-- Purpose: exercise WP1 route outcomes and queue geometry without starting services or loading profiles.
-- Owner: Dev 3 (Sean), staged by Dev 2. Depends on: CustomerNpcService and the server Lib folder.

local ServerScriptService = game:GetService("ServerScriptService")
local CustomerQueueCheck = {}

function CustomerQueueCheck.run()
	local lines = {}
	local passed, failed = 0, 0
	local function check(label: string, ok: boolean, detail: any?)
		if ok then
			passed += 1
			table.insert(lines, "PASS " .. label)
		else
			failed += 1
			table.insert(lines, "FAIL " .. label .. (if detail ~= nil then ": " .. tostring(detail) else ""))
		end
	end

	local root = ServerScriptService.Server
	local kit = Instance.new("Folder")
	kit.Name = "CustomerQueueCheckKit"
	kit.Parent = ServerScriptService
	local services = Instance.new("Folder")
	services.Parent = kit
	root.Lib:Clone().Parent = kit
	local clonedService = root.Services.CustomerNpcService:Clone()
	clonedService.Parent = services

	local ok, err = pcall(function()
		local service = require(clonedService)
		local ownerA, ownerB = {}, {}
		local records = {
			[ownerA] = { first = { reservation = "shelf1" }, next = { reservation = "shelf2" } },
			[ownerB] = { first = { reservation = "shelf3" } },
		}
		local calls = {}
		service.Init({
			CustomerService = {
				Leave = function(owner, id, reason)
					table.insert(calls, { owner = owner, id = id, reason = reason })
					records[owner][id] = nil
				end,
			},
		})

		local target = Vector3.new(0, 0, 10)
		local npc = { player = ownerA, id = "first", gone = false }
		local attempts = 0
		local reached = service._walkTo(npc, target, false, function()
			attempts += 1
			return if attempts == 1 then "failed" else "reached"
		end)
		check("retry succeeds without Leave", reached and attempts == 2 and #calls == 0)

		attempts = 0
		reached = service._walkTo(npc, target, false, function()
			attempts += 1
			return "failed"
		end)
		check("failed visit stops after two attempts", not reached and attempts == 2)
		local departure = calls[1]
		check("failed visit requests exactly one normal Leave for its reservation", #calls == 1
			and departure.owner == ownerA and departure.id == "first" and departure.reason == "pathBlocked"
			and records[ownerA].first == nil)
		check("next customer and second shop remain untouched", records[ownerA].next.reservation == "shelf2"
			and records[ownerB].first.reservation == "shelf3")

		attempts = 0
		reached = service._walkTo(npc, target, true, function()
			attempts += 1
			return "failed"
		end)
		check("blocked exit stops without a second Leave", not reached and attempts == 2 and #calls == 1)

		attempts = 0
		reached = service._walkTo(npc, target, false, function()
			attempts += 1
			npc.gone = true
			return "failed"
		end)
		check("removal during path computation cancels without retry or Leave", not reached and attempts == 1 and #calls == 1)
		reached = service._walkTo(npc, target, false, function()
			error("a gone NPC must never start walking")
		end)
		check("a removed visit cannot start another walk", not reached and #calls == 1)

		local function plot(name, spot, counterPosition)
			local model = Instance.new("Model")
			model.Name = name
			model.Parent = kit
			local counter = Instance.new("Part")
			counter.Name = "Counter"
			counter.Position = counterPosition
			counter.Parent = model
			local markers = Instance.new("Folder")
			markers.Name = "CustomerPath"
			markers.Parent = model
			local marker = Instance.new("Part")
			marker.Name = "CounterSpot"
			marker.Position = spot
			marker.Parent = markers
			return model
		end
		local a = plot("A", Vector3.new(0, 0, 10), Vector3.new(0, 1, 12))
		local b = plot("B", Vector3.new(30, 0, -10), Vector3.new(30, 1, -12))
		check("first spot is the till marker", service._queuePoint(a, 1) == target)
		check("six queue spots stay spaced behind the till", service._queuePoint(a, 6) == Vector3.new(0, 0, -2.5))
		check("rotation reverses the line in the neighboring shop", service._queuePoint(b, 6) == Vector3.new(30, 0, 2.5))
		local empty = Instance.new("Model")
		empty.Parent = kit
		check("missing till marker has no queue point", service._queuePoint(empty, 1) == nil)
	end)
	kit:Destroy()
	if not ok then
		check("isolated suite completed", false, err)
	end
	for _, line in lines do
		print("[CustomerQueueCheck] " .. line)
	end
	print("[CustomerQueueCheck]", passed, "passed;", failed, "failed")
	return lines, passed, failed
end

return CustomerQueueCheck
