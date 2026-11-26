-- PlayerListController.luau
-- Purpose: our own player list, shaped like Roblox's own (a slim panel at the top-right with one compact row per player) but in the
-- game's walnut / cream / gold look. Roblox's list is switched off. Each row: headshot, display name, small badges (team role such as
-- Founder / Dev, Premium, Friend) and the player's shop level and rating stars; tap the little house to visit their shop (the existing
-- RequestVisit, validated by the server). Always shown in the top-right corner like Roblox's (Sean 2026-11-25: no Players tile any more);
-- Tab hides / shows it, like Roblox's. Live as players join, leave and level up. HudLayoutController keeps the right rail under it.
-- Level and rating come from player attributes DF_Level / DF_Rating that the server publishes (EconomyService, CollectionBookService).
-- Owner: Dev 1 (Ace). Depends on: HudKit, Shared.Config.UiSkin, Shared.Remotes.RequestVisit.
-- Must start before HudLayoutController (which reads GetPanel to place the right rail).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit"))

local PlayerListController = {}
local DEBUG = true
local C = Skin.COLORS
local make = HudKit.make
local player = Players.LocalPlayer
local others: { [string]: any } = {}

local GROUP_ID = 165295576 -- the team's Roblox group: its role shows as a badge (same group the Credits screen reads)
-- Only these group roles get a badge, spelled exactly as in the group (Sean, 2026-11-25): Members and everyone else get none.
-- Matched by the start of the role name, so "Founder" and "Director" still match if the group renames them slightly.
local BADGE_ROLES = { "founder", "director" }
local WIDTH, ROW_H, MAX_ROWS = 260, 42, 3 -- always on screen, so it shows 3 rows and scrolls for the rest (6 players max)
local VISIT_COOLDOWN = 1.5 -- the server allows one RequestVisit per second

local gui: ScreenGui? = nil
local panel: Frame? = nil
local list: ScrollingFrame? = nil
local countLabel: TextLabel? = nil
local headshots: { [number]: string } = {}
local roles: { [number]: string | boolean } = {} -- userId -> group role name, or false when not in the team group
local friends: { [number]: boolean } = {}
local lastVisit = 0

local function log(...)
	if DEBUG then
		print("[PlayerListController]", ...)
	end
end

local function badge(parent: Instance, text: string, color: Color3, order: number): TextLabel
	local b = make("TextLabel", {
		Name = "Badge", LayoutOrder = order, BackgroundColor3 = color, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 15),
		FontFace = Skin.FONT_TITLE, Text = text, TextColor3 = C.ink, TextSize = 11,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, b)
	return b
end

local function loadHeadshot(userId: number, into: ImageLabel)
	if headshots[userId] then
		into.Image = headshots[userId]
		return
	end
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			headshots[userId] = img
			if into.Parent then
				into.Image = img
			end
		end
	end)
end

-- the team role (async, cached): the group's own role name for Founder / Director (BADGE_ROLES), nothing for anyone else
local function loadRole(p: Player, then_: () -> ())
	if roles[p.UserId] ~= nil then
		return
	end
	roles[p.UserId] = false
	task.spawn(function()
		local ok, groups = pcall(function()
			return GroupService:GetGroupsAsync(p.UserId)
		end)
		if ok and type(groups) == "table" then
			for _, g in groups do
				if g.Id == GROUP_ID and type(g.Role) == "string" and g.Role ~= "" then
					local lower = string.lower(g.Role)
					for _, wanted in BADGE_ROLES do
						if string.sub(lower, 1, #wanted) == wanted then
							roles[p.UserId] = g.Role -- the group's own spelling, no " / Dev" added
						end
					end
					break
				end
			end
		end
		then_()
	end)
end

local function loadFriend(p: Player, then_: () -> ())
	if p == player or friends[p.UserId] ~= nil then
		return
	end
	friends[p.UserId] = false
	task.spawn(function()
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(p.UserId)
		end)
		if ok and isFriend then
			friends[p.UserId] = true
			then_()
		end
	end)
end

-- The server size (6 since 2026-11-25, one per shop plot). Studio test servers report Roblox's default instead, so never
-- show more than there are plots.
local function maxPlayers(): number
	local plots = workspace:FindFirstChild("Plots")
	local plotCount = if plots then #plots:GetChildren() else 0
	return if plotCount > 0 then math.min(Players.MaxPlayers, plotCount) else Players.MaxPlayers
end

local function stars(n: number): string
	return string.rep("★", math.clamp(n, 0, 5))
end

local refresh

local function addRow(p: Player, order: number)
	local isMe = p == player
	local row = make("Frame", {
		Name = "Row_" .. p.UserId, LayoutOrder = order, Size = UDim2.new(1, -6, 0, ROW_H),
		BackgroundColor3 = if isMe then Color3.fromRGB(104, 72, 40) else C.walnutLight, BackgroundTransparency = 0.12,
	}, list)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, row)
	make("UIStroke", { Color = if isMe then C.accent else C.ink, Thickness = if isMe then 2 else 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = if isMe then 0.1 else 0.3 }, row)
	local avatar = make("ImageLabel", { Name = "Avatar", Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.fromRGB(63, 167, 255), BorderSizePixel = 0 }, row)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
	make("UIStroke", { Color = C.ink, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, avatar)
	loadHeadshot(p.UserId, avatar)

	make("TextLabel", {
		Name = "DisplayName", BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 3), Size = UDim2.new(1, -150, 0, 20), FontFace = Skin.FONT_TITLE,
		Text = string.upper(p.DisplayName), TextColor3 = if isMe then C.accent else C.text, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	-- badges under the name: team role, Premium, Friend
	local tags = make("Frame", { Name = "Tags", BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 23), Size = UDim2.new(1, -150, 0, 15) }, row)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tags)
	local role = roles[p.UserId]
	if type(role) == "string" then
		badge(tags, string.upper(role), C.accent, 1)
	end
	if p:GetAttribute("DF_OneOfOne") == true then
		badge(tags, "◆ 1/1", Color3.fromRGB(170, 145, 205), 2)
	end
	if p.MembershipType == Enum.MembershipType.Premium then
		badge(tags, "✦ PREMIUM", Color3.fromRGB(63, 220, 200), 3)
	end
	if friends[p.UserId] then
		badge(tags, "♥ FRIEND", Color3.fromRGB(255, 140, 170), 4)
	end

	-- rank: shop level and rating stars (server attributes; hidden until the server has published them)
	local level = p:GetAttribute("DF_Level")
	local rating = p:GetAttribute("DF_Rating")
	make("TextLabel", {
		Name = "Level", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 3), Size = UDim2.fromOffset(60, 20), BackgroundTransparency = 1,
		FontFace = Skin.FONT_TITLE, Text = if type(level) == "number" then `LV {level}` else "", TextColor3 = C.accent, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	make("TextLabel", {
		Name = "Rating", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 22), Size = UDim2.fromOffset(60, 16), BackgroundTransparency = 1,
		FontFace = Skin.FONT_TEXT, Text = if type(rating) == "number" then stars(rating) else "", TextColor3 = C.accent, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	if not isMe then
		local visit = make("TextButton", {
			Name = "VisitButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Color3.fromRGB(255, 107, 142), FontFace = Skin.FONT_TEXT, Text = "🏠", TextColor3 = C.cream, TextSize = 16, AutoButtonColor = true,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, visit)
		make("UIStroke", { Color = C.ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, visit)
		visit.Activated:Connect(function()
			if os.clock() - lastVisit < VISIT_COOLDOWN then
				return
			end
			lastVisit = os.clock()
			Remotes.RequestVisit:FireServer(p.UserId)
			log("visit ->", p.Name)
		end)
	end
	loadRole(p, refresh)
	loadFriend(p, refresh)
end

function refresh()
	if list == nil then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local all = Players:GetPlayers()
	table.sort(all, function(a, b)
		if (a == player) ~= (b == player) then
			return a == player -- me first
		end
		local la, lb = a:GetAttribute("DF_Level") or 0, b:GetAttribute("DF_Level") or 0
		if la ~= lb then
			return la > lb
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	for i, p in all do
		addRow(p, i)
	end
	if countLabel then
		countLabel.Text = `{#all} / {maxPlayers()}`
	end
	if panel then
		local rows = math.min(#all, MAX_ROWS)
		panel.Size = UDim2.fromOffset(WIDTH, 40 + rows * (ROW_H + 4) + 10)
	end
end

local function build()
	gui = make("ScreenGui", { Name = "PlayerList", ResetOnSpawn = false, DisplayOrder = 5, IgnoreGuiInset = true, Enabled = true })
	-- in the top-right corner, where Roblox's own list sits; the HUD's right rail (Travel, Visit) starts under it
	panel = make("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(WIDTH, 120),
		BackgroundColor3 = C.walnut, BackgroundTransparency = 0.04,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	make("UIGradient", { Color = ColorSequence.new(C.panelTop, C.panelBottom), Rotation = 90 }, panel)
	make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local rim = make("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 13) }, rim)
	make("UIStroke", { Color = C.edge, Thickness = 1, Transparency = 0.7 }, rim)
	make("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(150, 28), FontFace = Skin.FONT_TITLE,
		Text = "PLAYERS", TextColor3 = C.accent, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	countLabel = make("TextLabel", {
		Name = "Count", AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(90, 22),
		FontFace = Skin.FONT_TEXT, Text = "", TextColor3 = C.textDim, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)
	list = make("ScrollingFrame", {
		Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 1, -46),
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIScale", { Name = "Fit" }, panel)

	-- shrink on short screens (phones)
	local function fit()
		local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		;(panel :: Frame):FindFirstChild("Fit").Scale = math.clamp(view.Y / 720, 0.6, 1.1)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

function PlayerListController.Toggle()
	if gui == nil then
		return
	end
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		refresh()
	end
end

function PlayerListController.Init(controllers)
	others = controllers
end

local function watch(p: Player)
	for _, attr in { "DF_Level", "DF_Rating", "DF_OneOfOne" } do
		p:GetAttributeChangedSignal(attr):Connect(function()
			if gui and gui.Enabled then
				refresh()
			end
		end)
	end
end

function PlayerListController.Start()
	-- switch Roblox's own list off (CoreGui can reject the call until it is ready, so retry)
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
	build()
	refresh()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watch(p)
		if gui and gui.Enabled then
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if gui and gui.Enabled then
				refresh()
			end
		end)
	end)
	-- Tab hides / shows it (the key Roblox's own list used). No HUD tile any more: the list is always on screen.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Tab then
			PlayerListController.Toggle()
		end
	end)
	log("ready: Roblox's list is off; ours is always shown top-right (Tab hides / shows it)")
end

-- The list's panel (HudLayoutController keeps the right-hand HUD tiles under it).
function PlayerListController.GetPanel(): Frame?
	return panel
end

return PlayerListController
