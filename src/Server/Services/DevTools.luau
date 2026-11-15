-- DevTools.luau
-- Purpose: Studio-ONLY test commands (give cash, set level, give items or boxes, max upgrades, reset a test profile).
-- Owner: Dev 1 (Ace). Depends on: DataService, EconomyService, InventoryService, ShipmentService, PlotService, Config.
-- Does nothing outside Studio: no remote, no object, no commands. Inside Studio it creates a BindableFunction
-- ServerStorage.DevTools (never visible to clients) that you call from the command bar while Playing (Server):
--   game.ServerStorage.DevTools:Invoke("help")    -- see docs/STUDIO_TESTING.md for every command

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local DevTools = {}
local DEBUG = true
local log = Log.new("DevTools", DEBUG)

local S: { [string]: any } = {}

local commands: { [string]: any } = {} -- each command returns (ok, value)

function commands.help()
	local names = {}
	for name in commands do
		table.insert(names, name)
	end
	table.sort(names)
	return true, "commands: " .. table.concat(names, ", ")
end

-- giveCash(player, amount)
function commands.giveCash(player: Player, amount: any)
	if not Validate.isInteger(amount, 0, 1e9) then
		return false, "amount must be a whole number 0 - 1,000,000,000"
	end
	return S.EconomyService.AddCash(player, amount, "Dev"), nil
end

-- setLevel(player, level): sets level directly and clears XP (no level-up rewards)
function commands.setLevel(player: Player, level: any)
	if not Validate.isInteger(level, 1, Economy.MaxLevel) then
		return false, `level must be 1 - {Economy.MaxLevel}`
	end
	S.DataService.Set(player, "xp", 0)
	return S.DataService.Set(player, "level", level), nil
end

-- addXp(player, amount): goes through EconomyService, so level-ups and their rewards happen like in the real game
function commands.addXp(player: Player, amount: any)
	if not Validate.isInteger(amount, 0, 1e9) then
		return false, "amount must be a whole number 0 - 1,000,000,000"
	end
	return S.EconomyService.AddXp(player, amount)
end

-- giveItem(player, itemId, state?, stars?, golden?): state defaults to "Dirty"; Restored/Displayed/Exhibited get stars (default 2)
function commands.giveItem(player: Player, itemId: any, state: any, stars: any, golden: any)
	if not Validate.isConfigId(itemId, Items) then
		return false, "unknown itemId"
	end
	local itemState = state or "Dirty"
	local uid, reason = S.InventoryService.Add(player, itemId, { state = itemState, golden = golden == true })
	if uid == nil then
		return false, reason
	end
	if itemState == "Restored" or itemState == "Displayed" or itemState == "Exhibited" then
		S.InventoryService.Update(player, uid, { stars = stars or 2 })
	end
	return true, uid
end

-- giveBox(player, crateId): a rolled box of Unopened items, like a bought crate but free
function commands.giveBox(player: Player, crateId: any)
	if not Validate.isConfigId(crateId, Crates) then
		return false, "unknown crateId"
	end
	local boxId = HttpService:GenerateGUID(false)
	local uids = {}
	for _ = 1, Crates[crateId].itemCount do
		local itemId, golden = S.ShipmentService.RollItem(crateId)
		local uid = itemId and S.InventoryService.Add(player, itemId, { state = "Unopened", golden = golden, crateId = crateId, boxId = boxId })
		if uid then
			table.insert(uids, uid)
		end
	end
	return #uids > 0, uids
end

-- maxUpgrades(player): every upgrade to its max level for free (also shows decor and slots)
function commands.maxUpgrades(player: Player)
	for id, def in Upgrades do
		S.DataService.Set(player, "upgrades." .. id, def.maxLevel)
	end
	S.PlotService.RefreshSlots(player)
	return true, nil
end

-- resetProfile(player): back to a brand-new player (default data, first Rubber Duck box again). Test profiles only.
function commands.resetProfile(player: Player)
	for key, value in S.DataService.GetTemplate() do
		if key ~= "version" then
			S.DataService.Set(player, key, value)
		end
	end
	S.PlotService.RefreshSlots(player)
	S.ShipmentService.GrantFirstBox(player)
	return true, nil
end

-- dump(player): a copy of all saved data
function commands.dump(player: Player)
	return true, S.DataService.Get(player)
end

local function run(command: any, player: any, ...: any)
	if type(command) ~= "string" or commands[command] == nil then
		return false, "unknown command (try 'help')"
	end
	if command ~= "help" and not Validate.isPlayer(player) then
		return false, "second argument must be a Player"
	end
	local ok, success, value = pcall(commands[command], player, ...)
	if not ok then
		return false, "command errored: " .. tostring(success)
	end
	return success, value
end

function DevTools.Init(services)
	S = services
end

function DevTools.Start()
	if not RunService:IsStudio() then
		return -- live servers get no tools at all
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DevTools"
	fn.OnInvoke = run
	fn.Parent = ServerStorage
	log.info("Studio only: ServerStorage.DevTools ready. Try: game.ServerStorage.DevTools:Invoke('help')")
end

return DevTools
