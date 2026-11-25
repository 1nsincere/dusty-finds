-- TravelController.luau
-- Purpose: the Travel menu. A map-pin HUD button opens a list of places (Config.Travel); tapping one asks the server to
-- teleport there (RequestTravel). The server checks everything (id, cooldown, not riding/restoring) and moves the player.
-- Look (2026-11-25): the Figma "Travel" window: walnut shell + title medallion, a two-column grid of destination cards with a
-- coloured icon medallion, name and hint (WindowKit styles the shell, close button and cards).
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Travel, Shared.Config.UiSkin, Remotes.RequestTravel, HudSkinController, WindowKit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Travel = require(Shared.Config:WaitForChild("Travel"))
local Skin = require(Shared.Config:WaitForChild("UiSkin"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WindowKit = require(script.Parent.Parent:WaitForChild("WindowKit"))
local HudKit = require(script.Parent.Parent:WaitForChild("HudKit"))

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

local make = HudKit.make

-- Icon name (UiSkin.Art) and medallion colour per place.
local PLACE_STYLE = {
	MyShop = { art = "Home", color = Color3.fromRGB(63, 167, 255) },
	Plaza = { art = "Star", color = Color3.fromRGB(145, 104, 255) },
	Warehouse = { art = "Crate", color = Color3.fromRGB(31, 194, 165) },
	Museum = { art = "Museum", color = Color3.fromRGB(255, 138, 61) },
	Jeepney = { art = "Jeepney", color = Color3.fromRGB(255, 200, 58) },
	TODA = { art = "Tricycle", color = Color3.fromRGB(145, 104, 255) },
}

local COLUMNS = 2
local CELL_W, CELL_H, GAP = 258, 62, 8

local function build()
	local skin = others.HudSkinController
	gui = make("ScreenGui", { Name = "Travel", ResetOnSpawn = false, DisplayOrder = 5, IgnoreGuiInset = true, Enabled = false })
	local rows = math.ceil(#Travel.PLACES / COLUMNS)
	local width = 16 * 2 + COLUMNS * CELL_W + (COLUMNS - 1) * GAP
	local height = 62 + rows * CELL_H + (rows - 1) * GAP + 40
	local window = make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.walnut,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(width, height) }, window)
	make("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -70, 0, 36),
		FontFace = Skin.FONT_TITLE, Text = "TRAVEL", TextColor3 = C.accent, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
	}, window)
	local close = make("TextButton", {
		Name = "CloseButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = C.panelTop, FontFace = Skin.FONT_TEXT, Text = "X", TextColor3 = C.text, TextScaled = true,
	}, window)
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	WindowKit.Shell(window, { art = "Travel", color = Color3.fromRGB(63, 167, 255) })

	local list = make("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 58), Size = UDim2.new(1, -32, 1, -98) }, window)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL_W, CELL_H), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = COLUMNS,
	}, list)
	for i, place in Travel.PLACES do
		local style = PLACE_STYLE[place.id] or { art = "Travel", color = Color3.fromRGB(63, 167, 255) }
		local row = make("TextButton", {
			Name = place.id, LayoutOrder = i, BackgroundColor3 = C.walnutLight, Text = "", AutoButtonColor = false,
		}, list)
		WindowKit.Card(row, C.walnutLight, 14)
		local medallion = make("Frame", {
			Name = "Medallion", BackgroundColor3 = style.color, BorderSizePixel = 0, Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(44, 44), Active = false,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, medallion)
		make("UIStroke", { Color = C.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, medallion)
		make("ImageLabel", {
			Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(32, 32),
			Image = Skin.Art(style.art), ScaleType = Enum.ScaleType.Fit,
		}, medallion)
		make("TextLabel", {
			Name = "PlaceName", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 6), Size = UDim2.new(1, -72, 0, 26),
			FontFace = Skin.FONT_TITLE, Text = string.upper(place.name), TextColor3 = C.text, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		make("TextLabel", {
			Name = "Hint", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 33), Size = UDim2.new(1, -72, 0, 24),
			FontFace = Skin.FONT_BODY, Text = place.hint or "", TextColor3 = C.textDim, TextSize = 12, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
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
	local footer = make("TextLabel", {
		Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -32, 0, 16),
		FontFace = Skin.FONT_BODY, Text = `Travel takes you there at once · {Travel.COOLDOWN} s cooldown · not while restoring`, TextColor3 = C.textDim, TextSize = 12,
	}, window)
	footer.TextTransparency = 0.2
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
