-- Main.server.luau (ServerScriptService.Server.Main, a Script)
-- Purpose: loads every service in a fixed order, then calls Init on all, then Start on all (docs/03 §4).
-- Owner: Dev 1 (Ace). Depends on: Shared.Remotes and every module in Services/.
-- Why two passes: Init wires services together (no waiting on others), Start connects events,
-- so by the time any Start runs, every service already exists.

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
	"UpgradeService",
	"ShopSocialService",
}

local servicesFolder = script.Parent:WaitForChild("Services")
local services = {}

for _, name in ORDER do
	services[name] = require(servicesFolder:WaitForChild(name))
end

for _, name in ORDER do
	services[name].Init(services)
end

for _, name in ORDER do
	services[name].Start()
end

if DEBUG then
	print(`[Main] server ready, {#ORDER} services started`)
end
