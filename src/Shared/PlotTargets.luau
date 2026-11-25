-- PlotTargets.luau (ReplicatedStorage.Shared.PlotTargets)
-- Purpose: which parts of a shop a paint or a skin covers. One answer for the server (PaintService draws them for real) and
-- the client (PreviewController tries them on for 60 seconds), so a preview always matches what you would really get.
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Walls = Plot.Walls children + everything in Facade.Shell.Shop_Walls; Floor = Facade.Shell.Shop_Floor.
-- Pieces = shelves (Plot.Shelves) / pedestals (Plot.ExhibitSlots) that carry a PieceId (SkinService uses the same rule).

local PlotTargets = {}

local function addAll(list: { BasePart }, container: Instance?)
	if container == nil then
		return
	end
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	if container:IsA("BasePart") then
		table.insert(list, container)
	end
end

-- kind = "Wall" | "Floor"
function PlotTargets.paint(plot: Instance, kind: string): { BasePart }
	local list: { BasePart } = {}
	local facade = plot:FindFirstChild("Facade")
	local shell = facade and facade:FindFirstChild("Shell")
	if kind == "Wall" then
		local walls = plot:FindFirstChild("Walls")
		if walls then
			for _, part in walls:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(list, part)
				end
			end
		end
		addAll(list, shell and shell:FindFirstChild("Shop_Walls"))
	else
		addAll(list, shell and shell:FindFirstChild("Shop_Floor"))
	end
	return list
end

-- kind = "Shelf" | "Pedestal"
function PlotTargets.pieces(plot: Instance, kind: string): { BasePart }
	local FOLDER = { Shelf = "Shelves", Pedestal = "ExhibitSlots" }
	local folder = FOLDER[kind] and plot:FindFirstChild(FOLDER[kind])
	local list: { BasePart } = {}
	for _, part in if folder then folder:GetChildren() else {} do
		if part:IsA("BasePart") and part:GetAttribute("PieceId") ~= nil then
			table.insert(list, part)
		end
	end
	return list
end

return PlotTargets
