-- SkinService.luau (ServerScriptService.Server.Services.SkinService)
-- Purpose: shelf and pedestal skins (docs/10_Stock_Shop_And_Skins.md): buying a skin that is in stock at the skins
-- stall (RequestBuySkin), using an owned skin in your shop (RequestApplySkin), and drawing the skins on every shop so
-- visitors see them. One active shelf skin and one pedestal skin per shop ("" = classic). Looks only: never changes
-- slots, prices or rating points.
-- Owner: Dev 3 (Sean). Depends on: DataService (skins field), EconomyService (Spend), Shared.Stock (what is in stock),
-- Shared.Config (Skins, Stock, Rarities), Workspace.Plots (Shelves / ExhibitSlots, OwnerUserId), Workspace.SkinStall.Counter.
-- Validation order (buy): known skin -> data loaded -> not owned -> in stock now -> at the stall -> pay -> save (refund if
-- the save fails). Everything the client sends is checked; prices and stock come from Config + the shared roll.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(script.Parent.Parent.Lib.Log)
local Validate = require(script.Parent.Parent.Lib.Validate)
local Analytics = require(script.Parent.Parent.Lib.Analytics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hours = require(ReplicatedStorage.Shared.Hours)
local Skins = require(ReplicatedStorage.Shared.Config.Skins)
local StockConfig = require(ReplicatedStorage.Shared.Config.Stock)
local Stock = require(ReplicatedStorage.Shared.Stock)

local SkinService = {}
local DEBUG = true
local log = Log.new("SkinService", DEBUG)

local DataService, EconomyService = nil, nil
local KIND_FIELD = Skins.FIELD -- Shelf / Pedestal / Cashier -> data.skins field
local watched: { [BasePart]: { RBXScriptConnection } } = {}

local function notify(player: any, text: string)
	if Validate.isPlayer(player) then
		Remotes.Notify:FireClient(player, "Skins", text)
	end
end

-- ===== Drawing =====

local function skinFor(plot: Instance, kind: string): any
	local userId = plot:GetAttribute("OwnerUserId")
	local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local data = owner and DataService and DataService.Get(owner)
	local id = data and data.skins and data.skins[KIND_FIELD[kind]]
	return if type(id) == "string" then Skins.BY_ID[id] else nil
end

-- The extras (trim, light, sparkles) show only while the piece itself is visible (locked pedestals are hidden).
local function syncExtras(part: BasePart)
	local visible = part.Transparency < 0.99
	local trims = part.Parent and part.Parent.Parent and part.Parent.Parent:FindFirstChild("SkinTrims")
	for _, name in { "Top", "Base" } do
		local trim = trims and trims:FindFirstChild(part.Name .. "_" .. name)
		if trim and trim:IsA("BasePart") then
			trim.Transparency = if visible then 0 else 1
			trim.CFrame = part.CFrame * (trim:GetAttribute("Offset") :: CFrame)
		end
	end
	local light = part:FindFirstChild("SkinLight")
	if light and light:IsA("PointLight") then
		light.Enabled = visible
	end
	local sparkle = part:FindFirstChild("SkinSparkle")
	if sparkle and sparkle:IsA("ParticleEmitter") then
		sparkle.Enabled = visible
	end
end

local function drawPiece(plot: Instance, part: BasePart, skin: any)
	-- remember the classic look once, so "" (or a released plot) can always go back to it
	if part:GetAttribute("BaseColor") == nil then
		part:SetAttribute("BaseColor", part.Color)
		part:SetAttribute("BaseMaterial", part.Material.Name)
		part:SetAttribute("BaseReflectance", part.Reflectance)
	end
	local look = skin and skin.look
	part.Color = if look then look.color else part:GetAttribute("BaseColor")
	part.Material = if look then look.material else (Enum.Material :: any)[part:GetAttribute("BaseMaterial")]
	part.Reflectance = if look then (look.reflectance or 0) else part:GetAttribute("BaseReflectance")
	part:SetAttribute("Skin", if skin then skin.id else nil)

	for _, name in { "SkinLight", "SkinSparkle" } do
		local old = part:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local trims = plot:FindFirstChild("SkinTrims")
	for _, name in { "Top", "Base" } do
		local old = trims and trims:FindFirstChild(part.Name .. "_" .. name)
		if old then
			old:Destroy()
		end
	end

	-- model skins (look.model) are drawn on each screen by SkinModelController with their own light and aura;
	-- the server only sets the fallback colour on the block and the Skin attribute
	if look and look.model then
		syncExtras(part)
		if watched[part] == nil then
			watched[part] = {
				part:GetPropertyChangedSignal("Transparency"):Connect(function()
					syncExtras(part)
				end),
				part:GetPropertyChangedSignal("CFrame"):Connect(function()
					syncExtras(part)
				end),
			}
		end
		return
	end
	if look and look.trim then
		if trims == nil then
			trims = Instance.new("Folder")
			trims.Name = "SkinTrims"
			trims.Parent = plot
		end
		-- a rim round the top (flush with the top, so items still sit where they always did) and a plinth at the bottom
		local bands = {
			Top = CFrame.new(0, part.Size.Y / 2 - 0.2, 0),
			Base = CFrame.new(0, -part.Size.Y / 2 + 0.2, 0),
		}
		for name, offset in bands do
			local trim = Instance.new("Part")
			trim.Name = part.Name .. "_" .. name
			trim.Anchored = true
			trim.CanCollide = false
			trim.CanQuery = false
			trim.CanTouch = false
			trim.CastShadow = false
			trim.Size = Vector3.new(part.Size.X + 0.3, 0.4, part.Size.Z + 0.3)
			trim.Color = look.trim
			trim.Material = look.trimMaterial or Enum.Material.Metal
			trim:SetAttribute("Offset", offset)
			-- edit mode moves it with its piece (EditModeController followers)
			trim:SetAttribute("Piece", part:GetAttribute("PieceId"))
			trim.CFrame = part.CFrame * offset
			trim.Parent = trims
		end
	end
	if look and look.light then
		local light = Instance.new("PointLight")
		light.Name = "SkinLight"
		light.Color = look.light
		light.Range = 10
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = part
	end
	if look and look.sparkle then
		-- turned off on the client when Settings "Reduce effects" is on (SkinShopController)
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "SkinSparkle"
		sparkle.Color = ColorSequence.new(look.sparkle)
		sparkle.LightEmission = 1
		sparkle.Rate = 3
		sparkle.Lifetime = NumberRange.new(1, 1.8)
		sparkle.Speed = NumberRange.new(0.5, 1.2)
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Transparency = NumberSequence.new(0.2)
		sparkle.SpreadAngle = Vector2.new(30, 30)
		sparkle.Parent = part
	end
	syncExtras(part)

	-- keep the extras right when the piece moves (pedestals go up / to the Back Room) or is hidden / shown
	if watched[part] == nil then
		watched[part] = {
			part:GetPropertyChangedSignal("Transparency"):Connect(function()
				syncExtras(part)
			end),
			part:GetPropertyChangedSignal("CFrame"):Connect(function()
				syncExtras(part)
			end),
		}
	end
end

local function piecesOf(plot: Instance, kind: string): { BasePart }
	-- Cashier skins are model skins drawn over ShopProps.CashCounter on each screen (built with the first cashier
	-- design); the server has no blocks to colour for them
	local FOLDER = { Shelf = "Shelves", Pedestal = "ExhibitSlots" }
	local folder = FOLDER[kind] and plot:FindFirstChild(FOLDER[kind])
	local list = {}
	for _, part in if folder then folder:GetChildren() else {} do
		if part:IsA("BasePart") and part:GetAttribute("PieceId") ~= nil then
			table.insert(list, part)
		end
	end
	return list
end

-- Draws a plot with its owner's skins (or the classic look when nobody owns it).
function SkinService.DrawPlot(plot: Instance)
	for _, kind in Skins.KINDS do
		local skin = skinFor(plot, kind)
		for _, part in piecesOf(plot, kind) do
			drawPiece(plot, part, skin)
		end
	end
	-- the cash counter: only the Skin attribute on its Body; SkinModelController draws the model over it on each screen
	local props = plot:FindFirstChild("ShopProps")
	local counter = props and props:FindFirstChild("CashCounter")
	local body = counter and counter:FindFirstChild("Body")
	if body then
		local skin = skinFor(plot, "Cashier")
		body:SetAttribute("Skin", if skin then skin.id else nil)
	end
end

-- Draws one piece with a skin id ("" = classic). Used by the tests (SkinCheck) on a copy of a plot.
function SkinService.DrawPiece(plot: Instance, part: BasePart, skinId: string)
	drawPiece(plot, part, if skinId ~= "" then Skins.BY_ID[skinId] else nil)
end

local function plotOf(player: Player): Instance?
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

-- ===== Buy / apply =====

-- Returns ok, reason ("unknown", "noData", "owned", "notInStock", "far", "cash", "saveFailed").
function SkinService.Buy(player: Player, skinId: any, now: number?): (boolean, string?)
	if not Validate.isConfigId(skinId, Skins.BY_ID) then
		return false, "unknown"
	end
	local skin = Skins.BY_ID[skinId]
	local data = DataService.Get(player)
	if data == nil or type(data.skins) ~= "table" then
		return false, "noData"
	end
	if data.skins.owned[skinId] then
		return false, "owned"
	end
	if not Stock.isInStock(Stock.restockIndex(now or os.time()), skinId) then
		return false, "notInStock"
	end
	-- the Skins Booth or the centre Shelves & Pedestals stall (both sell from the same stock)
	local near = false
	for _, stallName in { "SkinStall", "ShelfStall" } do
		local stall = workspace:FindFirstChild(stallName)
		local counter = stall and stall:FindFirstChild("Counter")
		if counter and Validate.withinDistance(player, counter, StockConfig.BuyMaxStuds) then
			near = true
		end
	end
	if not near then
		return false, "far"
	end
	if not EconomyService.Spend(player, skin.price, "Shop", skinId) then
		return false, "cash"
	end
	if not DataService.Set(player, "skins.owned." .. skinId, true) then
		EconomyService.AddCash(player, skin.price, "Refund")
		return false, "saveFailed"
	end
	Analytics.Step(player, Analytics.STEP.BoughtSkin)
	Analytics.Event(player, "SkinBought", 1, skin.kind, skin.rarity, skinId)
	log.info(`{player.Name} bought {skinId} for ${skin.price}`)
	return true, nil
end

-- kind = "Shelf" | "Pedestal" | "Cashier"; skinId = an owned skin of that kind, or "" for the classic look.
-- Returns ok, reason ("badKind", "unknown", "wrongKind", "noData", "notOwned", "saveFailed").
function SkinService.Apply(player: Player, kind: any, skinId: any): (boolean, string?)
	local field = type(kind) == "string" and KIND_FIELD[kind]
	if not field then
		return false, "badKind"
	end
	if type(skinId) ~= "string" then
		return false, "unknown"
	end
	if skinId ~= "" then
		local skin = Skins.BY_ID[skinId]
		if skin == nil then
			return false, "unknown"
		end
		if skin.kind ~= kind then
			return false, "wrongKind"
		end
	end
	local data = DataService.Get(player)
	if data == nil or type(data.skins) ~= "table" then
		return false, "noData"
	end
	if skinId ~= "" and not data.skins.owned[skinId] then
		return false, "notOwned"
	end
	if not DataService.Set(player, "skins." .. field, skinId) then
		return false, "saveFailed"
	end
	local plot = plotOf(player)
	if plot then
		SkinService.DrawPlot(plot)
	end
	return true, nil
end

-- Admin gift (AdminService /skin): own a skin for free, no stock / distance / cash checks; use = also put it on.
-- Returns ok, reason ("unknown", "noData", "saveFailed", or an Apply reason).
function SkinService.Grant(player: Player, skinId: string, use: boolean?): (boolean, string?)
	local skin = Skins.BY_ID[skinId]
	if skin == nil then
		return false, "unknown"
	end
	local data = DataService.Get(player)
	if data == nil or type(data.skins) ~= "table" then
		return false, "noData"
	end
	if not data.skins.owned[skinId] and not DataService.Set(player, "skins.owned." .. skinId, true) then
		return false, "saveFailed"
	end
	if use then
		return SkinService.Apply(player, skin.kind, skinId)
	end
	return true, nil
end

-- ===== Wishlist (docs/12 Stage 2): pin skins you want; a toast tells you when one is in stock. NOTIFY ONLY: it never changes
-- the stock or the odds. At most WISHLIST_MAX pins. Returns ok, reason ("unknown", "noData", "full", "owned", "saveFailed").
local WISHLIST_MAX = 5
function SkinService.SetWishlist(player: Player, skinId: any, on: any): (boolean, string?)
	local skin = type(skinId) == "string" and Skins.BY_ID[skinId] or nil
	if skin == nil or type(on) ~= "boolean" then
		return false, "unknown"
	end
	local data = DataService.Get(player)
	if data == nil or type(data.wishlist) ~= "table" or type(data.skins) ~= "table" then
		return false, "noData"
	end
	if on then
		if data.skins.owned[skinId] then
			return false, "owned"
		end
		if data.wishlist[skinId] then
			return true, nil
		end
		local count = 0
		for _ in data.wishlist do
			count += 1
		end
		if count >= WISHLIST_MAX then
			return false, "full"
		end
		if not DataService.Set(player, "wishlist." .. skinId, true) then
			return false, "saveFailed"
		end
	else
		if data.wishlist[skinId] and not DataService.Set(player, "wishlist." .. skinId, nil) then
			return false, "saveFailed"
		end
	end
	return true, nil
end

local REASON_TEXT = {
	full = "Your wishlist is full (5). Remove one first.",
	owned = "You already own that skin.",
	notInStock = "That skin is sold out here now. New stock soon!",
	far = "Buy skins at the skins stall.",
	cash = "Not enough cash for that skin.",
	notOwned = "You don't own that skin yet.",
	saveFailed = "Couldn't save that. Try again.",
}

-- ===== Restock announcements =====

local function announceLoop()
	local lastIndex = Stock.restockIndex(os.time())
	while true do
		task.wait(1)
		local index = Stock.restockIndex(os.time())
		if index ~= lastIndex then
			lastIndex = index
			local rolled = Stock.roll(index)
			for _, id in rolled do
				local skin = Skins.BY_ID[id]
				if skin and StockConfig.AnnounceRarities[skin.rarity] then
					Remotes.Announcement:FireAllClients(`New at the skins stall: {skin.name} ({skin.rarity})!`, skin.rarity)
				end
			end
			-- wishlist: tell each player whose pinned skin is in this restock (once per restock)
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				if data and type(data.wishlist) == "table" then
					for _, id in rolled do
						local skin = Skins.BY_ID[id]
						if skin and data.wishlist[id] and not (data.skins and data.skins.owned[id]) then
							notify(player, `On your wishlist: {skin.name} ({skin.kind}) is in stock at the skins stall!`)
						end
					end
				end
			end
			log.info("restock", index)
		end
	end
end

function SkinService.Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	log.info("Init")
end

function SkinService.Start()
	Remotes.RequestBuySkin.OnServerEvent:Connect(function(player, skinId)
		if not Validate.rateLimit(player, "RequestBuySkin", 2) then
			return
		end
		if not Hours.marketOpen() then
			Remotes.Notify:FireClient(player, "Info", "The Warehouse Market is closed. It opens at " .. Hours.format(Hours.MARKET_OPEN) .. ".")
			return
		end
		local ok, reason = SkinService.Buy(player, skinId)
		if ok then
			local skin = Skins.BY_ID[skinId]
			notify(player, `You got the {skin.name} skin! Use it in the Skins window.`)
		elseif reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)
	Remotes.RequestApplySkin.OnServerEvent:Connect(function(player, kind, skinId)
		if not Validate.rateLimit(player, "RequestApplySkin", 4) then
			return
		end
		local _, reason = SkinService.Apply(player, kind, skinId)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)

	Remotes.RequestSetWishlist.OnServerEvent:Connect(function(player, skinId, on)
		if not Validate.rateLimit(player, "RequestSetWishlist", 4) then
			return
		end
		local _, reason = SkinService.SetWishlist(player, skinId, on)
		if reason and REASON_TEXT[reason] then
			notify(player, REASON_TEXT[reason])
		end
	end)

	-- redraw a shop whenever it changes hands (owner joins: their skins; owner leaves: classic)
	local plots = workspace:WaitForChild("Plots", 30)
	if plots then
		local function hook(plot: Instance)
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
				SkinService.DrawPlot(plot)
			end)
			SkinService.DrawPlot(plot)
		end
		for _, plot in plots:GetChildren() do
			hook(plot)
		end
		plots.ChildAdded:Connect(hook)
	end
	task.spawn(announceLoop)
	log.info("Start: stall restocks every", StockConfig.RestockSeconds, "s")
end

return SkinService
