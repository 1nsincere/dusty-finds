-- LeaderboardService.luau
-- Purpose: keeps the two physical Park boards updated: TopEarnersBoard (most cash) and MostValuableBoard
-- (most valuable SHOP = the total value of every item the player owns, RAP-style). Values are ALL-TIME records
-- kept in a DataStore, so a player stays on the board after leaving (Rolimon-style); online players' live
-- values merge into their records. The top 3 of each board also get a physical avatar of themselves dancing
-- on the podiums beside the board.
-- Boards are found by the LeaderboardType attribute, so they can be moved or re-decorated freely.
-- Owner: Dev 1 (Ace). Depends on: DataService (cash + inventory), Shared.Formulas (item value), Config.Items (names).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Formulas = require(ReplicatedStorage.Shared:WaitForChild("Formulas"))
local Items = require(ReplicatedStorage.Shared.Config:WaitForChild("Items"))

local DataService = nil -- set in Init from the services table

local UPDATE_INTERVAL = 20 -- seconds between refreshes
local ROW_COUNT = 5
local PODIUM_COUNT = 3
local RECORDS_KEY = "Records" -- one key holding every player's all-time bests
local STORE_NAME = if RunService:IsStudio() then "LeaderboardRecords_DEV" else "LeaderboardRecords_v1"

-- Roblox's own default R15 dance emotes, same ones the Townsfolk NPCs already use in this game.
local DANCE_ANIM_IDS = { 507771019, 507776043, 507777268 }

local LeaderboardService = {}
local DEBUG = true

local boards = {} -- ["Cash"/"BestItem"] = Model (re-found if it goes missing)
local avatarCache = {} -- [userId] = thumbnail content string
local descCache = {} -- [userId] = HumanoidDescription (avatar look for podium NPCs)
local store = nil -- DataStore, created lazily so a DataStore outage never blocks startup
local records = {} -- [tostring(userId)] = { name, cash, totalValue, itemName } all-time bests
local recordsDirty = false -- true when a live player beat a stored record and we should save
local podiumState = {} -- [boardType] = { userIds = {n,n,n}, token = n } current podium occupants + rebuild token

local function log(...)
	if DEBUG then
		print("[LeaderboardService]", ...)
	end
end

-- 1234567 -> "1,234,567"
local function comma(n: number): string
	n = math.floor(math.max(0, n))
	local formatted = tostring(n)
	while true do
		local k, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = k
		if replaced == 0 then
			break
		end
	end
	return formatted
end

-- The DataStore, or nil if it can't be opened (boards still work, records just aren't saved this session).
local function ensureStore()
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if ok then
			store = result
		else
			warn("[LeaderboardService] could not open DataStore:", result)
		end
	end
	return store
end

-- Load every player's all-time records once. A failed load just means empty records (they rebuild as people play).
local function loadRecords()
	local s = ensureStore()
	if s == nil then
		return
	end
	local ok, data = pcall(function()
		return s:GetAsync(RECORDS_KEY)
	end)
	if ok and type(data) == "table" then
		for key, r in data do
			if type(r) == "table" then
				records[key] = {
					name = if type(r.name) == "string" then r.name else "?",
					cash = if type(r.cash) == "number" then r.cash else 0,
					totalValue = if type(r.totalValue) == "number" then r.totalValue else 0,
					itemName = if type(r.itemName) == "string" then r.itemName else "",
				}
			end
		end
	elseif not ok then
		warn("[LeaderboardService] record load failed (boards start empty of history):", data)
	end
	local count = 0
	for _ in records do
		count += 1
	end
	log("loaded all-time records for", count, "player(s)")
end

-- Save records, merging field-by-field with whatever is stored so two servers never overwrite each other's highs.
local function saveRecords()
	local s = ensureStore()
	if s == nil then
		return
	end
	local snapshot = {}
	for key, r in records do
		snapshot[key] = { name = r.name, cash = r.cash, totalValue = r.totalValue, itemName = r.itemName }
	end
	local ok, err = pcall(function()
		s:UpdateAsync(RECORDS_KEY, function(old)
			old = if type(old) == "table" then old else {}
			for key, r in snapshot do
				local o = if type(old[key]) == "table" then old[key] else { name = r.name, cash = 0, totalValue = 0, itemName = "" }
				local oldTotal = if type(o.totalValue) == "number" then o.totalValue else 0
				local merged = {
					name = r.name, -- newest display name wins
					cash = math.max(r.cash, if type(o.cash) == "number" then o.cash else 0),
					totalValue = math.max(r.totalValue, oldTotal),
					itemName = if r.totalValue > oldTotal then r.itemName elseif type(o.itemName) == "string" then o.itemName else "",
				}
				old[key] = merged
			end
			return old
		end)
	end)
	if not ok then
		warn("[LeaderboardService] record save failed (will retry on next change):", err)
		recordsDirty = true -- retry next cycle
	else
		log("saved all-time records")
	end
end

-- Fold online players' live values into the all-time records (max wins). Only players who ever earned
-- something get a record, so brand-new zero players never appear on the boards.
local function mergeLiveIntoRecords(entries)
	for _, e in entries do
		local key = tostring(e.userId)
		local r = records[key]
		if r == nil and (e.cash > 0 or e.totalValue > 0) then
			r = { name = e.name, cash = 0, totalValue = 0, itemName = "" }
			records[key] = r
		end
		if r then
			r.name = e.name
			if e.cash > r.cash then
				r.cash = e.cash
				recordsDirty = true
			end
			if e.totalValue > r.totalValue then
				r.totalValue = e.totalValue
				r.itemName = e.bestItem
				recordsDirty = true
			end
		end
	end
end

-- All-time standings built from the records (online and offline players alike).
local function combinedEntries(): { { name: string, userId: number, cash: number, totalValue: number, bestItem: string } }
	local list = {}
	for key, r in records do
		local userId = tonumber(key)
		if userId then
			table.insert(list, {
				name = r.name,
				userId = userId,
				cash = r.cash,
				totalValue = r.totalValue,
				bestItem = r.itemName,
			})
		end
	end
	return list
end

-- Find the board models by attribute, wherever the team has moved them. Cached between refreshes.
local function findBoards()
	local found = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") then
			local t = d:GetAttribute("LeaderboardType")
			if t == "Cash" or t == "BestItem" then
				found[t] = d
			end
		end
	end
	return found
end

-- Headshot thumbnail for a userId, cached once rendered. Not-ready thumbnails are retried next refresh.
local function avatarFor(userId: number): string
	if avatarCache[userId] then
		return avatarCache[userId]
	end
	local ok, content, isReady = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	if ok and isReady and type(content) == "string" then
		avatarCache[userId] = content
		return content
	end
	return "" -- still rendering (or failed): retried on the next refresh
end

-- The sell value of one inventory item (same math the economy uses, no wish/tip bonus).
local function itemValue(item: any): number
	if type(item) ~= "table" then
		return 0
	end
	local def = Items[item.itemId]
	if def == nil then
		return 0
	end
	return Formulas.sellPrice(item.itemId, item.stars, item.golden) or 0
end

-- One entry per online player with loaded data: cash, their TOTAL shop value (every item summed),
-- and the name of their single most valuable item (shown as the row's sub-line).
local function collectEntries(): { { name: string, userId: number, cash: number, totalValue: number, bestItem: string } }
	local entries = {}
	for _, player in Players:GetPlayers() do
		local data = DataService and DataService.Get(player)
		if data then
			local totalValue, bestValue, bestItem = 0, 0, ""
			if type(data.inventory) == "table" then
				for _, item in data.inventory do
					local v = itemValue(item)
					totalValue += v
					if v > bestValue then
						bestValue = v
						local def = Items[item.itemId]
						bestItem = if def then def.name else ""
					end
				end
			end
			table.insert(entries, {
				name = player.DisplayName,
				userId = player.UserId,
				cash = data.cash or 0,
				totalValue = totalValue,
				bestItem = bestItem,
			})
		end
	end
	return entries
end

-- Write the top N of a metric into one board's rows. metric: "cash" or "totalValue".
local function updateBoard(board: Model, entries, metric: string, showItem: boolean)
	if board == nil then
		return
	end
	local display = board:FindFirstChild("Board") and board.Board:FindFirstChild("Display")
	if display == nil then
		return
	end

	local sorted = {}
	for _, e in entries do
		if e[metric] > 0 then
			table.insert(sorted, e)
		end
	end
	table.sort(sorted, function(a, b)
		return a[metric] > b[metric]
	end)

	for i = 1, ROW_COUNT do
		local row = display:FindFirstChild("Row" .. i)
		if row == nil then
			continue
		end
		local entry = sorted[i]
		if entry == nil then
			row.Visible = false
			continue
		end
		row.Visible = true
		local avatar = row:FindFirstChild("Avatar")
		local name = row:FindFirstChild("Name")
		local sub = row:FindFirstChild("Sub")
		local value = row:FindFirstChild("Value")
		if avatar then
			avatar.Image = avatarFor(entry.userId)
		end
		if name then
			name.Text = entry.name
		end
		if sub then
			sub.Text = if showItem then (entry.bestItem ~= "" and ("Best: " .. entry.bestItem) or "-") else ""
		end
		if value then
			value.Text = "$" .. comma(entry[metric])
		end
	end
	return sorted
end

-- Build one podium NPC: a physical copy of the player's avatar, anchored, dancing, with a name tag.
local function buildPodiumNPC(board: Model, podium: BasePart, entry, rank: number, danceIndex: number, token: number)
	local state = podiumState[board:GetAttribute("LeaderboardType")]
	if state and state.token ~= token then
		return -- a newer refresh already replaced this podium lineup; abandon
	end

	local desc = descCache[entry.userId]
	if desc == nil then
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(entry.userId)
		end)
		if not ok or d == nil then
			log("avatar fetch failed for", entry.userId, "-", tostring(d))
			return -- retried on the next refresh
		end
		descCache[entry.userId] = d
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		log("avatar build failed for", entry.userId, "-", tostring(model))
		return
	end
	if state and state.token ~= token then
		model:Destroy()
		return
	end

	model.Name = "PodiumAvatar" .. entry.userId

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		model:Destroy()
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
	end

	-- stand on the podium, facing the board it belongs to
	local boardPart = board:FindFirstChild("Board")
	local podiumTop = podium.CFrame.Position + Vector3.new(0, podium.Size.Y / 2, 0)
	local facePos = if boardPart then boardPart.Position else podium.CFrame.Position
	local flatTarget = Vector3.new(facePos.X, podiumTop.Y, facePos.Z)
	model:PivotTo(CFrame.lookAt(podiumTop + Vector3.new(0, 2.9, 0), flatTarget))

	-- dance forever (Roblox's default emote dances, already used by our Townsfolk NPCs)
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(DANCE_ANIM_IDS[((danceIndex - 1) % #DANCE_ANIM_IDS) + 1])
	local track = animator:LoadAnimation(anim)
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play()

	-- floating name tag so visitors know who they're looking at
	local head = model:FindFirstChild("Head")
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.new(0, 180, 0, 44)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.AlwaysOnTop = true
	tag.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = "#" .. rank .. " " .. entry.name
	label.Parent = tag
	tag.Parent = model

	model.Parent = board
end

-- Keep the podium lineup matching the top 3 of a board. Rebuilt only when the occupants change,
-- so the avatar web fetches don't run every refresh.
local function updatePodiums(boardType: string, board: Model, sorted)
	if board == nil then
		return
	end
	local podiums = {}
	for _, c in board:GetChildren() do
		if c:IsA("BasePart") and c:GetAttribute("PodiumIndex") then
			table.insert(podiums, c)
		end
	end
	table.sort(podiums, function(a, b)
		return (a:GetAttribute("PodiumIndex") :: number) < (b:GetAttribute("PodiumIndex") :: number)
	end)

	local topIds = {}
	for i = 1, math.min(PODIUM_COUNT, #podiums, #sorted) do
		table.insert(topIds, sorted[i].userId)
	end

	local state = podiumState[boardType]
	if state and table.concat(state.userIds, ",") == table.concat(topIds, ",") then
		return -- same lineup, nothing to do
	end

	-- lineup changed: clear the old avatars and rebuild
	for _, c in board:GetChildren() do
		if string.match(c.Name, "^PodiumAvatar%d") then
			c:Destroy()
		end
	end
	local token = if state then state.token + 1 else 1
	podiumState[boardType] = { userIds = topIds, token = token }

	for i, userId in topIds do
		local entry = sorted[i]
		if entry then
			task.spawn(buildPodiumNPC, board, podiums[i], entry, i, i, token)
		end
	end
end

function LeaderboardService.Init(services)
	DataService = services.DataService
	if DataService == nil then
		warn("[LeaderboardService] DataService missing, boards will only show saved records")
	end
	log("Init")
end

function LeaderboardService.Start()
	task.spawn(function()
		loadRecords()
		while true do
			local cashSorted, shopSorted
			local ok, err = pcall(function()
				mergeLiveIntoRecords(collectEntries())
				local entries = combinedEntries()
				local found = findBoards()
				boards.Cash = found.Cash
				boards.BestItem = found.BestItem
				cashSorted = updateBoard(boards.Cash, entries, "cash", false)
				shopSorted = updateBoard(boards.BestItem, entries, "totalValue", true)
				updatePodiums("Cash", boards.Cash, cashSorted)
				updatePodiums("BestItem", boards.BestItem, shopSorted)
			end)
			if not ok then
				warn("[LeaderboardService] refresh failed:", err)
			end
			if recordsDirty then
				recordsDirty = false
				task.spawn(saveRecords) -- off the refresh loop: a slow save never delays the boards
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
	log("Start, refreshing every " .. UPDATE_INTERVAL .. "s, all-time records kept in " .. STORE_NAME)
end

return LeaderboardService