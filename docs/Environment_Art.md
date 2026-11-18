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

---

## Premium restyle: "Modern Boutique District" (started 2026-11-16)

**Restore point:** Team Create **v105** (saved by Ace, 12:53 PM), taken BEFORE this restyle. It still holds the "Sunny Workshop Town" look. All Studio art is outside Git, so v105 is the only way back. (Earlier restore points: v76 before the Sunny restyle, v77 after its phase 1.)

**Before screenshots (taken 2026-11-16 from the Sunny Workshop Town):** street/Plot1 front, three-street overview. Inside Plot1: taken in Phase 1 (the capture tool timed out). What they show: saturated mint-green ground, cyan/purple/yellow roofs, flat SmoothPlastic everywhere, giant pale balls for hills and clouds that read as balloons, rounded cartoon trees. Friendly but toy-like.

### Style guide (draft for Ace's approval; nothing built yet)
**Mood.** A welcoming boutique quarter at golden hour sliding toward early evening: cinematic but friendly, warm, never gloomy. Think "a shopping street you want to walk down", not horror.

**What we take as principles (research notes, honest about their limits).**
- *The Mimic* (benchmark only): no official breakdown of its lighting exists in what I could find, so I take only the generic craft its look rests on: Future lighting, strong contrast, atmosphere that matches the sky, few but deliberate light sources, one consistent palette. Not its horror tone, layout or assets.
- Roblox's own lighting docs: Future lighting, a matched Atmosphere (colour and haze blend ground and sky), separate Ambient / OutdoorAmbient, ColorCorrection for grading, subtle Bloom, SunRays. Contrast is the biggest "premium" lever; over-saturation tires the eye.
- Performance warning (docs and devs): many dynamic lights under Future lighting are the main cost, and many players are on phones.
- Japanese shopping streets (limited research): uniform street furniture (matching lamps and gates), lanterns and strings of lights overhead, wood and timber lattice against plain concrete or plaster, narrow fronts with vertical signs, plants and small planters, light and shadow rhythm along the walkway. Little found on glass fronts, so those come from the brief.

**Palette (only these).** Neutrals: concrete D9D2C5, pale oak D8B98A, plaster F4F0E8, matte black 22252B, soft grey 9AA0A6. One accent per shop: teal 1F7A7A, terracotta D2694A, mustard E3B23C, plum 6E4A7E, sage 7FA37C, navy 2E4A7D. Signs only: warm white FFE9B0 + one coral. No muddy brown, beige-brown or olive. (Plot order for accents: P1 teal, P2 terracotta, P3 mustard, P4 plum, P5 sage, P6 navy.)

**Lighting.** Future lighting, sun about 16.5-17.5h, warm sun against cool shadow fill, gentle contrast, bloom with a high threshold, a light atmosphere in a warm peach-to-blue gradient, no brown haze, only the sun casts shadows, point lights kept at today's count (49) or fewer: warm glow comes from emissive (Neon) bulbs and string lights, not extra lights.

**Materials.** A small reused set: concrete, pale oak, plaster, brushed/matte black metal, paving stone, roof tile. Prefer MaterialVariants if Phase 2 shows they work; otherwise Roblox's built-in Concrete, Wood Planks, Smooth Plastic, Metal, Slate colored to the palette. Glass: real Glass material with a thin black frame.

**Shape language.** Straight modern lines with small bevels and rounded corners (no toy balls). Large glass shopfronts with slim black frames, recessed doors, wide fascia signs, flat canopies or slim awnings, one distinct roof silhouette per shop. Hero detail on shopfronts, signs, entrances, clock tower, square; keep roofs, backs and the horizon simple.

**Detail density.** Medium. Layered street furniture (pendant lamps, planters, outdoor tables, string lights over the square, benches) in repeating modular pieces, one model per prop. Trees with tapered trunks and layered canopies, no stacked spheres.

**Inside the shops (as important as the street).** Warm plaster walls, pale oak shelves and counter, matte black fixtures, soft pendant glow. Shelf and wall colours stay neutral so item rarity and Golden colours read clearly; we change the shelf, never the item.

**Avoid.** Saturated cartoon colours, flat default Studio blocks, muddy browns, overlapping point lights, anything that moves or collides unexpectedly, copying any real game's assets or layout, anything off-palette.

**Hard limits (every phase).** No renames/resizes/moves of the gameplay parts (Floor, Walls, Counter, Sign, Spawn, DisplaySlots, ExhibitSlots, Benches, DecorSlots, CustomerPath, DeliveryPoint, SupplyBoard, Shelves); new objects only under Workspace.Environment or Plots.PlotN.Facade; part count +10% at most; counts reported each phase; no src/, Config, Remotes, data, commits or pushes.

### Restyle log: Modern Boutique District (Dev 1, 2026-11-16, place v106; restore point v105)
**Done in one pass (Ace approved all phases):**
- *Phase 1 lighting:* ClockTime 17.1, Brightness 2.8, warm ColorShift_Top and cool ColorShift_Bottom, Atmosphere peach to blue (haze 0.9), grade contrast +0.12 saturation -0.04, bloom threshold 2.3, sun rays 0.1, DOF off, point-light shadows off. `Lighting.Technology` could not be set from a script (needs RobloxScript capability): **set it to Future by hand.**
- *Phase 2 capability test:* EditableMesh: creating vertices and triangles and a MeshPart from them worked in Studio edit mode; NOT verified in a published game (needs the place's EditableMesh permission), so it is not used. MaterialVariant can be created but needs image assets for its maps; the generators were not used, so no PBR set exists. Creator Store search for a modular shop kit returned mixed styles, paid or stud-style assets and unclear licenses: nothing used. Method used instead: lighting and grade + palette lock + built-in materials (Concrete, WoodPlanks, Metal, Slate, Glass) + hero pieces from plain parts.
- *Phases 3-6 (applied to every plot at once, no separate benchmark shop):* recolor of about 2,950 parts to the palette (nearest-colour fallback), concrete paving, oak trim, matte-black metal frames, slate roofs in the shop accent, fascia signs matte black with warm-white text, scalloped awnings replaced by flat canopies (120 parts removed, 12 added), 52 trees rebuilt with three layered canopy discs, 20 balloon-like hills deleted, `Environment.StreetDetail` (4 poles, 48 wire segments, 44 neon bulbs as a string-light square around the clock tower, 8 outdoor table sets). Clock tower, depot and stalls only recolored.
- *Counts (before -> after):* parts 3,054 -> 3,025 (-1%); point lights 70 (49 enabled) -> 70 (49 enabled); MaterialVariants 0 -> 0.
- *Checks after:* boot 15/15 services; `testAll` 577 passed, 0 failed; PlotCheck 44/44; CustomerCheck 51/51 (inside testAll).

**Self-critique, the five cheapest-looking things (honest):** 1) Roofs are still plain angular slabs, now a glossy slate in the accent (needs a real roof mesh or trim kit). 2) Shopfront glass is still the old small windows, not the large slim-framed glass fronts of the brief (each front needs rebuilding). 3) The clock tower still has multicolor bunting diamonds (off the one-accent rule). 4) Trees are layered discs, better than balls but still stylized. 5) No PBR textures: surfaces are flat colour with built-in materials. I only partly fixed 1 (colour); 2 to 5 are not fixed and need a real build pass or assets.

**Not verified:** lowest graphics level and the phone emulator (Ace to take and send); roof hiding on the new roofs (RoofController needs Script Sync); inside-Plot1 screenshot (capture timed out).

**Second pass (place v107):** real glass shopfronts on all 6 plots (12 windows): larger panes (12.6 x 6.2) in slim matte-black metal frames with 4 panes each, warm glowing back panel, flat canopy moved above the door sign (the gameplay `Sign` part was not moved), roofs changed from glossy slate to matte concrete in the accent, clock tower bunting reduced to teal and warm white only. Counts: parts 3,049 (-0.2% vs the 3,054 start), enabled point lights 49. After: boot ok, `testAll` 577 passed, PlotCheck 44/44. Still cheap: roof silhouettes are plain angular shapes, paving is noisy blue-white, trees stylized, no PBR textures, doors not recessed.

### New layout: "Workshop Lane" high street (Dev 1, 2026-11-16, place v109; restore points v105 and v107)
**Decision (replaces the three-street map from the environment overhaul; see D-Map2 in docs/06):** one promenade along the long axis of the desk mat, three shops facing three shops, a plaza at the north end, a gate and depot at the south end. Reason: the old layout scattered six shops over three streets with long empty walks; one street gives a clear arrival, a visible destination (the clock tower), and a stage for string lights and filler buildings. Shops are 48 studs apart (8 stud alleys between them), fronts 33 studs apart across a 34-wide promenade.
- **Plot positions (whole-plot `PivotTo`, nothing inside a plot changed):** west column faces east (yaw -90): Plot1 (-116.5, z 48), Plot2 (z 0), Plot3 (z -48). East column faces west (yaw +90): Plot4 (-43.5, z 48), Plot5 (z 0), Plot6 (z -48). Promenade axis x = -80. Plots 4 to 6 are still the "rotated" ones PlotCheck uses.
- **Landmarks moved (translated, arches also rotated and narrowed to fit):** Clock Tower at the north end (-80, 232) as the end-of-street vista, Fountain at plaza centre (-80, 190), market stalls west of the plaza, ArchB and ArchC across the promenade at z 112 and -112, Welcome Arch "WORKSHOP LANE" at z -150, Depot at the south end (-80, -205). `SpawnLocation` moved to (-80, 1.5, -128) near the gate.
- **Map size:** the cutting mat was shrunk from 440 x 640 to 260 x 520 (the 53 grid lines were removed) so the district sits on the oak desk with the giant pencils, books and lamp as the border. No expansion of the playable area was needed.
- **Rebuilt from scratch (all under `Workspace.Environment`):** `Paving` (promenade, sidewalks, curbs, inlay, plaza discs, forecourt), `Props` (24 lamps, 22 planters, 10 benches, 54 layered trees, 6 string-light strands across the street), `Fillers` (8 new buildings continuing the street, with shop-name fascias, glass fronts, upper-floor windows, cornices, 4 roof types: pergola, sawtooth, gable, water-tank, and blade signs). The old Paving, Fillers, Props, Trees and StreetDetail were deleted (1,664 instances).
- **Building structure upgrade on the six shops (`Plots.PlotN.Facade.Detail`, 24 parts each):** cornice mouldings on all four sides, concrete skirting, timber fins and a black band on the back wall, black corner trims, and a blade (vertical) sign on the front corner. Plain walls are the main "template" tell, so this is where the effort went.
- **Counts:** parts 3,054 (restyle start) -> 2,663 at this point (-13%); enabled point lights 49 (unchanged; all new glow is emissive).
- **Checks after the move:** boot ok, `testAll` with the live loop 590 passed, 0 failed (a real customer bought an item in the moved Plot1), PlotCheck 44/44, CustomerCheck 51/51, player spawns at Plot1.
- **Not re-verified:** the walking path of customers in each of the east-column plots by eye (CustomerCheck and one live sale pass); Visit teleports (Sean's `RequestVisit` uses the plots' Spawn, which moved with the plots); the Depot's facing (it was translated, not rotated); lowest graphics and phone emulator.
- **Honest remaining cheap spots:** filler and shop side walls are still plain plaster slabs seen from the desk edge; paving texture is noisy; roofs of the six shops are still the old shapes (only recolored); trees are stylized; no real textures.

### UI restyle: "matte charcoal glass" (Dev 1 with Ace, 2026-11-16; restore point = the version saved before this change, v109)
Goal: stop the "AI template" look (cream panels, cartoon Fredoka font, coral/teal toy colours). **Restyle only: no object was renamed, moved or resized, no controller logic changed**, so Sean's UI contract still holds.
- **Colour tokens (`src/Client/UiTheme.luau`, Sean's file, 5 values changed, names kept):** `Teal` 0E7C7B -> 1F7A7A, `Coral` F2784B -> D2694A (terracotta), `Cream` FFF8EE -> 22252B (panel colour is now matte charcoal), `Ink` 1F2D3A -> F4F0E8 (text is now warm white), `Disabled` -> 4A4F58. Because controllers use these names for panels, text, active tabs and call-to-action buttons, the whole UI follows.
- **Static Studio GUI (StarterGui, 11 ScreenGuis, plus `ReplicatedStorage.Assets.UI.ItemCard`):** panel backgrounds charcoal with a subtle top-to-bottom gradient, cards 2D3139, inactive chips 3A3F47, accent buttons terracotta, pills deep teal, text warm white or soft grey 9AA0A6, thin 1 px warm-white strokes at 85% transparency, fonts FredokaOne -> GothamBold and BuilderSansBold -> GothamMedium (69 backgrounds, 92 text colours, 94 fonts, 24 strokes, 12 gradients).
- **Not touched:** rarity colours, Golden colour (FFD43B), item colours, the emoji icons, layout and sizes. Rarity and golden still read clearly on the dark panels.
- **Checked:** Play boots with 15/15 services and 16/16 controllers, no errors; HUD and the Inventory and Upgrades windows screenshotted after the change.
- **Honest limits / still template-looking:** the HUD and button icons are still emoji (a real icon set is needed for a premium look); some text that code colours with `Teal` (for example the Inventory capacity "3/8") is low contrast on the dark panel; windows were checked on desktop only (phone emulator and the other screens (Supply, Collection, Visit, Settings, Discovery, Restoration, Toasts, Tutorial) not individually screenshotted); no motion or sound polish yet.

### Points of interest added to Workshop Lane (Dev 1 with Ace, place v111)
All under `Workspace.Environment.Districts` (visual only, no gameplay code, parts +260): **Museum of Restored Things** (east side of the north plaza: columns, glass atrium, banners, skylight; a natural home for the Collection Book / exhibit idea), **Cafe & Teas** (west side of the plaza: glass front, terracotta awning, 6 terrace table sets, 3 umbrellas), **Supply Warehouse** (south-east: roller doors, loading dock, crates, pallets, forklift; a natural home for the Supply / crate deliveries), **Pond Park** (south-west: pond, stones, trees, benches, flower beds), **two glass skybridges** across the promenade at z 94 and z -94 (they join the filler buildings on both sides), and a **directory board** at the south gate listing what is where. The market stalls moved north-south out of the cafe footprint. Enabled point lights dropped 49 -> 28 because the old lamp posts carried lights; new glow is emissive. After: `testAll` 577 passed, PlotCheck 44/44, parts 2,923 (-4% vs the 3,054 start).
**Ideas that need code (not built; each touches a contract, so the team decides):** 1) Museum as a real feature: the Collection Book opens from a pedestal inside, and exhibit points show on a leaderboard board. 2) Warehouse as the Supply point: the crate board / free delivery pickup moves there (walk to the dock), a daily mystery pallet. 3) Walking ambient NPCs and pigeons (cheap client-side animation, no server). 4) A bulletin board where players post a "wanted item" that customers also ask for. 5) A Cafe stall that sells a small timed boost (cosmetic or XP). 6) Friend visits: skybridge and plaza become the meeting spots; a shared photo spot with a camera prompt.

**Museum interaction (Dev 1, approved by Ace, place v113):** a Collection pedestal in front of the Museum (`Environment.Districts.Museum.CollectionPedestal.PromptAnchor.CollectionPrompt`, press E) opens Sean's Collection Book through `CollectionController.Open()`. New file `src/Client/Controllers/MuseumController.luau` + one line in `Main.local.luau`; client only, no remote, no data. Tested: teleport to the pedestal, press E, Collection Book visible. The Warehouse-as-Supply-point idea (A2) is NOT built: it changes where crates are bought and needs a flow decision.

### Warehouse is the Supply point (Dev 1, approved by Ace; place v115)
Paid crates can now only be bought at the **Supply Warehouse** (south end of Workshop Lane), not by tapping a button anywhere. **Server:** `RequestBuyCrate` is refused unless the player is within `Economy.SupplyMaxStuds` (20 studs) of `Environment.Districts.Warehouse.SupplyCounter` (`ShipmentService.IsNearSupply`); the refusal sends a toast. **Client:** `ShopController.OpenSupply()` explains where to go when you are far away (HUD box button and the plot SupplyBoard prompts become signposts), and closes the window when you walk away; the new `WarehouseController` opens the Supply screen from the "Supply Desk" counter prompt (press E). The **free delivery still arrives at your own door** (no change). Studio art: `Districts.Warehouse.SupplyDesk` + `SupplyCounter` (not in Git). Tested live: far from the counter, `RequestBuyCrate` bought nothing and showed the warehouse toast; at the counter it bought a Starter crate (-$50, +3 boxes); E opened the Supply screen; `testAll` with the live loop 617 passed, 0 failed. Files: `ShipmentService.luau`, `Economy.luau` (`SupplyMaxStuds`), `ShopController.luau` (Sean, small change), new `WarehouseController.luau`, `Main.local.luau`, `DevTools.luau` (whyStuck text). Sean: the Supply screen opens only near the counter now; please check it on a phone.

**Restore bug found and fixed (Dev 1, 2026-11-16, place v116): "I cannot use Restore" = invisible dirt.** The Restore flow itself worked (session, bench view, Wipe step, pointer attached). But the real RubberDuck's three `DirtSpots` were only 0.28 x 0.02 x 0.28 studs and sat INSIDE the body and head, so the dirt decals were hidden and the pointer ray hit the body instead: nothing visible to wipe. Fix (Studio only, not in Git): the three spots now lie on top of the body and head (0.5 stud, just above the surface), and all 21 placeholder models had their dirt and rust spots moved to the clear front strip of the base (0.8 x 0.7 studs). **Rule for item models (Dwayne, please add to the contract):** every spot Part must sit ON the outside surface (about 0.02 above it), face outward, be at least 0.5 studs, and never inside another part; check by looking at the model on the bench before saving. Not re-tested by mouse after the fix: Studio would not start Play when I tried (it hung), so please press Play and try Wipe on the duck.

### Scaled shops (Dev 1, 2026-11-16, place v134)
Shops can now be scaled (plan: 1.4x, a 56 stud floor, instead of 40). A scale test on Plot 1 passed `testAll` with the live customer loop. Code made scale-aware: `RoofController` (roof limits follow the floor width), `PlotService.buildExpansion` (Back Room and Showroom templates are scaled with the plot), `RestorationView` (the item is scaled by floor width / 40 so it matches the bigger bench and camera), plus two new PlotCheck tests (46). Plot 1 was reverted to 1x after the test; all six shops get scaled when the new layout is built. Dwayne: `RestorationView` got a small change (item scale from the plot size); please keep it.

## Canal Town fill (Studio-only art, place v154)
- New folder `Workspace.CanalTownWow` (all anchored, non-colliding except the grass ground slabs): Fountain, MuseumDome, ClockTower (brick shell + terracotta spire over the original tower), Ground (grass over the whole 500x700), Canals (x=-272 and x=110), Bridges (12), Lagoon + piers (south), Buildings (~43 houses), Decor (palms, lamps, benches, planters, parks), Boats.
- Dwayne's 8 `CanalTownAssembly.Buildings` scaled 1.25x (north houses, bakery and sari-sari moved 4 studs in Z to avoid overlap).
- Desk props (DeskLamp, BookStack x3, Ruler, ScrewJar, Pencil, VarnishTin) moved to `ServerStorage.DeskPropsArchive`; move back into `Workspace.Environment.Horizon` to restore.
- Checks after the change: testAll 632 passed / 0 failed, PlotCheck 46 passed; walked to Museum, Warehouse supply, shops, east/west/south districts.
- Not done: Blender hero models (museum, warehouse, depot), bridges are not walkable decks (canals do not block movement), phone performance unmeasured (~7,200 parts).

## Circle-park layout (place v156) and the Blender museum
- Layout follows the map brief (assets/template/3_Brief.png): central park circle (r 75, "Wishing Fountain Plaza": plaza + fountain, moat ring with 4 bridges, flower beds, carousel/slide/swings/sandbox), ring road, the six shops (scaled 1.4x, 56 studs) around it at r 123 with doors facing the park, entry avenue + Welcome Arch + spawn at the south, Museum + clock tower at the north plaza, Warehouse and Depot at the south. All new art is in `Workspace.CanalTownWow` (`Park`, `ParkDecor`, `Fountain`, ...).
- Old Workshop Lane street pieces (Fillers, Arches B/C, skybridges, central paving, props, Dwayne's draft canals/bridges/dressing, desk props, loose test scenes) are in `ServerStorage.OldLayoutArchive` and `ServerStorage.DeskPropsArchive` (parent them back to restore). Dwayne's 8 buildings now flank the north and south avenues.
- Checks: testAll with the live loop 645 passed / 0 failed, PlotCheck 46/46; walked to Museum, Warehouse supply (10 studs) and shops.
- Hero museum: `tools/blender/museum.py` -> `assets/models/Museum.glb` (about 25,700 triangles, 14 colour groups, 72 x 52 studs, dome ~60 high). Import with Home > Import 3D, then run `tools/studio/PlaceMuseum.luau` in the Command Bar (Edit mode): it colours by name, rotates the front to face the plaza, places it at (-8, 205) and archives the old blocky museum (the Collection pedestal and its prompt stay).

## Scattered canal-town layout: blockout (place v165, approved by Ace + Sean)
Plan: assets/template + Downloads/DustyFinds_Phase2_Blueprint.png (Phase 2). Changes from the blueprint, agreed: shops at street level (no shop terraces), height only on the plaza (+6), museum steps and canal walks; the Warehouse stays the only supply point; a My Shop HUD button replaces walking home.
- Plots (whole plot moved with PivotTo, door facing the street): Plot1 (40, 61) door -X, Plot2 (45, -75) -X, Plot3 (-190, 50) +X, Plot4 (-180, -215) +Z, Plot5 (-30, -140) +Z, Plot6 (-190, -85) +X. Each keeps 34 studs clear behind it for the Back Room / Showroom.
- Landmarks (rigid group moves): Museum (Blender) + Collection pedestal -> (-80, 126) facing the plaza; Depot + canopy + jeepney/tricycle -> (-196, 150); Warehouse + SupplyCounter + trim -> (-45, 222); clock tower -> (-150, 95); Welcome Arch -> (-80, -275), SpawnLocation (-80, -253).
- Plaza: the park/fountain/play area/food carts raised +4.3 onto a +6 platform (r 82) with a retaining wall and four 14-wide stairways. Workspace.CanalTownBlockout holds the platform, stairs, streets, the south canal + basin, and labelled blockout boxes (Waiting Shed, 4 jeepney stops, basketball court, domed hall, market lane, gardens, Storage Room space per shop).
- Dwayne's 8 buildings moved to the boulevard (Kainan, Supermart), the plaza south side (bakery, sari-sari) and the north street (homes).
- Archived (reversible): conflicting outer houses/decor -> ServerStorage.OldLayoutArchive.BlockoutClears; the park ring road and avenues.
- Checks: PlotCheck 46/46; testAll 632/0 plus the live loop 13/13 (the first run crashed only because the test started before the player's data loaded); pathfinding from the spawn reaches all 6 shops, the museum pedestal and the warehouse counter; shop -> warehouse walks 10 to 28 s.
- New client controller src/Client/Controllers/MyShopController.luau (HUD.LeftButtons.MyShop 🏠, uses Sean's RequestVisit to your own UserId). Tested: from the warehouse it puts you at your shop's Spawn.
- Next: art pass on the blockout (canal bridges high enough for boats, plaza and neighbourhood buildings, Filipino businesses), then Staff stage 1 (Stocker + Storage Room).
- Elevations (place v167, following the blueprint's elevation plan): every shop on its own stone terrace (whole plot raised with PivotTo; the terrace also covers the 34-stud Back Room space and a front landing with 16-wide stairs to the street): Plot5 +2, Plot2/Plot3/Plot4 +4 (Plot4's landing joins the canal walk), Plot1 +6, Plot6 +8. Plot2 moved 7 studs west so its Back Room space stays clear of the west canal. Museum + pedestal raised onto a +6 terrace joined to the plaza (stairs N/E/W); Depot + clock tower on a +4 terrace. Canal walks +4 on all three canals (they carry the canal-side house rows, which were raised with them), stairs down every 60-130 studs. 14 high bridges: deck top +8.5, underside +7.5 (6.9 studs over the water), steps up from the walks. North-west homes on a +2 terrace. All in Workspace.CanalTownBlockout.Elevation.
- Checks after the elevations: PlotCheck 46/46, testAll 645/0 including the live customer loop on a raised shop, pathfinding (no jumping) from the spawn reaches all 6 shop doors and interiors, the museum pedestal and the warehouse counter.
- Refinement + shop batch (place v168-v171): bridges rebuilt (level deck +8.5, 6 steps of 0.75 down to a 3-stud landing on each +4 walk, no piers in the water, underside +7.5); 250+ floating/sunk decor items snapped to the surface; buildings levelled or nudged to flat ground (nothing deleted; Dwayne's bakery/supermart/sari-sari re-lotted and turned to face their streets); old canal rails archived. Shops moved (approved): Plot1 (55,125) door S +6, Plot2 (60,-80) door N +4 (West Square between them), Plot3 (-170,235) door to the east canal +4 (landing joins the walk), Plot4 (-200,-225) door N +4 (landing joins the south canal walk), Plot5 (-38,-128) door to the boulevard +2, Plot6 (-215,-50) door N +8 (East Street). Canal walls now rise to the +4 walks with stone caps; railings on every canal edge with openings at the bridges. Blockout labels switched off.
- Checks: PlotCheck 46/46, testAll 645/0 with the live loop, walks without jumping: spawn -> shops 8-37 s, shop -> warehouse 12-32 s.
- Step B finishing + first step C model (place v172-v174): stone pilasters and plinth bands on every terrace face; balustrades, handrails, end posts and lamp posts on all 38 stairways; Dwayne's old pipeline test bakery archived. tools/blender/bridge.py -> Bridge.glb (stone segmental arch, voussoirs, keystone, balustrade, stair parapets, lanterns, flower boxes; ~7,400 tris) placed at all 14 bridges as visual-only MeshParts (Workspace.CanalTownWow.BridgesArt; template ServerStorage.BridgeTemplate; the 2 south-canal bridges stretched to 19.2). The blockout bridge parts stay as the invisible walking surface. Canal walls/caps and railings are now solid, plus invisible RailColliders along every railing, so the canals can only be crossed on the bridges (tested with a real character: blocked between bridges, over the deck on bridges 3, 9 and 14); all shops, the museum and the warehouse still reachable.
- Plan v2 (Ace's df_blueprint.py / DustyFinds_Phase2_Blueprint_Detailed.svg, place v177): shops at the plan's spots (Plot1 (74,61) +6, Plot2 (105,-75) +4, Plot3 (-190,50) +4, Plot4 (-186,-240) +4 with a 20-stud landing, Plot5 (-32,-126) +2, Plot6 (-190,-85) +8); curved West Canal (12 wide) looping from the west edge past Shop 2 into a basin at (-10,-246.5), curved South Canal (16 wide) from the basin to the east canal; 6-stud walks at +4 on both banks with solid walls/caps and invisible rail colliders; 8 bridge crossings (blockout deck +8.5 + 6 steps to the walk + 7 street steps; Blender bridge mesh on top, Workspace.CanalTownWow.BridgesArt, frames in CanalTownBlockout.BridgeFrames); plan streets; entrance gate at z -338, spawn (-80,-318); Kainan (-30,-298) and Supermart/Sulit (-122,-298) beside the entrance; court, gardens, domed hall, market lane boxes at the plan spots; clashing houses/decor archived (ServerStorage.OldLayoutArchive.PlanV2Clears), sari-sari re-lotted. Adjustments vs the plan: east canal kept at x -272 (12 wide), plaza kept at (-80,0) r 82, stairs 0.5-stud steps, bridge at (-272,100) instead of 51 (51 lands on Shop 3's back room).
- Checks: PlotCheck 46/46, testAll 645/0 with the live loop, all shops/museum/warehouse reachable without jumping, real character blocked at the west canal away from bridges and over the deck on bridge 2.
