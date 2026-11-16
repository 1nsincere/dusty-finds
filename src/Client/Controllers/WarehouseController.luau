-- WarehouseController.luau
-- Purpose: the Supply Warehouse on Workshop Lane is where crates are bought: its supply counter prompt opens Sean's Supply screen.
-- Owner: Dev 1 (Ace) with Dev 3's ShopController. Depends on: ShopController.OpenSupply, the counter in Studio at
-- Workspace.Environment.Districts.Warehouse.SupplyCounter (a Part) with child ProximityPrompt "SupplyPrompt".
-- Client only. The server enforces the same distance on RequestBuyCrate (ShipmentService.IsNearSupply), so this file cannot be abused.

local WarehouseController = {}
local DEBUG = true

local others: { [string]: any } = {}

function WarehouseController.Init(controllers: { [string]: any })
	others = controllers
end

function WarehouseController.Start()
	task.spawn(function()
		local env = workspace:WaitForChild("Environment", 20)
		local districts = env and env:WaitForChild("Districts", 20)
		local warehouse = districts and districts:WaitForChild("Warehouse", 20)
		local counter = warehouse and warehouse:WaitForChild("SupplyCounter", 20)
		local prompt = counter and counter:WaitForChild("SupplyPrompt", 20)
		if prompt == nil then
			warn("[WarehouseController] Warehouse.SupplyCounter prompt not found: nobody can open the Supply screen at the warehouse")
			return
		end
		prompt.Triggered:Connect(function()
			local shop = others.ShopController
			if shop and type(shop.OpenSupply) == "function" then
				shop.OpenSupply()
			end
		end)
		if DEBUG then
			print("[WarehouseController] ready: supply counter at the warehouse")
		end
	end)
end

return WarehouseController
