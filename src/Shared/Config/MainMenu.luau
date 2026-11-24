-- MainMenu.luau (ReplicatedStorage.Shared.Config.MainMenu)
-- Purpose: what the title menu shows (MainMenuController): the version label, the "What's New" updates list (newest
-- first; the first line of the newest one goes on the pinned note) and the credits (user IDs: the menu looks up each
-- dev's current Roblox username live and falls back to `name`).
-- Owner: Dev 3 (Sean). Depends on: nothing.

local MainMenu = {}

MainMenu.VERSION = "v0.9"

MainMenu.UPDATES = {
	{
		title = "Sakura Starlight",
		date = "Nov 25",
		lines = {
			"New: Sakura Starlight skins!",
			"Shelf, pedestal and counter in rose quartz, with floating pink diamonds.",
			"A brand-new loading screen and this main menu.",
		},
	},
	{
		title = "Counter skins",
		date = "Nov 24",
		lines = {
			"Skins for your cash counter: 10 styles from Painted Pine to Cosmic Harmony.",
			"The skins stall now has tabs: Pedestals, Shelves, Cashiers and Owned.",
		},
	},
	{
		title = "Skins stall",
		date = "Nov 24",
		lines = {
			"Buy shelf and pedestal skins at the stall in the Warehouse square.",
			"New stock every 5 minutes.",
		},
	},
}

MainMenu.CREDITS = {
	{ userId = 2515374038, name = "X3duactive", role = "Systems & Data" },
	{ userId = 3782711171, name = "dwayne_xbvuvu", role = "Restoration & Items" },
	{ userId = 852433571, name = "iizxeroo", role = "World, Customers & UI" },
}

return MainMenu
