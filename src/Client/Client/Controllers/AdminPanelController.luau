-- AdminPanelController.luau (StarterPlayerScripts.Client.Controllers)
-- Purpose: the /admin command card. The server's AdminService fires the AdminPanel remote (only at admins listed in
-- Shared.Config.Admins) with the live command list; this controller shows it as a centered card: one row per command
-- with its syntax and what it does, plus a close button. Running /admin again toggles the card closed.
-- Owner: Dev 1 (Ace). Depends on: Shared.Remotes (AdminPanel), UiTheme. No saved data, no other remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiTheme = require(script.Parent.Parent:WaitForChild("UiTheme"))

local AdminPanelController = {}
local DEBUG = true

local player = Players.LocalPlayer
local panel: ScreenGui? = nil

-- "/cash <who> <amount>  (negative takes money)" -> syntax + description (some commands have no description part)
local function parseUsage(usage: string): (string, string)
	local at = string.find(usage, "  (", 1, true)
	if at == nil then
		return usage, ""
	end
	local syntax = string.sub(usage, 1, at - 1)
	local desc = string.sub(usage, at + 3)
	return syntax, string.gsub(desc, "%)$", "")
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
	end
end

local function show(list: { { name: string, usage: string } })
	if panel then
		close() -- /admin while the card is open just closes it
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	panel = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 560, 0, 420)
	card.BackgroundColor3 = UiTheme.Cream
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.Teal
	stroke.Parent = card

	-- Teal header: title, the who-targeting hint, and the close button.
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.Size = UDim2.new(1, 0, 0, 64)
	head.BackgroundColor3 = UiTheme.Teal
	head.BorderSizePixel = 0
	head.Parent = card
	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(0, 12)
	headCorner.Parent = head
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -56, 0, 30)
	title.Position = UDim2.new(0, 16, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = UiTheme.Ink
	title.Text = "⚡ Admin Commands"
	title.Parent = head
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, -56, 0, 16)
	hint.Position = UDim2.new(0, 16, 0, 38)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = UiTheme.Ink
	hint.TextTransparency = 0.2
	hint.Text = "<who> = me | all | others | a player's name"
	hint.Parent = head
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.BackgroundColor3 = UiTheme.Coral
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = UiTheme.Ink
	closeBtn.Text = "✕"
	closeBtn.Parent = head
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(1, 0)
	btnCorner.Parent = closeBtn
	closeBtn.Activated:Connect(close)

	-- The scrollable list: one row per command, sorted the same way the server sorted them.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Commands"
	scroll.Position = UDim2.new(0, 12, 0, 76)
	scroll.Size = UDim2.new(1, -24, 1, -88)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	for i, entry in list do
		local syntax, desc = parseUsage(entry.usage)
		local row = Instance.new("Frame")
		row.Name = entry.name
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -12, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundTransparency = 1
		row.Parent = scroll

		local cmd = Instance.new("TextLabel")
		cmd.Name = "Syntax"
		cmd.Size = UDim2.new(1, 0, 0, 20)
		cmd.BackgroundTransparency = 1
		cmd.Font = Enum.Font.GothamMedium
		cmd.TextSize = 16
		cmd.TextXAlignment = Enum.TextXAlignment.Left
		cmd.TextColor3 = UiTheme.Coral
		cmd.Text = syntax
		cmd.Parent = row

		if desc ~= "" then
			local what = Instance.new("TextLabel")
			what.Name = "Desc"
			what.Position = UDim2.new(0, 0, 0, 20)
			what.Size = UDim2.new(1, 0, 0, 0)
			what.AutomaticSize = Enum.AutomaticSize.Y
			what.BackgroundTransparency = 1
			what.Font = Enum.Font.Gotham
			what.TextSize = 14
			what.TextXAlignment = Enum.TextXAlignment.Left
			what.TextWrapped = true
			what.TextColor3 = UiTheme.Ink
			what.TextTransparency = 0.25
			what.Text = desc
			what.Parent = row
		end
	end
end

function AdminPanelController.Init(_controllers) end

function AdminPanelController.Start()
	-- Only the server decides who gets this: it checks the Admins config before firing, so non-admins never see the card.
	Remotes.AdminPanel.OnClientEvent:Connect(function(list)
		if type(list) == "table" then
			local ok, err = pcall(show, list)
			if not ok then
				warn("[AdminPanelController] failed to show the panel:", err)
			end
		end
	end)
	if DEBUG then
		print("[AdminPanelController] ready: /admin opens the command card")
	end
end

return AdminPanelController