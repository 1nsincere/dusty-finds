# Shop Edit Mode: one-page plan (draft for Sean + Ace)

> Status: **agreed by Sean + Ace (2026-11-24), nothing built yet.** Build in the order of "Build steps". Decor shop
> (buying new furniture) comes **after** this, as phase B.

## Goal
In their own shop, a player can **move and rotate their display shelves and exhibit pedestals** on a grid, see it
saved, and visitors see the same layout. Customers still find every shelf.

## What moves, what stays

| Moves (phase A) | Stays fixed |
|---|---|
| Shelf units `Shelf1..4` (each carries its 3 display slots) | Counter + customer queue, door, front windows |
| Exhibit pedestals `Exhibit1..10` (with their bases/arches if any) | Workbenches, storage room, stairs (x 20..26.6) |
| (phase B) decor bought in the decor shop | Ace's Facade art, walls, Back Room shell |

Pieces are only placed inside **zones**: ground floor, Back Room (if owned), upstairs gallery (if Showroom owned).
**Keep-clear boxes** (no piece may overlap): door to counter walkway, counter + queue line, stairs, storage room door,
bench + its camera spot, Back Room opening. Zones and boxes are Studio parts in each plot (`PlotN.EditZones/*`), so they
are data, not code.

## Data (needs Ace: data template)
- New field `layout = {}` in the player data: `[pieceId] = { x, z, rot, floor }` in **plot-local studs** (same frame as
  everything else), `rot` = 0/90/180/270, `floor` = "Ground" | "Upstairs". Missing piece = default spot (today's layout).
- `version` 1 -> 2; old saves get an empty layout = nothing changes for them. Items keep their `slot` number, so an
  item on Slot5 stays on Slot5 wherever its shelf goes.

## Server: `LayoutService` (new, Ace)
- `RequestSaveLayout(layout)` (sent on **Done**): owner only, in their own plot, size-limited table, types checked,
  rate limited; every piece exists and is unlocked (slot enabled), grid-snapped (2.8), rot in {0, 90, 180, 270},
  inside a zone of its floor (that floor/room owned), no overlap with other pieces or keep-clear boxes; a shelf holding
  a reserved item must not move. All-or-nothing: one bad piece = nothing saved, the client gets the reason.
- `RequestResetLayout()`: back to the default layout.
- Applies the saved layout when a plot is assigned (after `PlotService.RefreshSlots`). Parts move on the server, so
  visitors see it; `DisplayController` already redraws an item when its slot moves (added for the gallery).
- Remotes declared in `Shared/Remotes.luau` + `docs/03 §6`.

## Customers (needs Ace: `CustomerNpcService`)
Today they walk a straight aisle line beside the left-wall shelves (`Browse1..3`) and stand level with the slot. With
movable shelves: each shelf model gets a **`StandSpot`** in front of it (moves with the shelf); customers walk Door ->
1-2 random stand spots -> the chosen shelf's stand spot -> queue, using **PathfindingService** with the old fade-out
as a fallback if no path exists (never stuck). Shelves can be in the Back Room or upstairs, so paths include the
stairs; the walk timing (`AutoCheckoutSeconds`) may need a look.

## Client: `EditModeController` (new, Sean)
"Edit shop" button (own shop only, not during a till / restoration). Camera goes high above the floor you're on, with
a Floor switch (Ground / Upstairs) when the Showroom is owned; tap a piece to pick it up; drag on the 2.8-stud grid
(mouse or one finger); Rotate (90°) / Done / Cancel / Reset buttons big enough for phones; ghost turns green/red from
the same rules the server uses (`Shared/Layout.luau`, so they can't disagree). Nothing is sent until **Done**; leaving
the plot or Cancel throws the changes away. A shelf with a reserved item shows a lock and can't be picked up.

## Studio contract (step 2, done 2026-11-24 in all 6 plots)
- **Pieces:** `Shelves/Shelf1..4` have `PieceId = "ShelfN"`, `PieceKind = "Shelf"`; each `DisplaySlots/SlotN` has
  `Piece = "ShelfN"` (Shelf1 = slots 1-3, Shelf2 = 4-6, Shelf3 = 7-9, Shelf4 = 10-12): move a shelf = move its slots by
  the same transform. `ExhibitSlots/Exhibit1..10` have `PieceId = "ExhibitN"`, `PieceKind = "Pedestal"`. Shelves stay
  as they are (one Part each, 4.2 x 4.2 x 11.2); nothing else was restructured, so no code broke.
- **Customer spot:** each shelf has an Attachment `StandSpot` 6.3 studs in front of it (where customers stand today),
  facing the shelf; it moves with the shelf.
- **Zones:** `PlotN.EditZones` (invisible, no collision, not queryable): `Zone_Ground` (x/z -26.6..26.6, 19 x 19
  cells of 2.8), `Zone_BackRoom` (`Requires = "BackRoom"`, z 28..60.2), `Zone_Upstairs` (`Requires = "Showroom"`, top
  y 18.5), and `KeepClear_*` boxes (Entrance, DeliverySpot, CounterAndQueue, StorageRoom, StorageDoor, Stairs,
  BackRoomWalkway, Bench2, StairHole, StairLanding, JarCabinet, FountainSpot, Lamp1..4). Every part has
  `Kind` (Zone / KeepClear), `Floor` (Ground / Upstairs) and, if it depends on a room, `Requires`. Boxes are
  axis-aligned in plot-local space, so rules can read them as plain x/z ranges (`Floor.CFrame:ToObjectSpace`).

## Build steps (each one testable alone)
1. **Ace** — data `layout` + version 2 migration; `Shared/Layout.luau` (grid, zone + overlap rules, pure, testable).
2. **Sean** — Studio: shelves as movable pieces with `StandSpot`; `EditZones` + keep-clear parts in all 6 plots.
   **Done 2026-11-24** (see "Studio contract").
3. **Ace** — `LayoutService` + remotes + `LayoutCheck` tests (bounds, overlap, keep-clear, locked piece, bad input).
4. **Ace** — customers: stand spots + pathfinding (+ `CustomerCheck`).
5. **Sean** — `EditModeController` UI, mouse + touch. **Built 2026-11-24** (with a first `Shared/Layout.luau` for Ace to
   review): Edit button in the HUD drawer; top-down view of the floor you're on (roof, upper storey and ceiling art
   hidden locally, a work light); tap / drag a piece (snaps to 2.8), Rotate, Ground/Upstairs (a selected piece comes
   along), Reset, Cancel, Done; red keep-clear plates, green/red highlights, hint names the problem; a shelf's slots
   and a pedestal's base/rim/plaque (attribute `Piece`) move with it; your character is frozen and the HUD hidden.
   Done sends `RequestSaveLayout(layout)` if that remote exists (only moved pieces: `[pieceId] = {x, z, rot, floor}`),
   otherwise it only checks the layout and puts everything back. Not yet: the reserved-shelf lock (needs the server to
   say which shelf is reserved), a phone check.
6. **Both** — Play, 2 players (visitor sees the layout), phone, rejoin keeps the layout, reset works.

## Decisions (Sean + Ace, 2026-11-24)
1. **Grid: 2.8 studs** (easier on phones).
2. **Shelves and pedestals can go anywhere in the zones: ground floor, Back Room, upstairs.** So customers must be able
   to walk to a shelf in the Back Room or upstairs (pathfinding up the stairs) — more work in step 4; the queue still
   ends at the downstairs counter.
3. **Reserved items:** customers reserve the item they pick (owner's "Take back" is refused meanwhile). Suggested: a
   shelf holding a reserved item can't be moved for those few seconds ("A customer is buying from this shelf"). Simple
   and safe; letting the customer follow a moved shelf can come later.
4. **Save only on Done** (one request with the whole layout, one validation pass, one save). Cancel = nothing changes.
5. **Rotation: 4 directions (90°)** for everything in phase A. Later option: 8 directions (45°) for pedestals only
   (treated as circles, so overlap checks stay simple).

Because of (4), the remote is one `RequestSaveLayout(layout)` (whole layout, validated piece by piece, all-or-nothing)
instead of one request per piece.

## Risks
Customers stuck behind furniture (pathfinding + fallback), exploited placement (server checks everything, shared rules),
blocked door / stairs (keep-clear boxes), save migration (version bump, empty layout = default).
