-- LayoutCheck.luau (ServerScriptService.Server.Tests.LayoutCheck)
-- Purpose: tests the edit-mode rules the server uses for RequestSaveLayout: LayoutService.Clean (what a client may send) and
-- LayoutService.Validate (bounds, grid, keep-clear boxes, overlap, locked / busy pieces, floors). Pure: made-up plot data, no
-- player, no real profile, no Studio objects touched.
-- Owner: Dev 1 (Ace). Depends on: Services.LayoutService, Shared.Layout.
-- Run in the Studio command bar while Playing (Server): require(game.ServerScriptService.Server.Tests.LayoutCheck).run()
-- Also part of DevTools testAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LayoutCheck = {}

function LayoutCheck.run()
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

	local Layout = require(ReplicatedStorage.Shared.Layout)
	local Service = require(ServerScriptService.Server.Services.LayoutService)

	-- ===== Clean: what a client may send =====
	check("clean: not a table is refused", select(2, Service.Clean("x")) == "badInput")
	check("clean: NaN refused", select(2, Service.Clean({ A = { x = 0 / 0, z = 0, rot = 0, floor = "Ground" } })) == "badInput")
	check("clean: huge number refused", select(2, Service.Clean({ A = { x = 1e9, z = 0, rot = 0, floor = "Ground" } })) == "badInput")
	check("clean: unknown floor refused", select(2, Service.Clean({ A = { x = 0, z = 0, rot = 0, floor = "Roof" } })) == "badFloor")
	check("clean: rotation 45 refused", select(2, Service.Clean({ A = { x = 0, z = 0, rot = 45, floor = "Ground" } })) == "badRotation")
	check("clean: a number key refused", select(2, Service.Clean({ [1] = { x = 0, z = 0, rot = 0, floor = "Ground" } })) == "badInput")
	check("clean: a non-table entry refused", select(2, Service.Clean({ A = 5 })) == "badInput")
	local many = {}
	for i = 1, Layout.MAX_PIECES + 1 do
		many["P" .. i] = { x = 0, z = 0, rot = 0, floor = "Ground" }
	end
	check("clean: more pieces than the limit refused", select(2, Service.Clean(many)) == "badInput")
	local cleaned = Service.Clean({ A = { x = 1, z = 2, rot = 90, floor = "Ground", evil = "x" } })
	check("clean: extra fields are dropped", cleaned ~= nil and cleaned.A.evil == nil and cleaned.A.rot == 90)
	check("clean: an empty layout is fine (= reset)", Service.Clean({}) ~= nil)

	-- ===== Validate: a made-up plot =====
	local function place(x: number, z: number, rot: number?, floor: string?)
		return { x = x, z = z, rot = rot or 0, floor = floor or "Ground" }
	end
	local areas = {
		{ name = "Zone_Ground", kind = "Zone", floor = "Ground", x0 = -26.6, x1 = 26.6, z0 = -26.6, z1 = 26.6 },
		{ name = "Zone_Upstairs", kind = "Zone", floor = "Upstairs", requires = "Showroom", x0 = -26.6, x1 = 26.6, z0 = -26.6, z1 = 26.6 },
		{ name = "KeepClear_Door", kind = "KeepClear", floor = "Ground", x0 = -12, x1 = -8, z0 = -15, z1 = -10 },
	}
	local function ctxWith(overrides: any?)
		local ctx = {
			areas = areas, owned = {}, current = {},
			pieces = {
				ShelfA = { sizeX = 4.2, sizeZ = 11.2, locked = false, busy = false, default = place(-24.5, -16.8) },
				ShelfB = { sizeX = 4.2, sizeZ = 11.2, locked = false, busy = false, default = place(-24.5, -5.6) },
				Exhibit9 = { sizeX = 2.8, sizeZ = 2.8, locked = true, busy = false, default = place(0, 20) },
			},
		}
		for k, v in overrides or {} do
			ctx[k] = v
		end
		return ctx
	end
	local function validate(layout: any, ctx: any?)
		return Service.Validate(layout, ctx or ctxWith())
	end

	check("validate: an empty layout is fine", (validate({})))
	check("validate: a free spot on the grid is fine", (validate({ ShelfA = place(-10.5, -21 + 2.8 * 7) })))
	local _, offReason = validate({ ShelfA = place(-10.4, -4.2) })
	check("validate: off the grid is refused", offReason == "offGrid", offReason)
	local _, outReason = validate({ ShelfA = place(-41.3, -21) })
	check("validate: outside the shop is refused", outReason == "outside", outReason)
	local _, clearReason, clearName = validate({ ShelfA = place(-10.5, -15.4) })
	check("validate: over a keep-clear box is refused", clearReason == "keepClear" and clearName == "KeepClear_Door", `{clearReason} {clearName}`)
	local _, overlapReason, overlapId = validate({ ShelfA = place(-24.5, -15.4) })
	check("validate: bumping into another piece is refused", overlapReason == "overlap" and overlapId == "ShelfB", `{overlapReason} {overlapId}`)
	local ok2 = validate({ ShelfA = place(-7, -24.5, 90) })
	check("validate: a quarter turn along the wall is fine", ok2)
	local _, rotReason = validate({ ShelfA = place(-7, -24.5, 45) })
	check("validate: a 45 degree turn is refused", rotReason == "badRotation", rotReason)
	local _, pieceReason = validate({ Nope = place(0, 0) })
	check("validate: an unknown piece is refused", pieceReason == "badPiece", pieceReason)
	local _, lockedReason = validate({ Exhibit9 = place(0, 0) })
	check("validate: a locked pedestal is refused", lockedReason == "locked", lockedReason)
	check("validate: a piece sent at its default spot is harmless", (validate({ ShelfA = place(-24.5, -16.8) })))
	local _, upReason = validate({ ShelfA = place(-10.5, -15.4, 0, "Upstairs") })
	check("validate: upstairs without the Showroom is refused", upReason == "outside", upReason)
	check("validate: upstairs with the Showroom is fine", (validate({ ShelfA = place(-10.5, -15.4, 0, "Upstairs") }, ctxWith({ owned = { Showroom = true } }))))

	-- two moved pieces must not land on each other
	local _, twoReason = validate({ ShelfA = place(-10.5, -21 + 2.8 * 7), ShelfB = place(-10.5, -21 + 2.8 * 8) })
	check("validate: two moved pieces on top of each other are refused", twoReason == "overlap", twoReason)
	check("validate: two moved pieces side by side are fine", (validate({ ShelfA = place(-10.5, -21 + 2.8 * 7), ShelfB = place(-10.5 + 2.8 * 2, -21 + 2.8 * 7) })))

	-- a shelf a customer is buying from stays where it is
	local busy = ctxWith()
	busy.pieces.ShelfA.busy = true
	local _, busyReason = validate({ ShelfA = place(-10.5, -21 + 2.8 * 7) }, busy)
	check("validate: moving a busy shelf is refused", busyReason == "reserved", busyReason)
	check("validate: leaving a busy shelf alone is fine", (validate({}, busy)))
	busy.current = { ShelfA = place(-10.5, -21 + 2.8 * 7) }
	local _, backReason = validate({}, busy)
	check("validate: putting a busy shelf back to default is refused", backReason == "reserved", backReason)
	check("validate: a busy shelf keeping its saved spot is fine", (validate({ ShelfA = place(-10.5, -21 + 2.8 * 7) }, busy)))

	for _, line in lines do
		if string.sub(line, 1, 4) == "FAIL" then
			warn("[LayoutCheck]", line)
		end
	end
	print(`[LayoutCheck] {passCount} passed, {failCount} failed`)
	return lines, passCount, failCount
end

return LayoutCheck
