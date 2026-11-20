-- Travel.luau (ReplicatedStorage.Shared.Config.Travel)
-- Purpose: the places the Travel menu can teleport a player to. "MyShop" is resolved by the server to the player's own
-- shop door; the others are fixed spots (the server finds clear ground near each one).
-- Owner: Dev 1 (Ace). Read by TravelService (server, decides) and TravelController (client, shows the list).

local Travel = {}

Travel.COOLDOWN = 4 -- seconds between teleports per player

-- order = the order in the menu
Travel.PLACES = {
	{ id = "MyShop", name = "My Shop", hint = "Back to your restoration shop" },
	-- `at` = a point ON the ground (its Y is the floor height); the server lands you on clear floor 4-10 studs from it.
	{ id = "Plaza", name = "Town Plaza", hint = "Fountain, palm trees, the Domed Hall", at = Vector3.new(-80, 17.6, -22) },
	{ id = "Warehouse", name = "Warehouse", hint = "Order supply crates", at = Vector3.new(-65, 4, 219) },
	{ id = "Museum", name = "Museum", hint = "Your Collection Book pedestal", at = Vector3.new(-80, 26, 90) },
	{ id = "Jeepney", name = "Jeepney Terminal", hint = "Ride the jeepney loop", at = Vector3.new(15, 0.75, -334) },
	{ id = "TODA", name = "TODA Tricycles", hint = "Ride a tricycle", at = Vector3.new(127, 0.6, -378) },
}

return Travel
