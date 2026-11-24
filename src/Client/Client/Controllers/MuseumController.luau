-- MuseumController.luau
-- Purpose: the Museum of Restored Things on Workshop Lane: its Collection pedestal opens Sean's Collection Book.
-- Owner: Dev 1 (Ace) with Dev 3's CollectionController. Depends on: CollectionController.Open (Sean), the pedestal prompt at
-- Workspace.Environment.Districts.Museum.CollectionPedestal (Ace's Studio art: PromptAnchor.CollectionPrompt).
-- Client only. No remote, no data: the Collection Book already reads everything from ClientState, so nothing can be exploited here.

local MuseumController = {}
local DEBUG = true

local others: { [string]: any } = {}

function MuseumController.Init(controllers: { [string]: any })
	others = controllers
end

function MuseumController.Start()
	task.spawn(function()
		local env = workspace:WaitForChild("Environment", 20)
		local districts = env and env:WaitForChild("Districts", 20)
		local museum = districts and districts:WaitForChild("Museum", 20)
		local pedestal = museum and museum:WaitForChild("CollectionPedestal", 20)
		local anchor = pedestal and pedestal:WaitForChild("PromptAnchor", 20)
		local prompt = anchor and anchor:WaitForChild("CollectionPrompt", 20)
		if prompt == nil then
			warn("[MuseumController] Museum.CollectionPedestal prompt not found: the museum does nothing")
			return
		end
		prompt.Triggered:Connect(function()
			local collection = others.CollectionController
			if collection and type(collection.Open) == "function" then
				collection.Open()
			end
		end)
		if DEBUG then
			print("[MuseumController] ready: Collection pedestal at the museum")
		end
	end)
end

return MuseumController
