-- Remotes.luau (ReplicatedStorage.Shared.Remotes)
-- Purpose: the ONE place every RemoteEvent/RemoteFunction is declared (docs/03_Architecture.md §6).
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- The server creates them inside ReplicatedStorage.Remotes; the client waits for them and uses the same names.
-- Adding a remote = add its name below AND update docs/03_Architecture.md §6.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEBUG = true

-- Client -> Server requests (server must validate every one; handlers come with each feature)
local CLIENT_TO_SERVER = {
	"RequestOpenBox",
	"RequestBuyCrate",
	"RequestClaimFreeDelivery",
	"RequestStartRestore",
	"ReportStepComplete",
	"RequestExitRestore",
	"RequestPlaceDisplay",
	"RequestPlaceExhibit",
	"RequestRemoveFromSlot",
	"RequestCheckout",
	"RequestQuickSell",
	"RequestBuyUpgrade",
	"RequestLikeShop",
	"RequestVisit",
	"RequestSaveSettings",
	"RequestTutorialStep",
	"RequestGiveChange", -- cashier: (amount) the change the owner counted out for the customer at the till
	"RequestCloseCashier", -- cashier: owner closed the till window (the customer keeps waiting / auto-checks out)
	"RequestTravel", -- travel menu: (placeId) teleport to a Config.Travel place (server checks id, cooldown, state)
	"RequestBuySkin", -- skins stall: (skinId) buy a skin that is in stock right now (server checks stock, owned, cash, distance)
	"RequestApplySkin", -- skins: (kind "Shelf"|"Pedestal", skinId or "" for classic) use an owned skin in your shop
}

-- Server -> Client notifications
local SERVER_TO_CLIENT = {
	"StateChanged",
	"Notify",
	"BoxOpened",
	"RestoreSession",
	"ItemRestored",
	"SaleMade",
	"Announcement",
	"CashierUpdate", -- cashier: { state = "open"|"wrong"|"done"|"closed", due, paid, item, attempts }
}

-- The only RemoteFunction we allow (client asks once for its full data after the profile loads)
local FUNCTIONS = {
	"GetInitialState",
}

local FOLDER_NAME = "Remotes"
local Remotes = {}

local folder
if RunService:IsServer() then
	-- Server creates the remotes once, so every player sees the same objects.
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local function make(className: string, name: string)
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
	for _, name in CLIENT_TO_SERVER do make("RemoteEvent", name) end
	for _, name in SERVER_TO_CLIENT do make("RemoteEvent", name) end
	for _, name in FUNCTIONS do make("RemoteFunction", name) end
	if DEBUG then
		print(`[Remotes] server created {#CLIENT_TO_SERVER + #SERVER_TO_CLIENT} events + {#FUNCTIONS} function`)
	end
else
	-- Client waits for the server to finish creating them.
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	for _, list in { CLIENT_TO_SERVER, SERVER_TO_CLIENT, FUNCTIONS } do
		for _, name in list do
			Remotes[name] = folder:WaitForChild(name)
		end
	end
	if DEBUG then
		print("[Remotes] client found all remotes")
	end
end

return Remotes
