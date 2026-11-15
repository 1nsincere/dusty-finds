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
