-- LayoutSlotsController.luau (StarterPlayerScripts.Client.Controllers.LayoutSlotsController)
-- Purpose: the "Shop layouts" window (docs/12 Stage 5, Saved Layouts pass: 3 slots, VIP: +1): save the shop layout you have NOW into
-- a slot, or put a saved one on your shop in one tap. Opened from Edit Mode's "Layouts" button (EditModeController).
-- Owner: Dev 1 (Ace). Depends on: Shared.Config.Monetization (slot count), Shared.Remotes (RequestSaveLayoutSlot,
-- RequestLoadLayoutSlot), ClientState (entitlements, layoutSlots), UiSkin + HudSkinController (look).
-- The server checks everything (pass, slot number, and the same layout rules as a normal save); this only shows and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Monetization = require(Shared:WaitForChild("Config"):WaitForChild("Monetization"))
local UiSkin = require(Shared:WaitForChild("Config"):WaitForChild("UiSkin"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local LayoutSlotsController = {}

local player = Players.LocalPlayer
local others: { [string]: any } = {}
local gui: ScreenGui? = nil
local list: Frame? = nil

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.new()
	f.Parent = parent
	local skin = others.HudSkinController
	if skin and skin.Panel then
		skin.Panel(f)
	else
		f.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
	end
	return f
end

local function text(parent: Instance, name: string, value: string, size: UDim2, position: UDim2?, color: Color3?, font: Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position or UDim2.new()
	l.TextScaled = true
	l.FontFace = font or UiSkin.FONT_TEXT
	l.TextColor3 = color or UiSkin.COLORS.text
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Text = value
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, size: UDim2, position: UDim2?, onClick: () -> (), color: Color3?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = name
	b.Image = ""
	b.Size = size
	b.Position = position or UDim2.new()
	b.Parent = parent
	local skin = others.HudSkinController
	if skin and skin.Panel then
		skin.Panel(b)
	end
	if skin and skin.Button then
		skin.Button(b)
	end
	local t = text(b, "Text", label, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), color or UiSkin.COLORS.text, UiSkin.FONT_TITLE)
	t.ZIndex = b.ZIndex + 1
	b.Activated:Connect(onClick)
	return b
end

local function hasSlot(n: number): boolean
	local slots = ClientState.Get("layoutSlots")
	return type(slots) == "table" and type(slots[tostring(n)]) == "table"
end

local function render()
	if list == nil then
		return
	end
	for _, child in (list :: Frame):GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = Monetization.layoutSlots(ClientState.Get("entitlements"))
	if count == 0 then
		text(list :: Frame, "None", "Get Saved Layouts or VIP at the Collector's Corner to keep several shop layouts.", UDim2.new(1, -16, 0, 60), UDim2.fromOffset(8, 4), UiSkin.COLORS.textDim)
		return
	end
	for n = 1, count do
		local row = panel(list :: Frame, "Slot" .. n, UDim2.new(1, -8, 0, 52), nil)
		row.LayoutOrder = n
		text(row, "Name", `Layout {n}`, UDim2.new(0, 110, 0, 22), UDim2.fromOffset(10, 6), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
		text(row, "State", if hasSlot(n) then "Saved" else "Empty", UDim2.new(0, 110, 0, 16), UDim2.fromOffset(10, 30), if hasSlot(n) then UiSkin.COLORS.good else UiSkin.COLORS.textDim, UiSkin.FONT_TEXT, Enum.TextXAlignment.Left)
		button(row, "Save", "Save here", UDim2.fromOffset(110, 34), UDim2.new(1, -240, 0, 9), function()
			Remotes.RequestSaveLayoutSlot:FireServer(n)
		end)
		local use = button(row, "Use", "Use", UDim2.fromOffset(110, 34), UDim2.new(1, -120, 0, 9), function()
			Remotes.RequestLoadLayoutSlot:FireServer(n)
		end, if hasSlot(n) then UiSkin.COLORS.money else UiSkin.COLORS.textDim)
		use.Active = hasSlot(n)
	end
end

function LayoutSlotsController.Close()
	if gui then
		gui.Enabled = false
	end
end

function LayoutSlotsController.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "LayoutSlots"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 20
	local w = panel(screen, "Window", UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.5, 0.5))
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(480, 330)
	limit.Parent = w
	text(w, "Title", "SHOP LAYOUTS", UDim2.new(0.6, 0, 0, 30), UDim2.fromOffset(14, 8), UiSkin.COLORS.text, UiSkin.FONT_TITLE, Enum.TextXAlignment.Left)
	text(w, "Hint", "\"Save here\" keeps your shop the way it is saved now. \"Use\" puts a saved layout on your shop.", UDim2.new(1, -28, 0, 28), UDim2.fromOffset(14, 40), UiSkin.COLORS.accent, UiSkin.FONT_TEXT, Enum.TextXAlignment.Left)
	button(w, "Close", "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), LayoutSlotsController.Close)
	local holder = Instance.new("Frame")
	holder.Name = "List"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(12, 76)
	holder.Size = UDim2.new(1, -24, 1, -88)
	holder.Parent = w
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	screen.Parent = player:WaitForChild("PlayerGui")
	gui, list = screen, holder
end

function LayoutSlotsController.Open()
	if gui == nil then
		build()
	end
	render();
	(gui :: ScreenGui).Enabled = true
end

function LayoutSlotsController.Init(controllers)
	others = controllers
end

function LayoutSlotsController.Start()
	for _, key in { "layoutSlots", "entitlements" } do
		ClientState.OnChanged(key, function()
			if LayoutSlotsController.IsOpen() then
				render()
			end
		end)
	end
end

return LayoutSlotsController
