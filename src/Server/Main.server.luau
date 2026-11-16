-- Main.server.luau (ServerScriptService.Server.Main, a Script)
-- Purpose: loads every service in a fixed order, then calls Init on all, then Start on all (docs/03 §4).
-- Owner: Dev 1 (Ace). Depends on: Shared.Remotes and every module in Services/.
-- Why two passes: Init wires services together (no waiting on others), Start connects events,
-- so by the time any Start runs, every service already exists.
-- Every step is wrapped in pcall: one broken service prints a red error and is skipped, instead of a syntax error in
-- (say) a test tool stopping the whole server from booting. Check Output for "[Main] FAILED" after every change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG = true

-- Create the remotes first so they exist before any service or client needs them.
require(ReplicatedStorage.Shared.Remotes)

-- Order matters: later services may depend on earlier ones.
local ORDER = {
	"DataService",
	"PlotService",
	"EconomyService",
	"InventoryService",
	"CollectionBookService",
	"ShipmentService",
	"RestorationService",
	"DisplayService",
	"CustomerService",
	"CustomerNpcService", -- Sean: customer models/walking/checkout prompt; reacts to CustomerService
	"UpgradeService",
	"ShopSocialService",
	"SettingsService",
	"TutorialService", -- Sean: saves tutorial.step/done (RequestTutorialStep), checked against Shared.Tutorial
	"DevTools", -- Studio only: does nothing on live servers
}

local servicesFolder = script.Parent:WaitForChild("Services")
local services = {}
local failed: { [string]: boolean } = {}

local function fail(name: string, step: string, err: any)
	failed[name] = true
	services[name] = nil
	warn(`[Main] FAILED {step} of {name}: {tostring(err)}`)
end

for _, name in ORDER do
	local ok, result = pcall(function()
		return require(servicesFolder:WaitForChild(name))
	end)
	if ok then
		services[name] = result
	else
		fail(name, "load", result)
	end
end

for _, name in ORDER do
	if not failed[name] then
		local ok, err = pcall(services[name].Init, services)
		if not ok then
			fail(name, "Init", err)
		end
	end
end

for _, name in ORDER do
	if not failed[name] then
		local ok, err = pcall(services[name].Start)
		if not ok then
			fail(name, "Start", err)
		end
	end
end

if DEBUG then
	local started = 0
	for _, name in ORDER do
		if not failed[name] then
			started += 1
		end
	end
	print(`[Main] server ready, {started}/{#ORDER} services started`)
end
