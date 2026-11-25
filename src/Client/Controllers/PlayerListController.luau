-- PlayerListController.luau
-- Purpose: our own player list instead of Roblox's. The standard list is switched off (it covered the HUD on desktop and does
-- not match the game); a "Players" tile on the right rail (or the Tab key) opens a walnut window listing everyone on this
-- server: headshot, display name, @username, and a Visit button that takes you to their shop (the existing RequestVisit,
-- which the server already validates). Live: rows update as players join and leave. Client only.
-- Owner: Dev 1 (Ace). Depends on: HudSkinController (HUD tile), WindowKit (window look), HudKit, Shared.Config.UiSkin,
-- Shared.Remotes.RequestVisit. Must start before HudLayoutController (which places the tile).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WindowKit = require(script.Parent.Parent:WaitForChild("WindowKit"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit"))

local PlayerListController = {}
local DEBUG = true
local C = Skin.COLORS
local make = HudKit.make
local player = Players.LocalPlayer
local others: { [string]: any } = {}

local WIDTH, ROW_H, MAX_ROWS = 400, 56, 7
local VISIT_COOLDOWN = 1.5 -- the server allows one RequestVisit per second

local gui: ScreenGui? = nil
local list: ScrollingFrame? = nil
local countLabel: TextLabel? = nil
local headshots: { [number]: string } = {}
local lastVisit = 0

local function log(...)
	if DEBUG then
		print("[PlayerListController]", ...)
	end
end

local function headshot(userId: number, into: ImageLabel)
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

local function addRow(p: Player, order: number)
	local row = make("Frame", { Name = "Row_" .. p.UserId, LayoutOrder = order, BackgroundColor3 = C.walnutLight, Size = UDim2.new(1, -8, 0, ROW_H) }, list)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, row)
	make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
	local avatar = make("ImageLabel", { Name = "Avatar", Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Color3.fromRGB(63, 167, 255), BorderSizePixel = 0 }, row)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
	make("UIStroke", { Color = C.ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, avatar)
	headshot(p.UserId, avatar)
	local isMe = p == player
	make("TextLabel", {
		Name = "DisplayName", BackgroundTransparency = 1, Position = UDim2.fromOffset(60, 6), Size = UDim2.new(1, -170, 0, 24), FontFace = Skin.FONT_TITLE,
		Text = string.upper(p.DisplayName) .. (if isMe then "  (YOU)" else ""), TextColor3 = if isMe then C.accent else C.text, TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	make("TextLabel", {
		Name = "UserName", BackgroundTransparency = 1, Position = UDim2.fromOffset(60, 30), Size = UDim2.new(1, -170, 0, 18), FontFace = Skin.FONT_BODY,
		Text = "@" .. p.Name, TextColor3 = C.textDim, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	if not isMe then
		local visit = make("TextButton", {
			Name = "VisitButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(84, 34),
			BackgroundColor3 = Color3.fromRGB(255, 107, 142), FontFace = Skin.FONT_TITLE, Text = "VISIT", TextColor3 = C.cream, TextSize = 17, AutoButtonColor = true,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, visit)
		make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, visit)
		visit.Activated:Connect(function()
			if os.clock() - lastVisit < VISIT_COOLDOWN then
				return
			end
			lastVisit = os.clock()
			Remotes.RequestVisit:FireServer(p.UserId)
			if gui then
				gui.Enabled = false
			end
			log("visit ->", p.Name)
		end)
	end
end

local function refresh()
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
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	for i, p in all do
		addRow(p, i)
	end
	if countLabel then
		countLabel.Text = `{#all} / {Players.MaxPlayers} in this server`
	end
end

local function build()
	gui = make("ScreenGui", { Name = "PlayerList", ResetOnSpawn = false, DisplayOrder = 5, IgnoreGuiInset = true, Enabled = false })
	local height = 62 + MAX_ROWS * (ROW_H + 6) + 44
	local window = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WIDTH, height), BackgroundColor3 = C.walnut,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(WIDTH, height) }, window)
	make("UIScale", { Name = "Fit" }, window)
	make("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -70, 0, 36), FontFace = Skin.FONT_TITLE, Text = "PLAYERS",
		TextColor3 = C.accent, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
	}, window)
	local close = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = C.panelTop,
		FontFace = Skin.FONT_TEXT, Text = "X", TextColor3 = C.text, TextScaled = true,
	}, window)
	close.Activated:Connect(function()
		(gui :: ScreenGui).Enabled = false
	end)
	WindowKit.Shell(window, { art = "Visit", color = Color3.fromRGB(255, 107, 142) })

	list = make("ScrollingFrame", {
		Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 1, -102), ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.accent, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, window)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	countLabel = make("TextLabel", {
		Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -32, 0, 18),
		FontFace = Skin.FONT_BODY, Text = "", TextColor3 = C.textDim, TextSize = 13,
	}, window)

	-- fit short screens (phones): shrink the window to the screen height
	local function fit()
		local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		;(window:FindFirstChild("Fit") :: UIScale).Scale = math.clamp(view.Y * 0.92 / height, 0.5, 1.15)
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
	Players.PlayerAdded:Connect(function()
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
	-- Tab opens it too (the key Roblox's own list used)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Tab then
			PlayerListController.Toggle()
		end
	end)
	task.spawn(function()
		local skin = others.HudSkinController
		local button = skin and skin.HudButton("Players", Skin.ICONS.Visit)
		if button then
			button.Activated:Connect(PlayerListController.Toggle)
		end
		log("ready: Roblox's list is off; the Players tile or Tab opens ours")
	end)
end

return PlayerListController
