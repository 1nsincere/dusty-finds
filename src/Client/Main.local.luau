-- Main.client.luau (StarterPlayerScripts.Client.Main, a Script with RunContext = Client)
-- Purpose: loads every controller in a fixed order, then calls Init on all, then Start on all.
-- Owner: Dev 3 (Sean) for UI controllers; Dev 1 (Ace) set up this skeleton. Depends on: Shared.Remotes, Controllers/.
-- Same two-pass pattern as the server so controllers can find each other in Init.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG = true

-- Waits until the server has created the remotes.
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

-- Load my data before any controller starts, so the HUD and menus can read it immediately.
-- If loading fails the game still starts (UI shows placeholders) instead of hanging here.
local ClientState = require(script.Parent:WaitForChild("ClientState"))
ClientState.Load()

local ORDER = {
	"HudController",
	"InventoryController",
	"DisplayController",
	"DiscoveryController",
	"RestorationController",
	"RestorationUIController", -- Sean: Restoration screen (chips, hint, progress, finish card)
	"RestorationMinigamesController", -- Dwayne: real Wipe/Polish adapters; keep with its module
	"ShopController",
	"CollectionController",
	"CustomerUIController",
	"SettingsController",
	"VisitController", -- Sean: 👥 Visit window (RequestVisit)
	"TutorialController",
	"RoofController", -- Dev 1: hides the roof of the shop you are standing in (environment pass)
	"AdminController", -- Dev 1: Studio-only dev commands (/fly, /tp, /noclip ...); does nothing on the live game
	"RestorationMoreMinigamesController", -- Dev 1: Test, Scrape, Reassemble, Replace minigames (Dwayne registers Wipe/Polish in his own controller)
	"MuseumController", -- Dev 1: the museum Collection pedestal opens the Collection Book
}

local controllersFolder = script.Parent:WaitForChild("Controllers")
local controllers = {}

for _, name in ORDER do
	controllers[name] = require(controllersFolder:WaitForChild(name))
end

for _, name in ORDER do
	controllers[name].Init(controllers)
end

for _, name in ORDER do
	controllers[name].Start()
end

if DEBUG then
	print(`[Main] client ready, {#ORDER} controllers started`)
end
