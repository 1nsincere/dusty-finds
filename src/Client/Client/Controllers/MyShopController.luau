-- MyShopController.luau
-- Purpose: a "My Shop" button on the HUD (left button column) that takes you straight back to your own shop.
-- The shops are spread over the whole canal town now, so walking home after the Warehouse would be dead time.
-- Owner: Dev 1 (Ace), approved by Dev 3 (Sean) for the HUD. Depends on: Shared.Remotes.RequestVisit (Sean's
-- ShopSocialService.Visit already sends you home when you visit your own UserId; it validates and rate-limits on the server),
-- StarterGui HUD.LeftButtons (an existing button is copied as the template so the style always matches).
-- Client only: no new remote, nothing to exploit (the server decides where you land).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local MyShopController = {}
local DEBUG = true
local COOLDOWN = 1.5 -- the server allows one RequestVisit per second; this just avoids spam-clicks

local function log(...)
	if DEBUG then
		print("[MyShopController]", ...)
	end
end

local function goHome()
	Remotes.RequestVisit:FireServer(Players.LocalPlayer.UserId)
end

function MyShopController.Init(_others) end

function MyShopController.Start()
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD", 15)
		local column = hud and hud:WaitForChild("LeftButtons", 15)
		if column == nil then
			warn("[MyShopController] HUD.LeftButtons not found: no My Shop button")
			return
		end
		if column:FindFirstChild("MyShop") then
			return
		end
		local template = column:FindFirstChild("Collection") or column:FindFirstChildWhichIsA("GuiButton")
		if template == nil then
			warn("[MyShopController] no HUD button to copy: no My Shop button")
			return
		end
		local button = template:Clone()
		button.Name = "MyShop"
		-- the copy keeps the look; clear anything that belongs to the original button's screen
		for _, d in button:GetDescendants() do
			if d:IsA("LocalScript") or d:IsA("Script") then
				d:Destroy()
			end
		end
		local icon = button:FindFirstChild("Icon", true)
		if icon and icon:IsA("TextLabel") then
			icon.Text = "🏠"
		elseif button:IsA("TextButton") then
			button.Text = "🏠"
		end
		local label = button:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = "My Shop"
		end
		if button:IsA("GuiObject") then
			local highest = 0
			for _, other in column:GetChildren() do
				if other:IsA("GuiObject") and other.LayoutOrder > highest then
					highest = other.LayoutOrder
				end
			end
			button.LayoutOrder = highest + 1
		end
		button.Parent = column
		local last = 0
		button.Activated:Connect(function()
			if os.clock() - last < COOLDOWN then
				return
			end
			last = os.clock()
			goHome()
		end)
		log("ready: My Shop button added")
	end)
end

return MyShopController
