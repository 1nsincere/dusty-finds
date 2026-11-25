-- RestorationSweep.luau (StarterPlayerScripts.Client.Tests.RestorationSweep)
-- Purpose: a dev check, not part of the game. Puts every item model (ReplicatedStorage.Assets.Items) through every step of its
-- recipe in a far-away corner of the world, frames it with the real restoration camera (RestorationView.FitCamera) at a
-- desktop and a phone aspect ratio, and reports anything the player would struggle with: a dirt/rust spot off screen,
-- hidden behind another part or facing away, a polish surface that is missing or invisible, parts that overflow the screen,
-- a minigame that cannot even start. Run from the command bar while playing:
--   require(game.Players.LocalPlayer.PlayerScripts.Client.Tests.RestorationSweep).Run()
-- Owner: Dev 1 (Ace) with Claude. Depends on: RestorationView, Config.Items, Assets.Items. Cleans up after itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RestorationView = require(script.Parent.Parent.Minigames.RestorationView)
local SpotClear = require(script.Parent.Parent.Minigames.SpotClear)
local Rub = require(script.Parent.Parent.Minigames.Rub)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local Sweep = {}

local FOV = 62
local ASPECTS = { { "desktop 16:9", 16 / 9 }, { "phone 2.2:1", 2.2 } }
-- the part of the screen the player can really work in (hint and chips on top, progress bar at the bottom)
local SAFE = { x0 = 0.04, x1 = 0.96, y0 = 0.14, y1 = 0.80 }
local ORIGIN = CFrame.new(900, 300, 900)
local FLAT = Vector3.new(0, 0, -1)

local function project(cf: CFrame, aspect: number, point: Vector3): (number?, number?)
	local v = cf:PointToObjectSpace(point)
	if v.Z >= -0.05 then
		return nil, nil
	end
	local tanV = math.tan(math.rad(FOV) / 2)
	local nx = (v.X / -v.Z) / (tanV * aspect)
	local ny = (v.Y / -v.Z) / tanV
	return 0.5 + 0.5 * nx, 0.5 - 0.5 * ny
end

local function inSafe(sx: number?, sy: number?): boolean
	return sx ~= nil and sy ~= nil and sx >= SAFE.x0 and sx <= SAFE.x1 and sy >= SAFE.y0 and sy <= SAFE.y1
end

local function isPartOrChild(hit: Instance, part: Instance): boolean
	return hit == part or hit:IsDescendantOf(part)
end

-- How much of `part` can a pointer actually touch? Casts a grid of rays through the part's on-screen box, exactly like the
-- player's pointer does, and counts the rays whose FIRST hit is the part. Returns hits out of the rays cast.
local function pointerHits(model: Model, cf: CFrame, aspect: number, part: BasePart): (number, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = false
	local half = part.Size / 2
	local lox, hix, loy, hiy = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, y = project(cf, aspect, (part.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
				if x and y then
					lox, hix, loy, hiy = math.min(lox, x), math.max(hix, x), math.min(loy, y), math.max(hiy, y)
				end
			end
		end
	end
	if lox == math.huge then
		return 0, 0
	end
	lox, hix, loy, hiy = math.max(lox, SAFE.x0), math.min(hix, SAFE.x1), math.max(loy, SAFE.y0), math.min(hiy, SAFE.y1)
	if hix <= lox or hiy <= loy then
		return 0, 0
	end
	local tanV = math.tan(math.rad(FOV) / 2)
	local tanH = tanV * aspect
	local hits, total, N = 0, 0, 6
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			local sx = lox + (hix - lox) * (i + 0.5) / N
			local sy = loy + (hiy - loy) * (j + 0.5) / N
			local dir = (cf.LookVector + cf.RightVector * ((sx - 0.5) * 2 * tanH) + cf.UpVector * ((0.5 - sy) * 2 * tanV)).Unit
			total += 1
			local hit = workspace:Raycast(cf.Position, dir * 200, params)
			if hit and isPartOrChild(hit.Instance, part) then
				hits += 1
			end
		end
	end
	return hits, total
end

-- how big the part looks: width and height of its screen box as a fraction of the screen
local function screenSize(cf: CFrame, aspect: number, part: BasePart): (number, number)
	local half = part.Size / 2
	local lox, hix, loy, hiy = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, y = project(cf, aspect, (part.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
				if x and y then
					lox, hix, loy, hiy = math.min(lox, x), math.max(hix, x), math.min(loy, y), math.max(hiy, y)
				end
			end
		end
	end
	if lox == math.huge then
		return 0, 0
	end
	return hix - lox, hiy - loy
end

-- true when a pointer can reach the part at all (a few of the grid rays land on it)
local function visibleFromCamera(model: Model, cf: CFrame, part: BasePart, aspect: number): boolean
	local hits = pointerHits(model, cf, aspect, part)
	return hits >= 2
end

local function decalFacing(part: BasePart, decalName: string, cf: CFrame): number?
	local decal = part:FindFirstChild(decalName)
	if decal and decal:IsA("Decal") then
		local normal = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(decal.Face))
		return normal:Dot((cf.Position - part.Position).Unit)
	end
	return nil
end

local function checkSpots(model: Model, folderName: string, decalName: string, cf: CFrame, aspect: number, issues: { string }, tag: string)
	local folder = model:FindFirstChild(folderName)
	if not folder then
		table.insert(issues, `{tag}: no {folderName} folder`)
		return
	end
	local n = 0
	for _, spot in folder:GetChildren() do
		if spot:IsA("BasePart") then
			n += 1
			local sx, sy = project(cf, aspect, spot.Position)
			if not inSafe(sx, sy) then
				table.insert(issues, `{tag}: {spot.Name} is off screen / under the UI ({if sx then string.format("%.2f,%.2f", sx, sy :: number) else "behind camera"})`)
			end
			if not visibleFromCamera(model, cf, spot, aspect) then
				table.insert(issues, `{tag}: {spot.Name} is hidden behind another part`)
			end
			local facing = decalFacing(spot, decalName, cf)
			if facing == nil then
				table.insert(issues, `{tag}: {spot.Name} has no {decalName} decal`)
			elseif facing < 0.1 then
				table.insert(issues, `{tag}: {spot.Name} faces away from the camera (dot {string.format("%.2f", facing)})`)
			end
		end
	end
	if n == 0 then
		table.insert(issues, `{tag}: {folderName} is empty`)
	end
end

local function checkPolish(model: Model, cf: CFrame, aspect: number, issues: { string }, tag: string)
	local folder = model:FindFirstChild("PolishSurfaces")
	if not folder then
		table.insert(issues, `{tag}: no PolishSurfaces folder`)
		return
	end
	local n, seen = 0, 0
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			n += 1
			if part.Transparency ~= 0 then
				table.insert(issues, `{tag}: polish surface {part.Name} has Transparency {part.Transparency} (shine cannot show)`)
			end
			local sx, sy = project(cf, aspect, part.Position)
			if inSafe(sx, sy) and visibleFromCamera(model, cf, part, aspect) then
				seen += 1
			else
				table.insert(issues, `{tag}: polish surface {part.Name} cannot be seen / reached from the camera`)
			end
		end
	end
	if n == 0 then
		table.insert(issues, `{tag}: PolishSurfaces is empty`)
	elseif seen == 0 then
		table.insert(issues, `{tag}: NO polish surface is reachable from the camera`)
	end
end

local function checkOverflow(model: Model, cf: CFrame, aspect: number, issues: { string }, tag: string)
	local worst = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Base" and p.Transparency < 0.95 then
			local half = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
						local x, y = project(cf, aspect, corner)
						if x == nil or y == nil then
							worst = math.max(worst, 1)
						else
							worst = math.max(worst, math.max(0 - x, x - 1, 0 - y, y - 1, 0))
						end
					end
				end
			end
		end
	end
	if worst > 0.01 then
		table.insert(issues, `{tag}: the item overflows the screen by {string.format("%.0f", worst * 100)}%`)
	end
end

-- ===== Bot: actually restores every item through the REAL minigames, with the pointer's real ray hits =====
-- (A real session showed the Lava Lamp's Replace step could not be finished: its bulb socket sat inside the glass, every tap
-- hit the glass first. Looking at the geometry was not enough, so this plays each step the way a player would.)
local SpotClear = require(script.Parent.Parent.Minigames.SpotClear)
local Scrape = require(script.Parent.Parent.Minigames.Scrape)
local Socket = require(script.Parent.Parent.Minigames.Socket)

-- the first pointer ray (of a grid over the part's screen box) whose FIRST hit is the part: what a player's tap would hit
local function findHit(model: Model, cf: CFrame, aspect: number, part: BasePart): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = false
	local half = part.Size / 2
	local lox, hix, loy, hiy = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, y = project(cf, aspect, (part.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
				if x and y then
					lox, hix, loy, hiy = math.min(lox, x), math.max(hix, x), math.min(loy, y), math.max(hiy, y)
				end
			end
		end
	end
	if lox == math.huge then
		return nil
	end
	lox, hix, loy, hiy = math.max(lox, SAFE.x0), math.min(hix, SAFE.x1), math.max(loy, SAFE.y0), math.min(hiy, SAFE.y1)
	if hix <= lox or hiy <= loy then
		return nil
	end
	local tanV = math.tan(math.rad(FOV) / 2)
	local tanH = tanV * aspect
	local best, bestScore = nil, -1
	for i = 0, 6 do
		for j = 0, 6 do
			local sx = lox + (hix - lox) * (i + 0.5) / 7
			local sy = loy + (hiy - loy) * (j + 0.5) / 7
			local dir = (cf.LookVector + cf.RightVector * ((sx - 0.5) * 2 * tanH) + cf.UpVector * ((0.5 - sy) * 2 * tanV)).Unit
			local hit = workspace:Raycast(cf.Position, dir * 200, params)
			if hit and isPartOrChild(hit.Instance, part) then
				local score = -((sx - (lox + hix) / 2) ^ 2 + (sy - (loy + hiy) / 2) ^ 2) -- the one nearest the middle of the part
				if score > bestScore then
					best, bestScore = hit, score
				end
			end
		end
	end
	return best
end

local function baseOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

-- Restores one item start to finish. Returns a list of problems (empty = every step could be completed).
local function playItem(id: string, def, source: Model): { string }
	local problems = {}
	local model = source:Clone()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
		end
	end
	model.Parent = workspace
	model:PivotTo(ORIGIN)
	local camera = workspace.CurrentCamera
	local aspect = 16 / 9
	local savedType, savedCF = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	for stepIndex, step in def.recipe do
		RestorationView.ApplyStepState(model, def.recipe, stepIndex)
		local cf = RestorationView.FitCamera(model, FLAT, FOV, aspect)
		camera.CFrame = cf
		local tag = `step {stepIndex} {step.type}`
		local done = false
		local function finished() done = true end
		if step.type == "Wipe" then
			local ok, g = pcall(SpotClear.new, model, { type = "Wipe", secondsPerSpot = 0.4 }, function() end, finished)
			if not ok then
				table.insert(problems, `{tag}: cannot start ({g})`)
			else
				for _, spot in model.DirtSpots:GetChildren() do
					local hit = if spot:IsA("BasePart") then findHit(model, cf, aspect, spot) else nil
					if hit == nil then
						table.insert(problems, `{tag}: a tap can never land on {spot.Name} (something is in front of it)`)
					else
						g:OnPointerDown(hit)
						for _ = 1, 60 do
							g:OnDrag(hit, Vector2.zero, 0.1)
						end
						g:OnPointerUp()
					end
				end
				if not done and #problems == 0 then
					table.insert(problems, `{tag}: all spots reached but the step never completed`)
				end
				g:Destroy()
			end
		elseif step.type == "Scrape" then
			local ok, g = pcall(Scrape.new, model, { type = "Scrape" }, function() end, finished)
			if not ok then
				table.insert(problems, `{tag}: cannot start ({g})`)
			else
				for _, spot in model.RustSpots:GetChildren() do
					local hit = if spot:IsA("BasePart") then findHit(model, cf, aspect, spot) else nil
					if hit == nil then
						table.insert(problems, `{tag}: a tap can never land on {spot.Name} (something is in front of it)`)
					else
						g:OnPointerDown(hit)
						for i = 1, 40 do
							g:OnDrag(hit, Vector2.new(if i % 2 == 0 then 30 else -30, 0), 0.016)
						end
						g:OnPointerUp()
					end
				end
				if not done and #problems == 0 then
					table.insert(problems, `{tag}: all spots reached but the step never completed`)
				end
				g:Destroy()
			end
		elseif step.type == "Polish" then
			local tuning = { requiredTravel = 1.0526, maxSampleTravel = 0.2, maxCreditPerSample = 0.05, minSampleTravel = 0.001 }
			local ok, g = pcall(Rub.new, model, { type = "Polish", movement = tuning }, function() end, finished)
			if not ok then
				table.insert(problems, `{tag}: cannot start ({g})`)
			else
				local reachedAny = false
				for part, state in g.surfaces do
					local hit = findHit(model, cf, aspect, part)
					if hit then
						reachedAny = true
						g:OnPointerDown(hit)
						for i = 1, 400 do
							g:OnDrag(hit, Vector2.new(if i % 2 == 0 then 60 else -60, 0), 0.016)
							if done then
								break
							end
						end
						g:OnPointerUp()
					end
				end
				if not reachedAny then
					table.insert(problems, `{tag}: no polish surface can be touched`)
				elseif not done then
					table.insert(problems, `{tag}: rubbed everything reachable but the polish never completed`)
				end
				g:Destroy()
			end
		elseif step.type == "Reassemble" or step.type == "Replace" then
			local ok, g = pcall(Socket.new, model, step, function() end, finished, { instant = true })
			if not ok then
				table.insert(problems, `{tag}: cannot start ({g})`)
			else
				for name, target in g.targets do
					local piece = model.LooseParts:FindFirstChild(name)
					local pieceBase = piece and baseOf(piece)
					local socketBase = baseOf(target.socket)
					local pieceHit = if pieceBase then findHit(model, cf, aspect, pieceBase) else nil
					local socketHit = if socketBase then findHit(model, cf, aspect, socketBase) else nil
					if pieceHit == nil then
						table.insert(problems, `{tag}: a tap can never land on the loose part {name}`)
					elseif socketHit == nil then
						table.insert(problems, `{tag}: a tap can never land on the spot for {name} (something is in front of it)`)
					else
						g:OnPointerDown(pieceHit)
						if step.type == "Replace" then
							g:OnPointerDown(socketHit)
						end
					end
				end
				if not done and #problems == 0 then
					table.insert(problems, `{tag}: parts tapped but the step never completed`)
				end
				g:Destroy()
			end
		end
		-- a failed step cannot be followed by the next one (its state would be wrong): stop at the first problem
		if #problems > 0 then
			break
		end
	end
	camera.CameraType = savedType
	camera.CFrame = savedCF
	model:Destroy()
	return problems
end

-- Plays every item (or opts.only) through its whole recipe. Returns { [itemId] = { problems } } and a summary.
function Sweep.Play(opts: { only: { string }? }?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Items")
	assert(models, "ReplicatedStorage.Assets.Items is missing")
	local ids = {}
	for id in Items do
		if not (opts and opts.only) or table.find(opts.only, id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	local report, failed, played = {}, 0, 0
	for _, id in ids do
		local def = Items[id]
		local source = models:FindFirstChild(def.model or id)
		if source and source:IsA("Model") then
			played += 1
			local problems = playItem(id, def, source)
			report[id] = problems
			if #problems > 0 then
				failed += 1
			end
		end
	end
	local lines = { `played {played} items through their whole recipe: {played - failed} finished, {failed} got stuck` }
	for _, id in ids do
		if report[id] and #report[id] > 0 then
			table.insert(lines, `[{id}]`)
			for _, p in report[id] do
				table.insert(lines, "  - " .. p)
			end
		end
	end
	return report, table.concat(lines, "\n")
end

-- Runs everything. opts.only = { "LavaLamp", ... } limits the items. Returns { [itemId] = { issues... } } and a summary string.
function Sweep.Run(opts: { only: { string }? }?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Items")
	assert(models, "ReplicatedStorage.Assets.Items is missing")
	local only
	if opts and opts.only then
		only = {}
		for _, id in opts.only do
			only[id] = true
		end
	end
	local ids = {}
	for id in Items do
		if not only or only[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	local folder = Instance.new("Folder")
	folder.Name = "RestorationSweep"
	folder.Parent = workspace
	local report, checked, withIssues, missing = {}, 0, 0, {}
	for _, id in ids do
		local def = Items[id]
		local source = models:FindFirstChild(def.model or id)
		if not (source and source:IsA("Model")) then
			table.insert(missing, id)
			continue
		end
		checked += 1
		local issues = {}
		local model = source:Clone()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		model.Parent = folder
		model:PivotTo(ORIGIN)
		if not (model.PrimaryPart and model.PrimaryPart.Name == "Base") then
			table.insert(issues, "contract: PrimaryPart must be Base")
		end
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and not p.Anchored then
				table.insert(issues, `contract: {p.Name} is not anchored`)
				break
			end
		end
		for stepIndex, step in def.recipe do
			RestorationView.ApplyStepState(model, def.recipe, stepIndex)
			for _, aspectInfo in ASPECTS do
				local label, aspect = aspectInfo[1], aspectInfo[2]
				local tag = `step {stepIndex} {step.type} @ {label}`
				local cf = RestorationView.FitCamera(model, FLAT, FOV, aspect)
				checkOverflow(model, cf, aspect, issues, tag)
				if step.type == "Wipe" then
					checkSpots(model, "DirtSpots", "Dirt", cf, aspect, issues, tag)
				elseif step.type == "Scrape" then
					checkSpots(model, "RustSpots", "Rust", cf, aspect, issues, tag)
				elseif step.type == "Polish" then
					checkPolish(model, cf, aspect, issues, tag)
				elseif step.type == "Reassemble" or step.type == "Replace" then
					local loose = model:FindFirstChild("LooseParts")
					local sockets = model:FindFirstChild("Sockets")
					if not loose or #loose:GetChildren() == 0 then
						table.insert(issues, `{tag}: no LooseParts`)
					end
					for _, socket in if sockets then sockets:GetChildren() else {} do
						local wanted = false
						for _, prefix in step.parts or { "" } do
							if string.sub(socket.Name, 1, #prefix) == prefix then
								wanted = true
							end
						end
						if wanted and socket:IsA("BasePart") then
							local sw, sh = screenSize(cf, aspect, socket)
							if pointerHits(model, cf, aspect, socket) < 2 then
								table.insert(issues, `{tag}: the spot for {socket.Name} is hidden / cannot be tapped`)
							elseif math.max(sw, sh) < 0.045 then
								table.insert(issues, `{tag}: the spot for {socket.Name} is tiny on screen ({string.format("%.1f", math.max(sw, sh) * 100)}%)`)
							end
							local piece = loose and loose:FindFirstChild(socket.Name)
							local base = piece and (if piece:IsA("BasePart") then piece else piece:FindFirstChildWhichIsA("BasePart", true))
							if base then
								local pw, ph = screenSize(cf, aspect, base)
								if pointerHits(model, cf, aspect, base) < 2 then
									table.insert(issues, `{tag}: the loose part {socket.Name} is hidden / cannot be tapped`)
								elseif math.max(pw, ph) < 0.045 then
									table.insert(issues, `{tag}: the loose part {socket.Name} is tiny on screen ({string.format("%.1f", math.max(pw, ph) * 100)}%)`)
								end
							end
						end
					end
				end
			end
			-- can the minigame even start on this model?
			if step.type == "Wipe" then
				local ok, err = pcall(function()
					local g = SpotClear.new(model, { type = "Wipe", secondsPerSpot = 1 }, function() end, function() end)
					g:Destroy()
				end)
				if not ok then
					table.insert(issues, `step {stepIndex} Wipe cannot start: {err}`)
				end
			elseif step.type == "Polish" then
				local ok, err = pcall(function()
					local g = Rub.new(model, { type = "Polish", movement = { requiredTravel = 1.5, maxSampleTravel = 0.2, maxCreditPerSample = 0.05, minSampleTravel = 0.001 } }, function() end, function() end)
					g:Destroy()
				end)
				if not ok then
					table.insert(issues, `step {stepIndex} Polish cannot start: {err}`)
				end
			end
		end
		-- de-duplicate the desktop/phone repeats
		local seen, unique = {}, {}
		for _, line in issues do
			if not seen[line] then
				seen[line] = true
				table.insert(unique, line)
			end
		end
		report[id] = unique
		if #unique > 0 then
			withIssues += 1
		end
		model:Destroy()
	end
	folder:Destroy()

	local lines = { `checked {checked} items, {withIssues} with issues` .. (if #missing > 0 then `; no model yet: {table.concat(missing, ", ")}` else "") }
	for _, id in ids do
		local issues = report[id]
		if issues and #issues > 0 then
			table.insert(lines, `[{id}]`)
			for _, line in issues do
				table.insert(lines, "  - " .. line)
			end
		end
	end
	return report, table.concat(lines, "\n")
end

return Sweep
