-- PlotCheck.luau (ServerScriptService.Server.Tests.PlotCheck)
-- Purpose: tests PlotService: plot assignment, sign, slot counts, decor visibility, release and reuse.
-- Owner: Dev 1 (Ace). Depends on: PlotService, Workspace.Plots, Shared.Config.
-- Safe by design: runs a COPY of PlotService on a COPY of Workspace.Plots with a fake DataService and mock players,
-- so the running game is untouched. Run in the Studio command bar while Playing (Server):
--   require(game.ServerScriptService.Server.Tests.PlotCheck).run()

local ServerScriptService = game:GetService("ServerScriptService")

local PlotCheck = {}

function PlotCheck.run()
	local lines: { string } = {}
	local passCount, failCount = 0, 0
	local function check(name: string, cond: boolean, detail: any?)
		if cond then
			passCount += 1
			table.insert(lines, "PASS " .. name)
		else
			failCount += 1
			table.insert(lines, `FAIL {name}{if detail ~= nil then " -> " .. tostring(detail) else ""}`)
		end
	end

	local plotsCopy = workspace.Plots:Clone()
	plotsCopy.Name = "PlotsCheckCopy"
	for _, plot in plotsCopy:GetChildren() do
		plot:SetAttribute("OwnerUserId", nil)
	end
	plotsCopy.Parent = workspace

	local kit = Instance.new("Folder")
	kit.Name = "PlotCheckKit"
	ServerScriptService.Server.Lib:Clone().Parent = kit
	local services = Instance.new("Folder")
	services.Name = "Services"
	services.Parent = kit
	local serviceCopy = ServerScriptService.Server.Services.PlotService:Clone()
	serviceCopy.Parent = services
	serviceCopy.Source = string.gsub(serviceCopy.Source, 'workspace:FindFirstChild%("Plots"%)', 'workspace:FindFirstChild("PlotsCheckCopy")')
	kit.Parent = ServerScriptService

	-- Decor is switched off in Config until the decor shop (Economy.ClosedUpgradeTabs). The decor checks below test the
	-- showing code the decor shop will reuse, so they run with every tab open; the switch itself is checked at the end.
	local Economy = require(game:GetService("ReplicatedStorage").Shared.Config.Economy)
	local savedClosedTabs = Economy.ClosedUpgradeTabs
	Economy.ClosedUpgradeTabs = {}

	local ok, err = pcall(function()
		local upgradesById: { [any]: { [string]: number } } = {}
		local loadedCallback, releasingCallback
		local fakeDS = {
			GetValue = function(player, path)
				return table.clone(upgradesById[player] or {})
			end,
			OnPlayerLoaded = function(cb)
				loadedCallback = cb
			end,
			OnPlayerReleasing = function(cb)
				releasingCallback = cb
			end,
		}
		local PlotService = require(serviceCopy)
		PlotService.Init({ DataService = fakeDS })
		PlotService.Start()

		local function newPlayer(i: number, upgrades: { [string]: number }?): any
			local p = { UserId = 5000 + i, Name = "Mock" .. i, DisplayName = "Shop" .. i, CharacterAdded = Instance.new("BindableEvent").Event }
			upgradesById[p] = upgrades or {}
			return p
		end
		local function plot(n: number): Model
			return plotsCopy["Plot" .. n]
		end
		local function slotsOn(n: number, folder: string): number
			local count = 0
			for _, slot in plot(n)[folder]:GetChildren() do
				if slot:GetAttribute("Enabled") then
					count += 1
				end
			end
			return count
		end
		local function decorShown(n: number, name: string): boolean
			local slot = plot(n).DecorSlots[name]
			for _, part in slot:GetDescendants() do
				if part:IsA("BasePart") then
					return part.Transparency < 1
				end
			end
			return false
		end
		local function decorHiddenProperly(n: number, name: string): boolean
			local slot = plot(n).DecorSlots[name]
			for _, part in slot:GetDescendants() do
				if part:IsA("BasePart") and (part.Transparency ~= 1 or part.CanCollide) then
					return false
				end
			end
			return slot:GetAttribute("Visible") == false
		end
		local DECOR = { "PottedPlant1", "PottedPlant2", "Rug", "WallPosters", "PendantLamps", "NeonSign" }

		check("Start found 6 plots", (function()
			local n = 0
			for _, c in plotsCopy:GetChildren() do
				if c:IsA("Model") then
					n += 1
				end
			end
			return n == 6
		end)())
		-- an unanchored part falls out of the world in Play (seen once: every shop and the whole town vanished)
		check("every part in Workspace.Plots and Workspace.Environment is Anchored", (function()
			local loose = {}
			for _, root in { workspace:FindFirstChild("Plots"), workspace:FindFirstChild("Environment") } do
				for _, d in root:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						table.insert(loose, d:GetFullName())
					end
				end
			end
			if #loose > 0 then
				return false, `{#loose} loose, e.g. {loose[1]}`
			end
			return true
		end)())
		check("all decor starts hidden (Transparency 1, no collision)", (function()
			for _, name in DECOR do
				if not decorHiddenProperly(1, name) then
					return false
				end
			end
			return true
		end)())

		-- assignment
		local P = {}
		for i = 1, 6 do
			P[i] = newPlayer(i)
			loadedCallback(P[i])
		end
		for i = 1, 6 do
			check("player " .. i .. " gets Plot" .. i .. " and its sign", PlotService.GetPlot(P[i]) == plot(i) and plot(i).Sign.SurfaceGui.OwnerName.Text == "Shop" .. i and plot(i):GetAttribute("OwnerUserId") == 5000 + i)
		end
		local P7 = newPlayer(7)
		check("7th player gets no plot and no error", pcall(loadedCallback, P7) and PlotService.GetPlot(P7) == nil)
		check("assign twice is harmless", (function()
			local before = PlotService.GetPlot(P[2])
			loadedCallback(P[2])
			return PlotService.GetPlot(P[2]) == before
		end)())

		-- slots
		check("default slots: 3 display, 1 exhibit", slotsOn(1, "DisplaySlots") == 3 and slotsOn(1, "ExhibitSlots") == 1)
		upgradesById[P[1]] = { DisplayShelves = 2 }
		PlotService.RefreshSlots(P[1])
		check("Display Shelves L2 -> 9 display slots", slotsOn(1, "DisplaySlots") == 9)
		upgradesById[P[1]] = { DisplayShelves = 3, Showroom = 1 }
		PlotService.RefreshSlots(P[1])
		check("Shelves L3 + Showroom -> 12 display, 10 exhibit (1 + 9 upstairs)", slotsOn(1, "DisplaySlots") == 12 and slotsOn(1, "ExhibitSlots") == 10, slotsOn(1, "ExhibitSlots"))
		check("another plot's slots are unaffected", slotsOn(2, "DisplaySlots") == 3 and slotsOn(2, "ExhibitSlots") == 1)

		-- decor
		check("no decor owned: everything hidden on an owned plot", (function()
			for _, name in DECOR do
				if not decorHiddenProperly(2, name) then
					return false
				end
			end
			return true
		end)())
		upgradesById[P[2]] = { Rug = 1, PottedPlants = 1 }
		PlotService.RefreshSlots(P[2])
		check("Rug and first plant shown", decorShown(2, "Rug") and decorShown(2, "PottedPlant1"))
		check("second plant (level 2) still hidden", decorHiddenProperly(2, "PottedPlant2"))
		check("unowned decor stays hidden", decorHiddenProperly(2, "NeonSign") and decorHiddenProperly(2, "PendantLamps") and decorHiddenProperly(2, "WallPosters"))
		check("shown decor does not collide by default", (function()
			for _, part in plot(2).DecorSlots.Rug:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					return false
				end
			end
			return plot(2).DecorSlots.Rug:GetAttribute("Visible") == true
		end)())
		upgradesById[P[2]] = { Rug = 1, PottedPlants = 2 }
		PlotService.RefreshSlots(P[2])
		check("Potted Plants level 2 shows the second plant", decorShown(2, "PottedPlant2") and decorShown(2, "PottedPlant1"))
		check("decor on another plot is not affected", decorHiddenProperly(3, "Rug") and decorHiddenProperly(1, "Rug"))
		-- a part can say how it looks when shown
		local lamp = plot(3).DecorSlots.PendantLamps:FindFirstChildWhichIsA("BasePart")
		lamp:SetAttribute("VisibleTransparency", 0.4)
		lamp:SetAttribute("VisibleCanCollide", true)
		upgradesById[P[3]] = { PendantLamps = 1 }
		PlotService.RefreshSlots(P[3])
		check("VisibleTransparency / VisibleCanCollide attributes are honoured", math.abs(lamp.Transparency - 0.4) < 1e-6 and lamp.CanCollide == true)
		upgradesById[P[3]] = {}
		PlotService.RefreshSlots(P[3])
		check("removing the upgrade hides it again", lamp.Transparency == 1 and lamp.CanCollide == false)

		-- shelf attributes (set by DisplayService.SyncSlots) must not leak to the next owner
		plot(2).DisplaySlots.Slot1:SetAttribute("ItemId", "Teacup")
		plot(2).DisplaySlots.Slot1:SetAttribute("Golden", true)
		plot(2).DisplaySlots.Slot1:SetAttribute("Stars", 3)

		-- ===== expansion rooms (Back Room, Showroom), tested on plot 4: it is rotated 180 degrees in the real map =====
		local p4 = plot(4)
		local wall4 = p4.Walls.BackWall
		local wallSize, wallPos = wall4.Size, wall4.Position
		local function countNamed(root: Instance, name: string): number
			local n = 0
			for _, d in root:GetDescendants() do
				if d.Name == name then
					n += 1
				end
			end
			return n
		end
		check("expansions: templates exist in ServerStorage.Expansions", game:GetService("ServerStorage"):FindFirstChild("Expansions") ~= nil and game:GetService("ServerStorage").Expansions:FindFirstChild("BackRoom") ~= nil and game:GetService("ServerStorage").Expansions:FindFirstChild("Showroom") ~= nil)
		check("expansions: no rooms before buying, back wall closed", p4:FindFirstChild("Expansion_BackRoom") == nil and p4.Benches:FindFirstChild("Bench2") == nil and wall4.Transparency == 0 and wall4.CanCollide == true)
		upgradesById[P[4]] = { BackRoom = 1 }
		PlotService.RefreshSlots(P[4])
		check("Back Room: the room is cloned into the plot", p4:FindFirstChild("Expansion_BackRoom") ~= nil)
		check("Back Room: Bench2 (with its Prompt) is in the plot's Benches, where restoration looks", p4.Benches:FindFirstChild("Bench2") ~= nil and p4.Benches.Bench2:FindFirstChildWhichIsA("ProximityPrompt") ~= nil)
		check("Back Room: the FishTank decor model is in DecorSlots and hidden until bought", p4.DecorSlots:FindFirstChild("FishTank") ~= nil and decorHiddenProperly(4, "FishTank"))
		check("Back Room: the back wall opens by restyling only (same size and position)", wall4.Transparency == 1 and wall4.CanCollide == false and wall4.Size == wallSize and wall4.Position == wallPos)
		check("Back Room: full width behind the shop, no plaster fill (Showroom is upstairs since 2026-11-24)", countNamed(p4, "WallFill") == 0)
		-- a scaled shop (1.4x, 56 studs): the room has to scale with the plot
		do
			local p5 = plot(5)
			local p5Scale = p5:GetScale() -- the live shops are already 1.4x since the circle-park layout: put it back afterwards
			p5:ScaleTo(1.4)
			upgradesById[P[5]] = { BackRoom = 1 }
			PlotService.RefreshSlots(P[5])
			local room = p5:FindFirstChild("Expansion_BackRoom")
			local templateFloor = game:GetService("ServerStorage").Expansions.BackRoom.Shell.Floor
			check("scaled shop: the Back Room is scaled 1.4x with the plot", room ~= nil and math.abs(room.Shell.Floor.Size.X - templateFloor.Size.X * 1.4) < 0.05, room and tostring(room.Shell.Floor.Size))
			local lp5 = p5.Floor.CFrame:PointToObjectSpace(room.Shell.Floor.Position)
			check("scaled shop: the room lies behind the scaled back wall (Z 28 to 62)", lp5.Z > 28 and lp5.Z < 62, tostring(lp5))
			upgradesById[P[5]] = nil
			PlotService.RefreshSlots(P[5])
			p5:ScaleTo(p5Scale)
		end
		-- limits written for the 40-stud shop, scaled by the plot's real size (56-stud shops are 1.4x)
		local k4 = p4.Floor.Size.X / 40
		local lp = p4.Floor.CFrame:PointToObjectSpace(p4.Expansion_BackRoom.Shell.Floor.Position)
		check("Back Room: the floor lies behind the back wall in the plot's own axes, full width (also on a rotated plot)", lp.Z > 20 * k4 and lp.Z < 44 * k4 and math.abs(lp.X) < 1 * k4 and p4.Expansion_BackRoom.Shell.Floor.Size.X > 39 * k4, tostring(lp))
		local bp = p4.Floor.CFrame:PointToObjectSpace(p4.Benches.Bench2.Position)
		check("Back Room: Bench2 stands inside the room", bp.Z > 20 * k4 and bp.Z < 44 * k4 and bp.X < 0, tostring(bp))
		upgradesById[P[4]] = { BackRoom = 1, FishTank = 1 }
		PlotService.RefreshSlots(P[4])
		check("Fish Tank shows once bought", decorShown(4, "FishTank"))
		upgradesById[P[4]] = { BackRoom = 1, Showroom = 1, FishTank = 1 }
		PlotService.RefreshSlots(P[4])
		PlotService.RefreshSlots(P[4])
		check("both rooms: Showroom added, wall still open", p4:FindFirstChild("Expansion_Showroom") ~= nil and countNamed(p4, "WallFill") == 0 and wall4.Transparency == 1)
		do
			local stairs = p4.Expansion_Showroom:FindFirstChild("Stairs", true)
			local upper = p4.Expansion_Showroom:FindFirstChild("UpperFloor", true)
			check("Showroom: stairs and the upper floor are built", stairs ~= nil and upper ~= nil and #stairs:GetChildren() > 10)
			local top = upper and upper:FindFirstChild("FloorMain")
			local tp = top and p4.Floor.CFrame:PointToObjectSpace(top.Position)
			check("Showroom: the upper floor is inside the building at wall-top height", tp ~= nil and math.abs(tp.X) < 28 * k4 / 1.4 and math.abs(tp.Z) < 28 * k4 / 1.4 and tp.Y > 12 * k4, tostring(tp))
			local e2 = p4.ExhibitSlots:FindFirstChild("Exhibit2")
			check("Showroom: pedestal 2 is shown and solid upstairs", e2 ~= nil and e2:GetAttribute("Enabled") == true and e2.Transparency == 0 and e2.CanCollide == true)
			local shell = p4:FindFirstChild("Facade") and p4.Facade:FindFirstChild("Shell")
			local jars = shell and shell:FindFirstChild("Shop_Jars")
			local nook = shell and shell:FindFirstChild("Shop_NookWood")
			local jarPart = jars and jars:FindFirstChildWhichIsA("BasePart", true)
			local nookPart = nook and nook:FindFirstChildWhichIsA("BasePart", true)
			check("Showroom: the jar shelf where the stairs go is hidden (HideWithExpansion)", jarPart ~= nil and nookPart ~= nil and jarPart.Transparency == 1 and nookPart.Transparency == 1)
			local vault = shell and shell:FindFirstChild("Shop_VaultTrim")
			local vaultPart = vault and vault:FindFirstChildWhichIsA("BasePart", true)
			check("Showroom: the downstairs exhibit alcoves (vault) are hidden", vaultPart ~= nil and vaultPart.Transparency == 1)
			local e1 = p4.ExhibitSlots:FindFirstChild("Exhibit1")
			local want = e1 and e1:GetAttribute("ExpansionCFrame")
			check("Showroom: pedestal 1 moved upstairs (ExpansionCFrame)", typeof(want) == "CFrame" and (e1.Position - (p4.Floor.CFrame * want).Position).Magnitude < 0.01)
		end
		check("refreshing again does not duplicate rooms, benches or decor", countNamed(p4, "Expansion_BackRoom") == 1 and countNamed(p4, "Bench2") == 1 and countNamed(p4, "FishTank") == 1)
		check("Showroom: the Fountain decor exists and is hidden until bought", p4.DecorSlots:FindFirstChild("Fountain") ~= nil and decorHiddenProperly(4, "Fountain"))
		upgradesById[P[4]] = { Showroom = 1 }
		PlotService.RefreshSlots(P[4])
		check("losing the Back Room removes its room, bench and decor but keeps the Showroom", p4:FindFirstChild("Expansion_BackRoom") == nil and p4.Benches:FindFirstChild("Bench2") == nil and p4.DecorSlots:FindFirstChild("FishTank") == nil and p4:FindFirstChild("Expansion_Showroom") ~= nil)
		check("Showroom alone keeps the back wall closed (it is upstairs, nothing behind the wall)", wall4.Transparency == 0 and wall4.CanCollide == true)
		releasingCallback(P[4])
		check("release removes every room, bench and decor model and closes the wall again", p4:FindFirstChild("Expansion_Showroom") == nil and countNamed(p4, "Bench2") == 0 and p4.DecorSlots:FindFirstChild("Fountain") == nil and wall4.Transparency == 0 and wall4.CanCollide == true)
		do
			local e2 = p4.ExhibitSlots:FindFirstChild("Exhibit2")
			check("locked upstairs pedestal is hidden and not solid (no floating pedestal)", e2 ~= nil and e2:GetAttribute("Enabled") == false and e2.Transparency == 1 and e2.CanCollide == false)
			local nook = p4.Facade.Shell:FindFirstChild("Shop_NookWood")
			local nookPart = nook and nook:FindFirstChildWhichIsA("BasePart", true)
			check("without the Showroom the jar shelf is back (original transparency)", nookPart ~= nil and nookPart.Transparency == (nookPart:GetAttribute("ShownTransparency") or 0) and nookPart.Transparency < 1)
			local e1 = p4.ExhibitSlots:FindFirstChild("Exhibit1")
			local home = e1 and e1:GetAttribute("HomeCFrame")
			check("without the Showroom pedestal 1 is back downstairs (HomeCFrame)", typeof(home) == "CFrame" and (e1.Position - (p4.Floor.CFrame * home).Position).Magnitude < 0.01)
		end

		-- release and reuse
		releasingCallback(P[2])
		check("release clears the shelf attributes (ItemId, Golden, Stars)", plot(2).DisplaySlots.Slot1:GetAttribute("ItemId") == nil and plot(2).DisplaySlots.Slot1:GetAttribute("Golden") == nil and plot(2).DisplaySlots.Slot1:GetAttribute("Stars") == nil)
		check("release resets sign, owner, slots and decor", plot(2).Sign.SurfaceGui.OwnerName.Text == "For Sale" and plot(2):GetAttribute("OwnerUserId") == nil and slotsOn(2, "DisplaySlots") == 3 and decorHiddenProperly(2, "Rug") and decorHiddenProperly(2, "PottedPlant1") and PlotService.GetPlot(P[2]) == nil)
		releasingCallback(P[2])
		check("double release is harmless", PlotService.GetPlot(P[2]) == nil)
		upgradesById[P7] = { NeonSign = 1 }
		loadedCallback(P7)
		check("the freed plot goes to the next player with their decor", PlotService.GetPlot(P7) == plot(2) and decorShown(2, "NeonSign") and plot(2).Sign.SurfaceGui.OwnerName.Text == "Shop7")
		check("the real Plots folder was not touched", workspace.Plots.Plot1:GetAttribute("OwnerUserId") == nil or workspace.Plots.Plot1:GetAttribute("OwnerUserId") ~= 5001)

		-- the decor switch (2026-11-24): with the Decor tab closed, decor someone already owns is not shown
		Economy.ClosedUpgradeTabs = { Decor = true }
		PlotService.RefreshSlots(P7)
		check("Decor tab closed: owned decor (Neon Sign) is hidden and not solid", decorHiddenProperly(2, "NeonSign"))
		Economy.ClosedUpgradeTabs = {}
		PlotService.RefreshSlots(P7)
		check("Decor tab open again: the same decor shows again", decorShown(2, "NeonSign"))
	end)
	Economy.ClosedUpgradeTabs = savedClosedTabs

	kit:Destroy()
	plotsCopy:Destroy()
	if not ok then
		failCount += 1
		table.insert(lines, "FAIL test runner crashed: " .. tostring(err))
	end
	for _, line in lines do
		print(line)
	end
	print(`[PlotCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return PlotCheck
