-- TravelController.luau
-- Purpose: the Travel menu. A map-pin HUD button opens a list of places (Config.Travel); tapping one asks the server to
-- teleport there (RequestTravel). The server checks everything (id, cooldown, not riding/restoring) and moves the player.
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Travel, Shared.Config.UiSkin, Remotes.RequestTravel, HudSkinController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Travel = require(Shared.Config:WaitForChild("Travel"))
local Skin = require(Shared.Config:WaitForChild("UiSkin"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TravelController = {}
local DEBUG = true
local C = Skin.COLORS
local others: { [string]: any } = {}
local gui: ScreenGui

local function log(...)
	if DEBUG then
		print("[TravelController]", ...)
	end
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local PLACE_ICON = { MyShop = "MyShop", Plaza = "Star", Warehouse = "Supply", Museum = "Collection", Jeepney = "Travel", TODA = "Travel" }

local function build()
	local skin = others.HudSkinController
	gui = make("ScreenGui", { Name = "Travel", ResetOnSpawn = false, DisplayOrder = 5, IgnoreGuiInset = true, Enabled = false })
	local window = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 72 + #Travel.PLACES * 54),
		BackgroundColor3 = C.panelBottom,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(420, 560) }, window)
	if skin then
		skin.Panel(window)
	end
	make("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -70, 0, 34),
		FontFace = Skin.FONT_TITLE, Text = "TRAVEL", TextColor3 = C.accent, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
	}, window)
	local close = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = C.panelTop, FontFace = Skin.FONT_TEXT, Text = "X", TextColor3 = C.text, TextScaled = true,
	}, window)
	make("UICorner", { CornerRadius = UDim.new(0, Skin.CORNER) }, close)
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	local list = make("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -28, 1, -66) }, window)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, place in Travel.PLACES do
		local row = make("TextButton", {
			Name = place.id, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = C.panelTop, Text = "", AutoButtonColor = false,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, Skin.CORNER) }, row)
		make("UIStroke", { Color = C.edge, Transparency = C.edgeTransparency, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
		make("ImageLabel", {
			Name = "Glyph", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(32, 32),
			Image = Skin.ICONS[PLACE_ICON[place.id] or "Travel"], ScaleType = Enum.ScaleType.Fit,
		}, row)
		make("TextLabel", {
			Name = "PlaceName", BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 4), Size = UDim2.new(1, -60, 0, 24),
			FontFace = Skin.FONT_TEXT, Text = string.upper(place.name), TextColor3 = C.text, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		make("TextLabel", {
			Name = "Hint", BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 27), Size = UDim2.new(1, -60, 0, 16),
			FontFace = Skin.FONT_TEXT, Text = place.hint or "", TextColor3 = C.textDim, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		if skin then
			skin.Button(row)
		end
		row.Activated:Connect(function()
			Remotes.RequestTravel:FireServer(place.id)
			gui.Enabled = false
			log("travel ->", place.id)
		end)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TravelController.Init(controllers)
	others = controllers
end

function TravelController.Start()
	build()
	task.spawn(function()
		local skin = others.HudSkinController
		local button = skin and skin.HudButton("Travel", Skin.ICONS.Travel)
		if button then
			button.Activated:Connect(function()
				gui.Enabled = not gui.Enabled
			end)
		end
		log("ready:", #Travel.PLACES, "places")
	end)
end

return TravelController
