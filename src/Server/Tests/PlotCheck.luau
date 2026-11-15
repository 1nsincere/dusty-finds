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
		check("Shelves L3 + Showroom -> 12 display, 4 exhibit", slotsOn(1, "DisplaySlots") == 12 and slotsOn(1, "ExhibitSlots") == 4)
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

		-- release and reuse
		releasingCallback(P[2])
		check("release resets sign, owner, slots and decor", plot(2).Sign.SurfaceGui.OwnerName.Text == "For Sale" and plot(2):GetAttribute("OwnerUserId") == nil and slotsOn(2, "DisplaySlots") == 3 and decorHiddenProperly(2, "Rug") and decorHiddenProperly(2, "PottedPlant1") and PlotService.GetPlot(P[2]) == nil)
		releasingCallback(P[2])
		check("double release is harmless", PlotService.GetPlot(P[2]) == nil)
		upgradesById[P7] = { NeonSign = 1 }
		loadedCallback(P7)
		check("the freed plot goes to the next player with their decor", PlotService.GetPlot(P7) == plot(2) and decorShown(2, "NeonSign") and plot(2).Sign.SurfaceGui.OwnerName.Text == "Shop7")
		check("the real Plots folder was not touched", workspace.Plots.Plot1:GetAttribute("OwnerUserId") == nil or workspace.Plots.Plot1:GetAttribute("OwnerUserId") ~= 5001)
	end)

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
