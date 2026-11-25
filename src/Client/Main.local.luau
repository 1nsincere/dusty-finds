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
-- the loading screen (ReplicatedFirst.Loading.LoadingScreen) watches these local attributes to fill its bar
-- (Sean, 2026-11-25; keep these when merging Main.local: without them the loading screen waits its full 40 s)
local LocalPlayer = game:GetService("Players").LocalPlayer
LocalPlayer:SetAttribute("DF_SfxOn", ClientState.Get("settings.sfx") ~= false) -- its sound effects follow Settings
LocalPlayer:SetAttribute("DF_SaveLoaded", true)

local ORDER = {
	"SoundController", -- Dev 1: music, ambience, UI + game sounds (Config.Sounds); first so other controllers can call it
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
	"AdminPanelController", -- Dev 1: the /admin card (AdminPanel remote shows every command + what it does)
	"RestorationMoreMinigamesController", -- Dev 1: Test, Scrape, Reassemble, Replace minigames (Dwayne registers Wipe/Polish in his own controller)
	"MuseumController", -- Dev 1: the museum Collection pedestal opens the Collection Book
	"WarehouseController", -- Dev 1: the Warehouse supply counter opens the Supply screen (crates are sold only there)
	"MyShopController", -- Dev 1 (Sean approved): 🏠 My Shop HUD button, teleports you back to your own shop (RequestVisit)
	"LightingController", -- Dev 1: day/night cycle, night lamps and window glow (Config.DayNight)
	"CashierController", -- Dev 1: the till screen (count out the change; CashierUpdate / RequestGiveChange)
	"HudSkinController", -- Dev 1: HUD/window/toast skin (warm walnut look, Config.UiSkin); restyle only
	"TravelController", -- Dev 1: Travel menu (map-pin HUD button -> RequestTravel)
	"PlayerListController", -- Dev 1: our own player list (Roblox's is switched off); Players HUD tile / Tab key. Needs HudSkinController first, HudLayoutController after
	"SprintController", -- Dev 1: hold Shift / lightning button to sprint
	"AutoRunController", -- Dev 1: Auto Run (Menu switch / R key): keep walking forward until you take over
	"HudLayoutController", -- Dev 1: Figma HUD layout: status plate, rails, Menu flyout, chips, notification dock (after the controllers that add HUD buttons)
	"TownsfolkController", -- Sean: ambient townspeople walking the streets (client-only decoration, Config.Townsfolk)
	"StorageShelfController", -- Sean: draws unrestored items on every shop's storage room shelves (StorageShelfService)
	"EditModeController", -- Sean: shop edit mode, move / turn shelves and pedestals (Shared.Layout; docs/09); after HudSkinController
	"PaintShopController", -- Dev 1: Paint Bar window (wall / floor paints, always in stock; Workspace.PaintCounter prompt)
	"SkinShopController", -- Sean: skins stall window (stock, restock timer, buy) + your skins (apply); sparkles off with Reduce effects
	"SkinModelController", -- Sean: draws model skins (Assets.Skins) over the shelf / pedestal blocks on this screen, with light + aura
	"MainMenuController", -- Sean: title menu after the loading screen (PLAY / Settings / Updates / Credits); last: hides the HUD until PLAY
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
LocalPlayer:SetAttribute("DF_ClientReady", true)

if DEBUG then
	print(`[Main] client ready, {#ORDER} controllers started`)
end
