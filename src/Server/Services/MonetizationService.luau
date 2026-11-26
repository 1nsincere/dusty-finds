-- MonetizationService.luau (ServerScriptService.Server.Services.MonetizationService)
-- Purpose: everything Robux (docs/11, docs/12 Stage 5, approved by Ace 2026-11-25): opens the Roblox purchase prompt for a pass or
-- a tip (RequestPurchasePass / RequestPurchaseProduct), checks with Roblox that a pass is really owned, saves it as
-- data.entitlements, hands out what a pass includes (theme paints + skins), keeps the VIP cosmetic choices (RequestSetVip) and
-- publishes the cosmetics other players can see (Player attributes DF_VIP, DF_Pet, DF_PetColor, DF_Title, DF_AuraStyle,
-- DF_Glow). The tip jar thanks the player and gives nothing else.
-- Owner: Dev 1 (Ace). Depends on: DataService, Shared.Config.Monetization, MarketplaceService (replaceable for tests), TextService
-- (title filter).
--
-- Rules (docs/11): server-authoritative. The CLIENT only asks; the pass is saved only after Roblox says the player owns it.
-- Nothing here changes cash, XP, speed or odds. A pass id of 0 in the config = not created on Roblox yet: refused as comingSoon.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Config = require(ReplicatedStorage.Shared.Config.Monetization)
local Skins = require(ReplicatedStorage.Shared.Config.Skins)

local DEVELOPER_TITLE_USER_ID = 2515374038

local MonetizationService = {}
local DEBUG = true
local log = Log.new("MonetizationService", DEBUG)

local DataService = nil
local market: any = MarketplaceService -- tests swap this for a fake (SetMarketplace)
local thanked: { [any]: boolean } = {} -- PurchaseId -> already thanked this session

local playerById = function(userId: number): any
	return Players:GetPlayerByUserId(userId)
end

-- Tests only: swap Roblox's purchase API and the player lookup for fakes on their own copy of this service.
function MonetizationService.SetMarketplace(fake: any?, lookup: ((number) -> any)?)
	market = fake or MarketplaceService
	if lookup then
		playerById = lookup
	end
end

local function notify(player: any, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, "Info", text)
	end
end

-- ===== Ownership =====

function MonetizationService.Has(player: any, passId: string): boolean
	local entitlements = DataService.GetValue(player, "entitlements")
	return type(entitlements) == "table" and entitlements[passId] == true
end

-- What other players can see (attributes replicate to everyone). Called whenever a pass or a VIP choice changes.
function MonetizationService.PublishCosmetics(player: any)
	if not Validate.isPlayer(player) then
		return
	end
	local vip = MonetizationService.Has(player, "VIP")
	local vipData = DataService.GetValue(player, "vip")
	vipData = if type(vipData) == "table" then vipData else {}
	local pet = nil
	if vip and vipData.pet ~= "" and vipData.pet ~= nil then
		pet = vipData.pet
	elseif vip or MonetizationService.Has(player, "Companion") then
		pet = "Cat" -- the Companion pass (or VIP before choosing) comes with a default friend
	end
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("DF_VIP", if vip then true else nil)
	set("DF_OneOfOne", if player.UserId == DEVELOPER_TITLE_USER_ID then true else nil)
	set("DF_Pet", pet)
	set("DF_PetColor", if pet and vipData.petColor ~= "" then vipData.petColor else nil)
	set("DF_Title", if vip and vipData.title ~= "" then vipData.title else nil)
	set("DF_AuraStyle", if vip and vipData.auraStyle ~= "" then vipData.auraStyle else nil)
	set("DF_Glow", if MonetizationService.Has(player, "GlowPack") then true else nil)
end

-- Saves the pass and gives what it includes. Safe to call twice. `silent` = no thank-you (the join-time re-check).
-- Returns ok, reason ("unknown", "noData", "saveFailed").
function MonetizationService.Grant(player: any, passId: string, silent: boolean?): (boolean, string?)
	local pass = Config.BY_PASS[passId]
	if pass == nil then
		return false, "unknown"
	end
	local entitlements = DataService.GetValue(player, "entitlements")
	if type(entitlements) ~= "table" then
		return false, "noData"
	end
	local already = entitlements[passId] == true
	if not already and not DataService.Set(player, "entitlements." .. passId, true) then
		return false, "saveFailed"
	end
	-- theme passes include paints and skins (put in the Owned tabs; the player chooses when to use them)
	if pass.grants then
		for _, id in pass.grants.paints or {} do
			if not (DataService.GetValue(player, "paints.owned." .. id) == true) then
				DataService.Set(player, "paints.owned." .. id, true)
			end
		end
		for _, id in pass.grants.skins or {} do
			if not (DataService.GetValue(player, "skins.owned." .. id) == true) then
				DataService.Set(player, "skins.owned." .. id, true)
			end
		end
	end
	MonetizationService.PublishCosmetics(player)
	if not already then
		Analytics.Event(player, "PassOwned", pass.price, passId)
		log.info(`{if Validate.isPlayer(player) then player.Name else "?"} owns {passId}`)
		if not silent then
			notify(player, `Thank you! {pass.name} is yours.`)
		end
	end
	return true, nil
end

-- Asks Roblox whether the player owns the pass. nil = Roblox could not answer (try again later).
local function robloxOwns(player: any, pass: any): boolean?
	local ok, owns = pcall(function()
		return market:UserOwnsGamePassAsync(player.UserId, pass.passId)
	end)
	if ok then
		return owns == true
	end
	return nil
end

-- Join-time re-check: a pass bought on another server, or before a data wipe, is restored.
function MonetizationService.CheckOwnedPasses(player: any)
	for _, pass in Config.PASSES do
		if pass.passId > 0 and not MonetizationService.Has(player, pass.id) then
			if robloxOwns(player, pass) == true then
				MonetizationService.Grant(player, pass.id, true)
			end
		end
	end
	MonetizationService.PublishCosmetics(player)
end

-- ===== Prompts (the client asks; Roblox shows the purchase window) =====

-- Returns ok, reason ("unknown", "comingSoon", "owned", "noData"). `ok` only means the prompt was opened.
function MonetizationService.PromptPass(player: any, key: any): (boolean, string?)
	local pass = type(key) == "string" and Config.BY_PASS[key] or nil
	if pass == nil then
		return false, "unknown"
	end
	if pass.passId <= 0 then
		return false, "comingSoon"
	end
	if type(DataService.GetValue(player, "entitlements")) ~= "table" then
		return false, "noData"
	end
	if MonetizationService.Has(player, pass.id) then
		return false, "owned"
	end
	market:PromptGamePassPurchase(player, pass.passId)
	return true, nil
end

-- ===== Skin vouchers =====

local SEEN_KEEP = 20 -- how many recent receipt ids are remembered

local function voucherState(player: any): { Epic: number, Legendary: number, seen: { string } }?
	local v = DataService.GetValue(player, "vouchers")
	if type(v) ~= "table" then
		return nil
	end
	local seen = {}
	if type(v.seen) == "table" then
		for _, id in v.seen do
			if type(id) == "string" then
				table.insert(seen, id)
			end
		end
	end
	return { Epic = math.max(0, math.floor(tonumber(v.Epic) or 0)), Legendary = math.max(0, math.floor(tonumber(v.Legendary) or 0)), seen = seen }
end

-- A voucher receipt: +1 voucher of the product's tier, saved BEFORE the purchase is confirmed; the receipt id is remembered so a repeat
-- (Roblox may send one twice) never gives a second voucher. Returns true when the voucher is saved (a repeat counts as saved).
local function grantVoucher(player: any, product: any, purchaseId: any): boolean
	local state = voucherState(player)
	if state == nil or (product.tier ~= "Epic" and product.tier ~= "Legendary") then
		return false
	end
	local pid = tostring(purchaseId)
	if table.find(state.seen, pid) then
		return true
	end
	state[product.tier] += 1
	table.insert(state.seen, pid)
	while #state.seen > SEEN_KEEP do
		table.remove(state.seen, 1)
	end
	return DataService.Set(player, "vouchers", state)
end

-- Spends one voucher on a skin of that rarity. Returns ok, reason ("unknown", "notRedeemable", "owned", "noVoucher", "noData", "saveFailed").
function MonetizationService.RedeemVoucher(player: any, skinId: any): (boolean, string?)
	local skin = type(skinId) == "string" and Skins.BY_ID[skinId] or nil
	if skin == nil then
		return false, "unknown"
	end
	if skin.pass ~= nil or (skin.rarity ~= "Epic" and skin.rarity ~= "Legendary") then
		return false, "notRedeemable" -- theme / pass skins and the other rarities are not sold with vouchers
	end
	local state = voucherState(player)
	if state == nil or DataService.GetValue(player, "skins.owned") == nil then
		return false, "noData"
	end
	if DataService.GetValue(player, "skins.owned." .. skinId) == true then
		return false, "owned"
	end
	if state[skin.rarity] < 1 then
		return false, "noVoucher"
	end
	state[skin.rarity] -= 1
	if not DataService.Set(player, "vouchers", state) then
		return false, "saveFailed"
	end
	if not DataService.Set(player, "skins.owned." .. skinId, true) then
		state[skin.rarity] += 1 -- give the voucher back
		DataService.Set(player, "vouchers", state)
		return false, "saveFailed"
	end
	Analytics.Event(player, "VoucherRedeemed", 1, skin.rarity, skinId)
	log.info(`{if Validate.isPlayer(player) then player.Name else "?"} redeemed a {skin.rarity} voucher for {skinId}`)
	return true, nil
end

-- Gives a premium paint product's paints for good. Returns true when every paint is saved as owned (already owned counts).
local function grantPaints(player: any, product: any): boolean
	for _, id in product.paints or {} do
		if DataService.GetValue(player, "paints.owned." .. id) ~= true and not DataService.Set(player, "paints.owned." .. id, true) then
			return false
		end
	end
	return true
end

local function ownsAllPaints(player: any, product: any): boolean
	for _, id in product.paints or {} do
		if DataService.GetValue(player, "paints.owned." .. id) ~= true then
			return false
		end
	end
	return true
end

function MonetizationService.PromptProduct(player: any, key: any): (boolean, string?)
	local product = type(key) == "string" and Config.BY_PRODUCT[key] or nil
	if product == nil then
		return false, "unknown"
	end
	if product.productId <= 0 then
		return false, "comingSoon"
	end
	if product.paints ~= nil and ownsAllPaints(player, product) then
		return false, "owned" -- never charge for paints you already have
	end
	market:PromptProductPurchase(player, product.productId)
	return true, nil
end

-- Roblox says a pass purchase window closed. Only believe it after asking Roblox who owns the pass.
function MonetizationService.OnPassPurchaseFinished(player: any, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	for _, pass in Config.PASSES do
		if pass.passId == gamePassId then
			if robloxOwns(player, pass) == true then
				MonetizationService.Grant(player, pass.id, false)
			else
				log.warn(`purchase of {pass.id} reported but Roblox does not show it as owned yet`)
			end
			return
		end
	end
end

-- Developer product receipts (the tip jar). Returns Enum.ProductPurchaseDecision. A tip gives nothing but thanks, so a repeat
-- can't hurt; the session set only stops a double thank-you. If the player isn't here, Roblox retries when they come back.
function MonetizationService.HandleReceipt(info: any): Enum.ProductPurchaseDecision
	local player = playerById(info.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	for _, product in Config.PRODUCTS do
		if product.productId > 0 and product.productId == info.ProductId then
			if product.kind == "Voucher" then
				if not grantVoucher(player, product, info.PurchaseId) then
					return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved: Roblox retries
				end
				Analytics.Event(player, "VoucherBought", product.price, product.id)
				notify(player, `Thank you! {product.name}: pick any {product.tier} skin at the skins stall (Vouchers tab).`)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			if product.paints ~= nil then
				-- a premium paint or set: save the paints BEFORE confirming (if saving fails Roblox retries); granting twice is harmless
				if not grantPaints(player, product) then
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				if not thanked[info.PurchaseId] then
					thanked[info.PurchaseId] = true
					Analytics.Event(player, "PremiumPaint", product.price, product.id)
					notify(player, `Thank you! {product.name} is yours. Find it in the Paint Bar (Owned).`)
				end
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			if not thanked[info.PurchaseId] then
				thanked[info.PurchaseId] = true
				Analytics.Event(player, "TipJar", product.price, product.id)
				notify(player, `Thank you so much for supporting Dusty Finds! ({product.name})`)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- not one of ours: leave it for another handler / try later
end

-- ===== VIP choices (cosmetic only) =====

local function inList(list: { any }, id: any): boolean
	for _, entry in list do
		if entry.id == id then
			return true
		end
	end
	return false
end

-- Letters, digits, spaces and a little punctuation; trimmed; at most TitleMaxLength characters.
local function cleanTitle(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(text, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if #trimmed == 0 or #trimmed > Config.VIP.TitleMaxLength or string.find(trimmed, "[^%w %-'!&%.]") then
		return nil
	end
	return trimmed
end

-- field: "title" | "pet" | "petColor" | "auraStyle"; value: a choice id ("" clears it). Returns ok, reason
-- ("notVip", "badField", "badValue", "badTitle", "noData", "saveFailed").
function MonetizationService.SetVip(player: any, field: any, value: any): (boolean, string?)
	if not MonetizationService.Has(player, "VIP") then
		return false, "notVip"
	end
	if type(DataService.GetValue(player, "vip")) ~= "table" then
		return false, "noData"
	end
	if type(value) ~= "string" then
		return false, "badValue"
	end
	local final = value
	if field == "pet" then
		if value ~= "" and not inList(Config.VIP.Pets, value) then
			return false, "badValue"
		end
	elseif field == "petColor" then
		if value ~= "" and not inList(Config.VIP.PetColors, value) then
			return false, "badValue"
		end
	elseif field == "auraStyle" then
		if value ~= "" and not inList(Config.VIP.AuraStyles, value) then
			return false, "badValue"
		end
	elseif field == "title" then
		if value ~= "" then
			if table.find(Config.VIP.Titles, value) then
				final = value
			else
				-- a custom title: simple characters only, then Roblox's text filter (everyone sees it, so the broadcast filter)
				local clean = cleanTitle(value)
				if clean == nil then
					return false, "badTitle"
				end
				local ok, filtered = pcall(function()
					local result = TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
					return result:GetNonChatStringForBroadcastAsync()
				end)
				if not ok or filtered ~= clean then
					return false, "badTitle" -- filtered or the filter is down: refuse, never show unfiltered text
				end
				final = clean
			end
		end
	else
		return false, "badField"
	end
	if not DataService.Set(player, "vip." .. field, final) then
		return false, "saveFailed"
	end
	MonetizationService.PublishCosmetics(player)
	return true, nil
end

local REASON_TEXT = {
	comingSoon = "That isn't available just yet. Coming soon!",
	owned = "You already have that.",
	notVip = "Get VIP at the Collector's Corner to choose that.",
	badTitle = "That title can't be used. Pick a preset or a short, friendly one.",
	saveFailed = "Couldn't save that. Try again.",
}

-- ===== Remotes and Roblox events =====

function MonetizationService.Init(services)
	DataService = services.DataService
	log.info("Init")
end

function MonetizationService.Start()
	Remotes.RequestPurchasePass.OnServerEvent:Connect(function(player, key)
		if not Validate.rateLimit(player, "RequestPurchasePass", 2) then
			return
		end
		local _, reason = MonetizationService.PromptPass(player, key)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestPurchaseProduct.OnServerEvent:Connect(function(player, key)
		if not Validate.rateLimit(player, "RequestPurchaseProduct", 2) then
			return
		end
		local _, reason = MonetizationService.PromptProduct(player, key)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestRedeemVoucher.OnServerEvent:Connect(function(player, skinId)
		if not Validate.rateLimit(player, "RequestRedeemVoucher", 2) then
			return
		end
		local ok, reason = MonetizationService.RedeemVoucher(player, skinId)
		if ok then
			notify(player, `{Skins.BY_ID[skinId].name} is yours! Find it in the Owned tab.`)
		elseif reason == "noVoucher" then
			notify(player, "You don't have a voucher for that rarity.")
		elseif reason == "notRedeemable" then
			notify(player, "Vouchers work for Epic and Legendary skins only.")
		elseif reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestSetVip.OnServerEvent:Connect(function(player, field, value)
		if not Validate.rateLimit(player, "RequestSetVip", 3) then
			return
		end
		local _, reason = MonetizationService.SetVip(player, field, value)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		MonetizationService.OnPassPurchaseFinished(player, gamePassId, wasPurchased)
	end)
	MarketplaceService.ProcessReceipt = function(info)
		return MonetizationService.HandleReceipt(info)
	end
	if DataService.OnPlayerLoaded then
		DataService.OnPlayerLoaded(function(player)
			task.spawn(MonetizationService.CheckOwnedPasses, player)
		end)
	end
	log.info("Start")
end

return MonetizationService
