-- AdminService.luau
-- Purpose: owner/admin chat commands that work in the LIVE game (cash, levels, XP, items, relics, boxes, upgrades,
-- teleports) on yourself or on other players. Only user IDs listed in Shared.Config.Admins can run them: the server
-- checks the speaker's UserId on every command, so other players typing them get nothing.
-- Owner: Dev 1 (Ace). Depends on: TextChatService (server-side TextChatCommands), DataService, EconomyService,
-- InventoryService, ShipmentService, PlotService, Shared.Config (Admins, Items, Crates, Upgrades, Economy), Remotes.Notify.
-- Targets: me | all | others | a name (start of username or display name, case-insensitive).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Admins = require(Config:WaitForChild("Admins"))
local Items = require(Config:WaitForChild("Items"))
local Crates = require(Config:WaitForChild("Crates"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Economy = require(Config:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Log = require(script.Parent.Parent.Lib.Log)

local AdminService = {}
local DEBUG = true
local log = Log.new("AdminService", DEBUG)
local S: { [string]: any } = {}

local function tell(admin: Player, text: string)
	Remotes.Notify:FireClient(admin, "Info", text)
end

-- "me" | "all" | "others" | name prefix -> list of players
local function targets(admin: Player, word: string?): { Player }
	word = string.lower(word or "me")
	if word == "me" then
		return { admin }
	end
	local list = {}
	for _, p in Players:GetPlayers() do
		if word == "all" or (word == "others" and p ~= admin)
			or string.sub(string.lower(p.Name), 1, #word) == word or string.sub(string.lower(p.DisplayName), 1, #word) == word then
			table.insert(list, p)
		end
	end
	return list
end

-- item id or display name (start of either, case-insensitive)
local function findItem(word: string?): string?
	if not word then
		return nil
	end
	local w = string.lower(word)
	for id, def in Items do
		if string.lower(id) == w then
			return id
		end
	end
	for id, def in Items do
		if string.sub(string.lower(id), 1, #w) == w or (def.name and string.find(string.lower(def.name), w, 1, true)) then
			return id
		end
	end
	return nil
end

local function giveRestored(p: Player, itemId: string, stars: number, golden: boolean): boolean
	local uid = S.InventoryService.Add(p, itemId, { state = "Restored", golden = golden })
	if not uid then
		return false
	end
	S.InventoryService.Update(p, uid, { stars = stars })
	return true
end

local function itemsOfRarity(rarity: string): { string }
	local list = {}
	for id, def in Items do
		if def.rarity == rarity then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

local function each(admin: Player, who: string?, fn: (Player) -> boolean?): number
	local list = targets(admin, who)
	if #list == 0 then
		tell(admin, "No player matches \"" .. tostring(who) .. "\"")
		return 0
	end
	local n = 0
	for _, p in list do
		if S.DataService.IsLoaded(p) and fn(p) ~= false then
			n += 1
		end
	end
	return n
end

local function whole(text: string?, min: number, max: number): number?
	local n = tonumber(text)
	if n == nil or n ~= n or n % 1 ~= 0 or n < min or n > max then
		return nil
	end
	return n
end

-- ===== the commands: name -> { usage, fn(admin, args) } =====
local COMMANDS: { [string]: { usage: string, run: (Player, { string }) -> () } } = {}

COMMANDS.cash = { usage = "/cash <who> <amount>  (negative takes money)", run = function(admin, a)
	local amount = whole(a[2], -1e9, 1e9)
	if not amount then return tell(admin, COMMANDS.cash.usage) end
	local n = each(admin, a[1], function(p)
		if amount >= 0 then
			return S.EconomyService.AddCash(p, amount, "Admin")
		end
		local cash = S.EconomyService.GetCash(p) or 0
		return S.DataService.Set(p, "cash", math.max(0, cash + amount))
	end)
	tell(admin, string.format("Cash %+d to %d player(s)", amount, n))
end }

COMMANDS.setcash = { usage = "/setcash <who> <amount>", run = function(admin, a)
	local amount = whole(a[2], 0, 1e12)
	if not amount then return tell(admin, COMMANDS.setcash.usage) end
	local n = each(admin, a[1], function(p) return S.DataService.Set(p, "cash", amount) end)
	tell(admin, string.format("Cash set to $%d for %d player(s)", amount, n))
end }

COMMANDS.level = { usage = "/level <who> <1-" .. Economy.MaxLevel .. ">", run = function(admin, a)
	local level = whole(a[2], 1, Economy.MaxLevel)
	if not level then return tell(admin, COMMANDS.level.usage) end
	local n = each(admin, a[1], function(p)
		S.DataService.Set(p, "xp", 0)
		return S.DataService.Set(p, "level", level)
	end)
	tell(admin, string.format("Level %d for %d player(s)", level, n))
end }

COMMANDS.xp = { usage = "/xp <who> <amount>  (level-ups + rewards happen)", run = function(admin, a)
	local amount = whole(a[2], 1, 1e9)
	if not amount then return tell(admin, COMMANDS.xp.usage) end
	local n = each(admin, a[1], function(p) return (S.EconomyService.AddXp(p, amount)) end)
	tell(admin, string.format("+%d XP for %d player(s)", amount, n))
end }

COMMANDS.give = { usage = "/give <who> <item> [stars 1-3] [golden]  (restored, ready to sell)", run = function(admin, a)
	local itemId = findItem(a[2])
	if not itemId then return tell(admin, "Unknown item \"" .. tostring(a[2]) .. "\". Try /items") end
	local stars = whole(a[3], 1, 3) or 3
	local golden = a[4] ~= nil and string.lower(a[4]) == "golden"
	local n = each(admin, a[1], function(p) return giveRestored(p, itemId, stars, golden) end)
	tell(admin, string.format("Gave %s%s %d★ to %d player(s)", if golden then "Golden " else "", Items[itemId].name or itemId, stars, n))
end }

COMMANDS.giveraw = { usage = "/giveraw <who> <item>  (dirty, needs restoring)", run = function(admin, a)
	local itemId = findItem(a[2])
	if not itemId then return tell(admin, "Unknown item. Try /items") end
	local n = each(admin, a[1], function(p) return S.InventoryService.Add(p, itemId, { state = "Dirty" }) ~= nil end)
	tell(admin, string.format("Gave dirty %s to %d player(s)", Items[itemId].name or itemId, n))
end }

COMMANDS.relic = { usage = "/relic <who> [item]  (golden 3★ Relic; random if no item)", run = function(admin, a)
	local relics = itemsOfRarity("Relic")
	local chosen = findItem(a[2])
	local n = each(admin, a[1], function(p)
		local id = chosen or relics[math.random(1, #relics)]
		return giveRestored(p, id, 3, true)
	end)
	tell(admin, string.format("Relic given to %d player(s)", n))
end }

COMMANDS.rarity = { usage = "/rarity <who> <Common|Uncommon|Rare|Epic|Legendary|Relic|Mythic|Secret>  (one of each, 3★)", run = function(admin, a)
	local wanted = a[2] and (string.upper(string.sub(a[2], 1, 1)) .. string.lower(string.sub(a[2], 2))) or ""
	local list = itemsOfRarity(wanted)
	if #list == 0 then return tell(admin, COMMANDS.rarity.usage) end
	local n = each(admin, a[1], function(p)
		for _, id in list do giveRestored(p, id, 3, false) end
		return true
	end)
	tell(admin, string.format("%d %s item(s) each to %d player(s)", #list, wanted, n))
end }

COMMANDS.box = { usage = "/box <who> <crateId>", run = function(admin, a)
	local crateId
	for id in Crates do
		if a[2] and string.lower(id) == string.lower(a[2]) then crateId = id end
	end
	if not crateId then
		local ids = {}
		for id in Crates do table.insert(ids, id) end
		return tell(admin, "Crates: " .. table.concat(ids, ", "))
	end
	local n = each(admin, a[1], function(p)
		local boxId = HttpService:GenerateGUID(false)
		for _ = 1, Crates[crateId].itemCount do
			local itemId, golden = S.ShipmentService.RollItem(crateId)
			if itemId then
				S.InventoryService.Add(p, itemId, { state = "Unopened", golden = golden, crateId = crateId, boxId = boxId })
			end
		end
		return true
	end)
	tell(admin, string.format("%s box to %d player(s)", crateId, n))
end }

COMMANDS.maxupgrades = { usage = "/maxupgrades <who>", run = function(admin, a)
	local n = each(admin, a[1], function(p)
		for id, def in Upgrades do
			S.DataService.Set(p, "upgrades." .. id, def.maxLevel)
		end
		S.PlotService.RefreshSlots(p)
		return true
	end)
	tell(admin, string.format("Max upgrades for %d player(s)", n))
end }

COMMANDS["goto"] = { usage = "/goto <who>  (you go to them)", run = function(admin, a)
	local target = targets(admin, a[1])[1]
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root or not admin.Character then return tell(admin, "Can't find that player") end
	admin.Character:PivotTo(root.CFrame * CFrame.new(0, 0, 4))
end }

COMMANDS.bring = { usage = "/bring <who>  (they come to you)", run = function(admin, a)
	local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local n = each(admin, a[1], function(p)
		if p ~= admin and p.Character then
			p.Character:PivotTo(root.CFrame * CFrame.new(math.random(-4, 4), 0, -4))
			return true
		end
		return false
	end)
	tell(admin, string.format("Brought %d player(s)", n))
end }

-- Sean (Dev 3): give shelf / pedestal skins (Config.Skins) for free. A set name gives both pieces of the set
-- (e.g. "cosmic" = ShelfCosmic + PedestalCosmic); add "use" to put them on straight away.
COMMANDS.skin = { usage = "/skin <who> <skin|set|all> [use]  (e.g. /skin me cosmic use; /skins lists them)", run = function(admin, a)
	local Skins = require(Config:WaitForChild("Skins"))
	local word = string.lower(a[2] or "")
	if word == "" then return tell(admin, COMMANDS.skin.usage) end
	local ids = {}
	for _, skin in Skins.LIST do
		local id = string.lower(skin.id)
		-- exact id ("shelfcosmic"), set name ("cosmic" matches Shelf/PedestalCosmic) or "all"
		if word == "all" or id == word or id == "shelf" .. word or id == "pedestal" .. word or id == "cashier" .. word then
			table.insert(ids, skin.id)
		end
	end
	if #ids == 0 then return tell(admin, "Unknown skin \"" .. tostring(a[2]) .. "\". Try /skins") end
	local use = a[3] ~= nil and string.lower(a[3]) == "use" and word ~= "all"
	local n = each(admin, a[1], function(p)
		for _, id in ids do
			if not (S.SkinService.Grant(p, id, use)) then
				return false
			end
		end
		return true
	end)
	tell(admin, string.format("Gave %s%s to %d player(s)", table.concat(ids, ", "), if use then " (in use)" else "", n))
end }

COMMANDS.skins = { usage = "/skins  (list skin ids)", run = function(admin)
	local Skins = require(Config:WaitForChild("Skins"))
	local byRarity = {}
	for _, skin in Skins.LIST do
		byRarity[skin.rarity] = byRarity[skin.rarity] or {}
		table.insert(byRarity[skin.rarity], skin.id)
	end
	for _, r in { "Mythic", "Relic", "Legendary", "Epic", "Rare", "Uncommon", "Common" } do
		if byRarity[r] then
			tell(admin, r .. ": " .. table.concat(byRarity[r], ", "))
		end
	end
end }

COMMANDS.items = { usage = "/items", run = function(admin)
	local byRarity = {}
	for _, r in { "Secret", "Mythic", "Relic", "Legendary", "Epic", "Rare", "Uncommon", "Common" } do
		table.insert(byRarity, r .. ": " .. table.concat(itemsOfRarity(r), ", "))
	end
	for _, line in byRarity do
		tell(admin, line)
	end
end }

COMMANDS.admin = { usage = "/admin", run = function(admin)
	-- one short toast per command (long toasts get cut off): its usage line
	local names = {}
	for name in COMMANDS do table.insert(names, name) end
	table.sort(names)
	tell(admin, "ADMIN COMMANDS (who = me, all, others or a name):")
	for _, name in names do
		tell(admin, COMMANDS[name].usage)
	end
end }

local function run(admin: Player, name: string, text: string)
	if Admins[admin.UserId] == nil then
		return -- not an admin: silently ignored
	end
	local cmd = COMMANDS[name]
	if not cmd then
		return
	end
	local args = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(args, word)
	end
	table.remove(args, 1) -- the "/name" itself
	local ok, err = pcall(cmd.run, admin, args)
	if not ok then
		tell(admin, "Error: " .. tostring(err))
	end
	log.info(admin.Name, "ran", text)
end

function AdminService.Init(services)
	S = services
	log.info("Init")
end

function AdminService.Start()
	-- Server-created TextChatCommands: Triggered fires here on the server with the speaker; the text is not posted to chat.
	local folder = TextChatService:FindFirstChild("AdminCommands") or Instance.new("Folder")
	folder.Name = "AdminCommands"
	folder.Parent = TextChatService
	for name in COMMANDS do
		local alias = "/" .. name
		local existing = folder:FindFirstChild(name)
		local command = existing or Instance.new("TextChatCommand")
		command.Name = name
		command.PrimaryAlias = alias
		command.Parent = folder
		command.Triggered:Connect(function(source: TextSource, text: string)
			local admin = Players:GetPlayerByUserId(source.UserId)
			if admin then
				run(admin, name, text)
			end
		end)
	end
	log.info("Start: admin commands for", #(function() local t = {} for id in Admins do table.insert(t, id) end return t end)(), "admin(s)")
end

return AdminService
