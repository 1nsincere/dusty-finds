-- DecorRooms.luau (ReplicatedStorage.Shared.Config.DecorRooms)
-- Purpose: the decor rooms of the Warehouse Market (upstairs). Decor upgrades (Config/Upgrades, tab "Decor") have a `room` and can only be
-- bought at that room's counter (Studio: parts tagged "DecorStall" with the attribute Room = the room id), while the market is open.
-- Data only. Owner: Dev 1 (Ace). Read by: ShopController, DecorStallController (client), UpgradeService (server).

local DecorRooms = {}

DecorRooms.TAB = "Decor" -- the Upgrades tab that is only shown at a counter
DecorRooms.BuyMaxStuds = 18 -- how close a player must be to the room's counter to buy (the server checks it)
DecorRooms.TAG = "DecorStall" -- CollectionService tag on the counter part (attribute Room = the room id below)

-- id -> display name. A room with no decor pieces yet says "Coming soon" at its counter.
DecorRooms.ROOMS = {
	CozyLiving = { name = "Cozy Living" },
	KitchenNook = { name = "Kitchen Nook" },
	GalleryStudy = { name = "Gallery & Study" },
}

return DecorRooms
