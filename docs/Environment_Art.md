# Environment art (Studio only, not in Git)

Built by Ace with Claude Code, place v65 (restore point before it: **v63**). Style: cozy vintage antique street at golden hour.
The art lives in Team Create, not Git. This file is the map so nobody breaks it.

## Rules (so the code keeps working)
- Gameplay parts keep their names, sizes and positions: `Floor, Walls, Counter, Sign, Spawn, DisplaySlots, ExhibitSlots, Benches, DecorSlots,
  CustomerPath, DeliveryPoint, SupplyBoard, Shelves`. The pass only changed their **Color / Material** and added new objects.
- New objects are non-colliding unless they are pillars, benches, trees or planters. No facade part collides, so the door and customer
  path stay clear (checked: raycasts from the door and every `CustomerPath` point).
- Everything new is under `Workspace.Environment` or `Workspace.Plots.PlotN.Facade`. Removing the whole pass = delete those folders
  (then recolor the gameplay parts, or restore place v63).

## What exists
| Where | What |
|---|---|
| `Lighting` | golden-hour clock 17.2, warm ambient, Atmosphere haze, Bloom, SunRays, `WarmGrade` ColorCorrection (depth of field off) |
| `Workspace.Baseplate / Street / SpawnLocation` | recolored: grass, cobblestone road, spawn decal hidden |
| `Environment.StreetDetail` | dashed centre line, curbs, north and south sidewalks |
| `Environment.Ground` | south lawn strip |
| `Environment.Props` | LampPost (warm point lights), Bench, Planter (flowers) |
| `Environment.Trees` | trees on the south lawn and behind the shops |
| `Environment.Backdrop` | ring of distant hills, a row of town buildings behind the plots (lit windows) |
| `Environment.WelcomeArch` | brick arch over the spawn on the street with a "DUSTY FINDS" sign (SurfaceGui on both sides) |
| `Plots.PlotN.Facade` (N = 1-6) | brick base, cornice, door frame, striped awning, windows with flower boxes, wall lanterns, chimney, front pediment, interior string lights and baseboards. Plot 1 is the template; 2-6 are copies recolored (wall, brick, awning, trim) |
| Interior restyle (all plots) | plaster walls, wood floor, wooden shelves/counter/bench, marble exhibit pedestals, slate supply board, fabric rug on `Spawn`, cream shelf pads |

## Known gaps / next ideas
- The 40 stud gap between Plot 3 and Plot 4 (x -10..10) is bare lawn: good place for a fountain / town square.
- No shop expansions (Back Room, Showroom) exist yet; they need models that match this style.
- `For Sale` sign is Sean's `Sign.SurfaceGui`: untouched.
- Environment sound (street ambience, shop bell) not added; the world has no audio yet.
- Backdrop buildings are simple boxes; hills are spheres. Good enough from the street, replace with meshes later if needed.

---

# Environment overhaul (market square) - progress log
Restore point: **place v66** ("Before environment overhaul", saved by Claude Code at Ace's go). Older: v63 (before the first art pass), v65 (first art pass).
Direction: market square with a workbench theme (kept: map ends at a giant workbench, horizon props instead of boxes/hills).
Palette rule: UiTheme hues (Teal 0E7C7B, Coral F2784B, Cream FFF8EE, Ink 1F2D3A, Golden FFD43B, rarity Uncommon green / Rare blue muted) + warm wood, brick red, greige and stone neutrals. Darker/lighter shades of those hues are allowed.

## Phase 1 - lighting fix and palette cleanup (done)
- Lighting: Brightness 2.4 -> 1.9, Exposure -0.1, Bloom 0.45/28/thr 1.1 -> 0.12/18/thr 2.6, SunRays 0.18 -> 0.06, grade contrast 0.12 -> 0.05, saturation 0.18 -> 0.08, Atmosphere haze 1.6 -> 0.9. Lamps stay shadowless (only the sun casts shadows).
- Palette: one brick red; greige/cream/stone walls; one accent per shop (P1 teal, P2 coral, P3 golden, P4 ink, P5 green, P6 blue) on awning, door mat and Spawn rug; flowers only coral/cream/golden/teal; trees two muted greens (no orange canopies); lawn a muted green.
- Added parts: 0. Total parts in Workspace: 1284 (Environment 531, Facades 444).
- Checks: Play boot 14/14 services, 10/10 controllers, no errors; PlotCheck 28/28; CustomerCheck 51/51.
- Not verified by me: lowest-graphics and phone-emulator screenshots (cannot switch those from here); pixel values (judged by eye: no wall or sign is pure white in the street and plot views).

## Phases 2-8 (done, saved as place v70)
**New layout (market square).** Plots 1-3 stay on the north side (z centre 0, front at z -20). Plots 4-6 were moved with `PivotTo` to the south side (centre z -104, rotated 180 degrees, so their fronts face the square at z -84). The cobbled square is x -215..45, z -84..-20 (64 deep). Door x positions: -150, -90, -30 on both sides. Because each plot moved as one model, every child part kept its position relative to the plot.

| What | Where |
|---|---|
| Shop exteriors, 6 different rooflines | `Plots.PlotN.Facade` with groups `Front`, `Upper`, `Roof`, `Interior`. P1 gable (teal), P2 flat+cornice (coral), P3 stepped parapet (golden), P4 mansard (ink), P5 hipped (green), P6 gambrel (blue). Two storeys: the ground floor is the original 12-stud walls, the upper floor (9 studs) and roof are new |
| Big fascia sign per shop | `Facade.Front.FasciaSign` -> SurfaceGui -> TextLabel `OwnerName`. `PlotService.setSign` now also fills these labels (Dev 1 file, 8 lines), so the name shows on both signs. Sean's `Sign` + `Sign.SurfaceGui.OwnerName` are untouched (only recoloured to wood) |
| Filler fronts (cafe, bookshop, alley with crates) | `Environment.Fillers`: 5 on each side, solid, non-playable, no lawn gaps |
| Paving: border band, brick inlay, central medallion, worn door paths, raised kerbs | `Environment.Paving` + `workspace.Street` (resized to 260x1x64) |
| Props (one prototype per prop, copies of it) | `Environment.Props` (lamp, bench, planter) and `Environment.Trees`; prototypes in `ServerStorage.EnvPrototypes` (inert) |
| Landmarks | `Environment.Landmarks`: WelcomeArch (west end, over the spawn road), ClockTower (centre, x -90 z -52), Depot + delivery truck (east end) |
| Workbench | `workspace.Baseplate` is now the bench top (470x14x360, top at y 0); `Environment.Ground.CuttingMat` is the green mat the town sits on; `Environment.Horizon`: apron, legs, lip, invisible edge walls, and the giant props (desk lamp, 2 book stacks, ruler, screw jar, pencil, varnish tin) |
| Spawn | `workspace.SpawnLocation` moved to x -207 z -52 (west of the arch), decal hidden |

**Roof hiding (phase 8).** New client controller `src/Client/Controllers/RoofController.luau`, registered with ONE line in `Main.local.luau` (`"RoofController"` at the end of ORDER). It fades the `Facade.Roof` and `Facade.Upper` parts of the shop the local player stands in (inside the 40x40 footprint, with a doorway margin), using `LocalTransparencyModifier`, so nothing replicates and the real Transparency never changes.

**Honest limits**
- Display windows are overlays on the existing solid wall (`FrontWallL/R` are protected, so I could not cut holes): they look like windows from outside but you cannot see the interior through them. The door gap is real.
- Hero custom-texture materials: none used (all built-in materials).
- Trees are cubes at angles (faceted); from close up they look blocky rather than organic. Fine for the diorama look, replace with proper meshes later if wanted.
- The workbench look depends on fog/haze below the bench: the void beyond the edge is the Atmosphere colour.
- No Creator Store assets were inserted.
- The helper module that builds a shop exterior (`B.facade(plot, style)`) is kept in `ServerStorage._EnvBuilder` (Studio only, NOT in Git, inert) so a shop can be rebuilt or restyled; prop prototypes are in `ServerStorage.EnvPrototypes`. Delete both once the art is final.

## Numbers and checks after phases 2-8
- Parts in Workspace: 2318 (Environment 1252, Facades 780; before the overhaul 1284). All anchored, 0 scripts in Workspace, 42 PointLights (0 cast shadows), 165 Neon parts.
- Play: boot 14/14 services (CustomerNpcService now exists in the place) and no errors; PlotCheck 28/28; CustomerCheck 51/51.
- Moved shops: a Kid NPC walked Door -> Browse1 -> CounterSpot -> Exit in Plot1, Plot4, Plot5 and Plot6 (all reached); every shop's `Spawn` is inside its footprint at local (0, 1, -14).
- Roof hiding tested: player inside Plot1 hides 74/74 of its roof+upper parts and none elsewhere; inside the rotated Plot4 hides 67/67; in the square 0/420.
- NOT verified: lowest graphics level and the phone emulator (cannot be switched from here). For a cheap phone the likely costs are the 42 point lights and 165 neon parts; if it stutters, remove the interior string-bulb lights (`Facade.Interior.Bulb` PointLights) first.
- NOT verified: the real client roof script ran from a temporary copy because Script Sync had not imported the new `RoofController.luau` / the `Main.local.luau` line yet (the code is identical). After the next Studio sync, boot should print `10 -> 11 controllers` and `[RoofController] Start: 6 plots tracked`.

## Map expansion: three streets (supersedes the single square layout above)
| Street | z centre | North shop (faces -Z, door x) | South shop (rotated 180, door x) | End landmark |
|---|---|---|---|---|
| Market Street | -52 | Plot1 (x -150, z 0) | Plot4 (x -150, z -104) | Clock tower (x -90), Depot + truck at the east end, welcome arch |
| Antique Row | 158 | Plot2 (x -80, z 210) | Plot5 (x -80, z 106) | Fountain (x -90) + its own arch |
| Workshop Lane | -262 | Plot3 (x -20, z -210) | Plot6 (x -20, z -314) | Market stalls (x -90) + its own arch |

- **Avenue:** x -245..-215, z -294..190, joins the three street entrances; `SpawnLocation` at (-230, 1.5, -52).
- **Streets** are 260 x 64 (x -215..45); each has paving border, brick inlay, medallion, worn door paths, kerbs, lamps, benches, planters and generated filler fronts (cafe, bookshop, antiques, tools, bakery, alleys). 26 fillers in total.
- **Parks:** a 66-stud block of trees between streets (z 20..86 and z -190..-124).
- **Workbench:** x -330..170, z -400..300 (`workspace.Baseplate` is the bench top, `Environment.Ground.CuttingMat` the mat). Props: desk lamp NE, book stacks NW/S/E, ruler S edge, screw jar SE, pencil W, varnish tin E.
- **Performance:** about 2,950 parts in Workspace, 70 point lights (21 lamp lights switched off, 49 enabled). StreamingEnabled is ON (target radius 1024 covers the map). Not tested on a phone: see "NOT verified" above.
- **Expansion rooms** (Back Room, Showroom): `ServerStorage.Expansions`, attached behind each shop (z 20..44 in plot-local axes). See docs/03 §2 and PlotService.applyExpansions. Annexes are open-topped (no roof): the main shop roof only covers the original 40 x 40 footprint.

---

# RESTYLE: "Sunny Workshop Town" (appeals to all ages)
**Restore point before the restyle: place v76** (three-street town, saved by Claude Code at Ace's go). After phase 1: **v77**.
Palette (only these): Sky 6EC6FF, cloud FFFFFF, grass 8BD96B, leaf 4FA84A, cream FFF4DE (walls), honey wood E8B873, teal 2EC4B6, coral FF7A6B, yellow FFD04D, purple 9B8CFF, ink 2B2D42 (outlines, frames, sign text only). Each shop: ONE accent, cream walls, honey trim. No dark brown, dark slate, grey-brown or beige as a main colour.

## Phase 1 - sky, light, ground and horizon colour (done)
- **Light:** ClockTime 17 -> 11, Brightness 1.9 -> 2.1, exposure -0.15, light blue-grey ambient (no brown tint). Atmosphere: Density 0.28 -> 0.10, Haze 0.9 -> 0.1, Glare 0, colours light sky blue (was orange). Bloom 0.12/thr 2.6 -> 0.15/thr 2.4, SunRays 0.04. Colour grade: neutral white tint, +12% saturation. Sky: moon and stars off. New `Terrain.Clouds` (Cover 0.45, Density 0.45, white).
- **Ground:** `Baseplate` (bench top) light honey wood; `CuttingMat` grass green with lighter grid lines; streets/avenue/spawn pad cobble recoloured light cream; borders honey, inlays and medallion ring coral, inner medallion yellow; kerbs and door paths light honey.
- **Horizon:** bench aprons, legs and lip light honey (no dark brown). Props recoloured and made less metallic: desk lamp (yellow base, teal shade, coral joints, ink arms), book stacks (teal/coral/yellow/purple with cream pages), ruler yellow with ink ticks, screw jar is now a jar of colourful buttons (coral lid), pencil (yellow shaft, coral eraser, teal ferrule), varnish tin is now a teal paint tin with a yellow label.
- **Parts:** 2945 -> 2945 (+0). Enabled point lights 49 -> 49 (only the sun casts shadows).
- **Checks:** boot 14/14 services, 10 controllers, no errors; PlotCheck 43/43; CustomerCheck 51/51. No `src/` code hardcodes world colours or lighting (grep).
- **Still old-looking on purpose (later phases):** dark roofs, brick bases, dark wood trim and dark sign boards (phases 2-3), dark blocky trees, lamps, benches (phase 4), clock tower and depot (phase 7).
- **NOT verified by me:** lowest graphics level and the phone emulator (cannot be switched from here). Please check: the clouds, the soft blue sky and the pale cobbles should survive low quality; the grass may look flatter.

## Restyle phases 2-7 (done, place v79; v77 = after phase 1, v76 = before the restyle)
Done in one pass at Ace's go ("you have all my approvals"), so phases were not shown one by one.
- **Phase 2-3 (shops and fillers):** every shop is cream (SmoothPlastic) with honey wood trim; roofs recoloured to ONE accent per shop: P1 teal, P2 coral, P3 yellow, P4 purple, P5 leaf green, P6 sky blue (roof, shutters, door mat, fascia trim, `Spawn` pad). Brick, dark wood and slate are gone (brick -> honey, slate -> ink only for lamp posts/frames). Sign boards are cream with ink text (`FasciaSign`, filler `SignBoard`, `DepotSign`, arch boards, and Sean's `Sign`). Shop windows are lit warm cream. Fillers: roof in the colour of their door.
- **Shapes:** NEW scalloped/rolled awnings over both shop windows (5 stripes + a rolled front edge each), round bulb lamp heads, ball-shaped planter bushes. Roof SHAPES were not changed (gable, flat, stepped, mansard, hipped, gambrel): only colour. Round windows exist only on the gable shop (attic).
- **Interiors (gameplay parts, colour/material only):** `Floor` light honey wood, `Walls` cream SmoothPlastic, `Shelves` pale honey, `Counter`/`Bench1` honey, `DisplaySlots` pads cream (items sit on cream: rarity colours read well), `SupplyBoard` ink, `Sign` cream with ink text.
- **Phase 4 (streets):** paving recoloured light (done in phase 1), crates/barrels honey/yellow/coral, trees REPLACED: thick two-piece trunk + four soft round canopy balls in two greens, about 1 in 6 in pink blossom and 1 in 11 yellow (6 parts instead of 8). Hills: 20 pale green/blue balls beyond the bench (`Environment.Hills`).
- **Phase 5 (horizon):** colours from phase 1; props kept (desk lamp, books, ruler, button jar, pencil, paint tin). Pale hills beyond the bench replace the void; Terrain Clouds already on.
- **Phase 6 (signature details):** (1) bunting: two rings of colourful flags on cords around the clock tower (`ClockTower.Bunting`, static, no Legendary trigger); (2) colour-block arches: the three street arches have a four-colour beam and teal/purple pillars. NOT built: toy tram, shop windows showing the owner's display (needs client code).
- **Phase 7 (landmarks):** clock tower (cream shaft with honey bands, teal roof), depot (coral roof, teal shutters), fountain, market stalls recoloured through the same pass. Roof-hiding: `RoofController.luau` is still NOT synced into the Studio place (client Script Sync), so it was not re-run; its logic is unchanged and does not depend on colours.
- **Budget:** parts 2945 -> 3054 (+109 = +3.7%, limit +10%), enabled point lights 49 -> 49, only the sun casts shadows.
- **Checks:** Play boot 14/14 services, PlotCheck 43/43, CustomerCheck 51/51, DevToolsCheck 27/27, live e2e 13/13, customers walk Door -> Browse1 -> CounterSpot -> Exit in Plots 1, 2, 4 and 6.
- **Honest limits:** still blocky rather than rounded (roof shapes, filler bodies, flat-roof deck); the far void beyond the hills is plain blue; paving is very pale and plain; I could not take lowest-graphics or phone-emulator screenshots (cannot switch those from here) so please check them: pale colours and bloom may wash out on low settings, and 49 point lights plus about 3,050 parts are the likeliest cost on a cheap phone.
- **Hand-built piece needed:** nothing mandatory, but a proper rounded roof set, a mesh for trees and a toy tram would lift it further.
