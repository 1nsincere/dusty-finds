# Dusty Finds: layout export summary

Read-only export of the place open in Studio: "Dusty Finds: Restore & Sell", placeId 113871213495650, Edit mode, 2026-11-18.
Nothing in the place was changed. The full data is in `df_export.txt`.

**How it was exported.** `DF_Layout_Export.lua` was not found anywhere on this PC, so I wrote equivalent read-only Luau for sections 1–4 (no section 5, nothing created in ServerStorage). Studio blocks HTTP from the MCP tool, so the script `print`ed each line with a `DFX|` prefix, and the lines were taken from Studio's own log file (`%LOCALAPPDATA%\Roblox\logs`).

**Completeness check.** Studio reported 839 folders/models, 733 models and 5,665 parts. The file has exactly 839 / 733 / 5,665 rows, numbered with no gaps.

**Conventions.**
- Units are studs, Y is up.
- `rot` is Orientation X,Y,Z in degrees.
- `topY` is centre Y + half height. It's exact for flat parts. For the round Cylinder discs lying on their side (park lawn, plazas, moat), the thickness is size **X**, so the real top is pos.Y + X/2. I give corrected values below.

---

## 1. Baseplate

| | |
|---|---|
| Name | `Workspace.Baseplate` (Part, WoodPlanks, colour d8b98a) |
| Size | 660 × 14 × 700 studs |
| Centre | (0, -7, -50) → covers X -330..330, Z -400..300 |
| **Top surface Y** | **0.0** (this is "+0") |
| Ground on top of it | Grass slabs, top **Y 0.4**: `Environment.Ground.CuttingMat` (X -210..50, Z -245..275) and `CanalTownWow.Ground.North/South/East/West` around it. These are not overlapping. |
| Edge | `Environment.Horizon`: walls EdgeN/S/W 80 tall just outside the plate, a 2.4-tall wood lip (LipN/S/E/W) on the rim, an apron and "bench legs" under it. The walls are named for the old compass: `EdgeW` stands at X -331, which is the **-X (east)** side in this orientation. There's no wall at X +331, so the **+X (west)** side, behind the shop row, is open (only the 2.4 lip). |
| Terrain | `Terrain:CountCells()` = **0**. There's no terrain at all; ground and water are Parts. |

There is also `Workspace.NewLayout`, a blank copy of the Baseplate (same size, centre (760, -7, -50), 20-stud grid, faint lines every 100). I added it earlier today as a layout area. It's not part of the game layout.

## 2. Orientation check

| Landmark | World centre (X, Z) | Where it is |
|---|---|---|
| SpawnLocation / Main Entrance | (-80, -318) | far **-Z** |
| Museum | (-80, 126) | **+Z** of the central park |
| Depot | (-196, 150) | **+Z** and **-X** |
| Shop Plot3 | (258, 160) | far **+X** |

**+Z = North** (museum side), **-Z = South** (entrance and lagoon), **-X = East** (Depot and the straight canal side), **+X = West** (shop row). This matches the Phase 2 blueprint ("North = +Z top, East = -X right").

## 3. Landmarks

Centre and footprint are the model bounding box. Top Y is the highest point. Front is the direction the entrance faces.

| Landmark | Studio path | Centre (X, Y, Z) | Footprint X × Z | Top Y | Rotation / front |
|---|---|---|---|---|---|
| Museum | `CanalTownWow.MuseumBlender` | (-80.0, 39.6, 126.0) | 82.0 × 64.9 | 71.3 | yaw 0; front faces **-Z (south)** to the park. Sits on MuseumTerrace (top 8.0). |
| Collection pedestal (gameplay) | `Environment.Districts.Museum.CollectionPedestal` | (-80.0, 10.2, 89.5) | 6.4 × 4.0 | 11.4 | in front of the museum on its terrace |
| Depot | `CanalTownWow.BlenderBuildings.Depot` | (-196.0, 19.4, 149.9) | 68.0 × 52.2 | 34.8 | yaw 0; front **-Z (south)**; on DepotTerrace (top 4.2) |
| Warehouse | `CanalTownWow.BlenderBuildings.Warehouse` | (-46.0, 13.3, 222.3) | 44.6 × 55.8 | 25.5 | yaw 0; front **-Z (south)**; floor Y 2.6 |
| Supply counter (gameplay) | `Environment.Districts.Warehouse.SupplyCounter` (+ SupplyDesk) | (-55.0, 6.0, 203.0) | 6.6 × 2.8 | 11.1 | 4 studs inside the warehouse door |
| Clock Tower | `CanalTownWow.BlenderBuildings.ClockTower` | (-150.0, 29.7, 95.0) | 16.6 × 16.6 | 55.5 | yaw 180; clock face **+Z (north)**; on DepotTerrace (base Y 4.0) |
| Central Fountain Plaza | `CanalTownWow.Fountain` (in `CanalTownWow.Park`) | (-80, —, 0) | fountain basin Ø 26.4; plaza disc Ø 48 | fountain crown 24.2; plaza top ≈ 6.45 | round, no front |
| Park (central circle park) | `CanalTownWow.Park` + `ParkDecor` | (-80, —, 0) | lawn Ø 150 (X -155..-5, Z -75..75); curb Ø 154.8; moat ring Ø 96 inside the lawn with 4 bridge decks | lawn top ≈ 6.05; bridge decks 7.0 | round; carousel at (-40, 40), slide/swing at (-120, ±40), seesaw/sandbox at (-43, -37) |
| Pond Park (second park) | `Environment.Districts.Park` | (-148, —, -195) | 40.3 × 52.0 | canopy 15.1 | pond Ø 26 at (-150, -195) |
| Domed Hall | `CanalTownWow.BlenderBuildings.DomedHall` | (88.0, 22.6, -219.3) | 50.0 × 61.4 | 44.7 | yaw 180; front **+Z (north)** |
| Market Lane | `CanalTownBlockout.MarketLane` | (-80.0, 0.6, -244.0) | 30.0 × 60.0 | 0.8 | **marker only**: a pink, 35% transparent slab (no stalls on it) |
| Market stalls (actual stalls) | `Environment.Landmarks.MarketStalls` | (-142.0, 5.4, 157.0) | 38.8 × 27.8 | 9.8 | 33 parts, on the Depot terrace side |
| Basketball court | `CanalTownBlockout.BasketballCourt` | (92.0, 0.7, 124.0) | 30.0 × 46.0 | 1.0 | **marker only**: an orange, 35% transparent slab (no hoops or lines) |
| Kainan ni Bida | `CanalTownWow.BlenderBuildings.Kainan` | (-46.6, 13.2, -307.0) | 47.3 × 38.4 | 25.9 | yaw 90; front **-X (east)**, onto the main street |
| Sulit Mart | `CanalTownWow.BlenderBuildings.Sulit` | (-112.6, 9.2, -309.0) | 51.4 × 48.2 | 18.0 | yaw -90; front **+X (west)**, facing Kainan across the street |
| Main Entrance (Gate) | `CanalTownWow.BlenderBuildings.Gate` | (-80.0, 13.1, -334.0) | 71.0 × 13.0 | 26.0 | yaw 0; across the main street |
| SpawnLocation | `Workspace.SpawnLocation` | (-80.0, 1.5, -318.0) | 8 × 8 | 2.0 | just north of the Gate, on the lagoon plaza |

**Also present:**
- Bakery at (-51.1, -110.0), 29 × 26, front -X.
- Sari-sari at (-53.5, -150.0), 26 × 24, front -X.
- Cafe `Environment.Districts.Cafe` at (-134.6, 212.7), 32 × 42.
- Directory board at (-71.5, -122).
- Lagoon at the south end: `CanalTownWow.Lagoon` water (X -200..40, Z -385..-300), sea wall at Z -299, piers.
- A big `Workspace.Street` slab at (-78, 0.9, -57), 260 × 64, top 1.4 (see Problems).

## 4. Shops (6 plots)

Each plot is a Model `Plots.PlotN` with a 56 × 56 `Floor` (PrimaryPart).

**Door direction** = the plot's `Spawn` pad compared with the `Floor`.

**Back Room** = the 34-stud strip directly behind the back wall. The room itself is **not in Workspace**: it's cloned at runtime from `ServerStorage.Expansions` when bought. The `StorageRoomSpace_PlotN` parts are 6 × 6 neon signs on the back wall, not rooms.

| Plot | Floor centre (X, Z) | Floor top Y | Floor yaw | Door faces | Back Room space (reserved) | Terrace (paving top) | Front stairs |
|---|---|---|---|---|---|---|---|
| Plot1 | (74, 61) | 7.0 | 90 | **-X (east)** | X 102..136, Z 33..89 | Plot1Terrace X 40.3..135.7, Z 29.3..92.7, top 7.0 | 13 steps, X 27..40, Z 53..69, 0.7 → 6.5, up toward +X |
| Plot2 | (105, -75) | 5.0 | 90 | **-X (east)** | X 133..167, Z -103..-47 | Plot2Terrace X 71.3..166.7, Z -106.7..-43.3, top 5.0 | 9 steps, X 62..71, Z -83..-67, 0.7 → 4.5, up toward +X |
| Plot3 | (258, 160) | 5.0 | 90 | **-X (east)** | X 286..320, Z 132..188 | Plot3Terrace X 216.3..321.7, Z 114.3..205.7, top 5.0 | 22 steps along X 209..215, Z 147..173, 1.1 → 4.6 (canal-walk side) |
| Plot4 | (-186, -240) | 5.0 | 180 | **+Z (north)** | X -214..-158, Z -302..-268 | Plot4Terrace X -217.7..-154.3, Z -301.7..-192.3, top 5.0 | 9 steps, X -194..-178, Z -192..-183, 0.7 → 4.5 |
| Plot5 | (258, -270) | 3.0 | 90 | **-X (east)** | X 286..320, Z -298..-242 | Plot5Terrace X 216.3..321.7, Z -315.7..-224.3, top 2.9 | 10 steps along X 209..215, Z -278..-262, 1.1 → 2.6 |
| Plot6 | (258, -100) | 9.0 | 90 | **-X (east)** | X 286..320, Z -128..-72 | Plot6Terrace X 216.3..321.7, Z -145.7..-54.3, top 9.0 | 42 steps along X 209..215, Z -121..-79, 1.1 → 8.6 |

Each plot also has:
- Counter: 14 × 4.2, inside, near the door side.
- Sign: on the front, about 15 above the floor.
- DeliveryPoint: next to the Spawn pad.

Shell styles: Plot1 and Plot4 = A, Plot2 and Plot5 = B, Plot3 and Plot6 = C. The art is in `Facade.Shell/Upper/Roof`.

## 5. Bridges

**Found 9 walkable bridges, not 14.** Each one is:
- a `BridgeN_Deck` plus 12 `_Step` and 14 `_StreetStep` parts in `CanalTownBlockout.CanalsV2`;
- visual art `CanalTownWow.BridgesArt.BridgeN`;
- a CFrameValue `CanalTownBlockout.BridgeFrames.BridgeN`, which is not a part.

All decks are 9 wide, deck top **Y 8.5**, and the steps go from 0.7 up to 7.7.

| Bridge | Deck centre (X, Z) | Deck length | Length incl. stairs | Yaw | Crosses |
|---|---|---|---|---|---|
| Bridge1 | (37.9, -19.7) | 15.2 | ≈ 41 | -55 | West canal (CanalsV2 `West*`) |
| Bridge2 | (20.0, -59.0) | 15.2 | ≈ 41 | -75 | West canal |
| Bridge3 | (15.6, -170.9) | 15.2 | ≈ 41 | -90 | West canal |
| Bridge4 | (-136.6, -163.3) | 19.2 | ≈ 45 | 21 | South canal (CanalsV2 `South*`) |
| Bridge5 | (-67.2, -204.4) | 19.2 | ≈ 45 | 35 | South canal |
| Bridge6 | (-272.0, 100.0) | 15.2 | ≈ 41 | 90 | East canal (straight, `CanalTownWow.Canals`, X -272) |
| Bridge7 | (-272.0, -39.0) | 15.2 | ≈ 41 | 90 | East canal |
| Bridge8 | (-272.0, -204.0) | 15.2 | ≈ 41 | 90 | East canal |
| Bridge9 | (198.0, 14.9) | 15.2 | ≈ 41 | 0 | West canal (its east–west leg near Z 15) |

The central park has 4 more short flat bridge decks across its moat (`CanalTownWow.Park.BridgeDeck`, top 7.0, no stairs). Counting those gives 13, still not 14.

## 6. Canals

**Canals are Parts, not terrain water.** The water surface is a 0.1-thick SmoothPlastic slab with **top Y 0.6**, plus a "Deep" darker slab under it (15% transparent).

| Canal | Parts | Water width | Outline | Walls / walks |
|---|---|---|---|---|
| West canal (`CanalsV2.WestWater1..61`, curved) | 61 segments, median 12.2 long | median **6.7** (segments 2.8–12.2; tapered pieces on bends) | centreline from about (254, 15) west → east along Z≈15 to (110, 11), bending south through (62, 0), (31, -32), (23, -49), (14, -100), (15, -137), (11, -203), (8, -212), and ending at (-3, -233) at the turning basin | wall top 4.0, cap top 4.4 (2.2 wide), canal walk top **4.0** (6 wide) both sides, railings + invisible RailColliders |
| South canal (`CanalsV2.SouthWater1..36`, curved) | 36 segments, median 16.2 long | median **8.1** (4.5–11.5) | from about (-269, -149) east through (-220, -149), (-181, -152), (-153, -158), (-140, -162), (-63, -207), (-49, -217) to (-12, -235) at the basin | same as the west canal |
| Turning basin (`CanalsV2.BasinWater`) | 1 disc | Ø 34 | centre (-10, -246.5) | BasinWall/Walk/Cap, walk top 4.0 |
| East canal (`CanalTownWow.Canals`, straight) | 1 water + 1 deep part | **12** (X -278..-266) | straight along X -272 from Z -345 to Z 290 | walls X -279.6..-264.4 top 4.0, caps top 4.4; promenade X -288.6..-255.4 top 0.8; raised walk `EastCanalEast_Paving` X -330..-280 top 4.0 |
| Lagoon (`CanalTownWow.Lagoon`) | water + deep | 240 × 85 | X -200..40, Z -385..-300 | sea wall at Z -299 (top 2.8), 3 piers |

The full outline of every segment (position, size, yaw) is in `df_export.txt` section 3: search `CanalsV2.WestWater`, `SouthWater`, `BasinWater`, `CanalTownWow.Canals`.

## 7. Stairs, platforms and terraces

Up direction uses the compass from section 2: +X west, -X east, +Z north, -Z south.

**Terraces and platforms (paving tops)**

| Name | Footprint (X range, Z range) | Top Y |
|---|---|---|
| MuseumTerrace | -127.7..-32.3, 82.3..165.7 | 8.0 |
| DepotTerrace (Depot, Clock Tower, market stalls) | -241.1..-141.7, 82.9..186.3 | 4.2 |
| Plot1Terrace | 40.3..135.7, 29.3..92.7 | 7.0 |
| Plot2Terrace | 71.3..166.7, -106.7..-43.3 | 5.0 |
| Plot4Terrace | -217.7..-154.3, -301.7..-192.3 | 5.0 |
| Plot3 / Plot5 / Plot6 Terrace (EastQuarter) | 216.3..321.7 × 91.4 deep, centred Z 160 / -270 / -100 | 5.0 / 2.9 / 9.0 |
| NorthHomesTerrace | -19.7..44.7, 190.3..249.7 | 2.0 |
| ResTerraces NE (homes) | 50.3..139.8, 216.3..250.7 | 4.0 |
| ResTerraces S (homes) | -279.7..-145.3, -396.7..-362.3 | 4.0 |
| Hillside A (front + back) | -316.7..-290.3, -95.8..180.8 | 8.5 |
| **Hillside B (highest)** | -330.7..-317.3, -95.7..180.7 | **16.0** |
| East canal raised walk | -330..-280, -345..290 | 4.0 |
| Canal walks (west, south, basin) | along the canals | 4.0 |

**Stairs** (bottom step top → top step top, and which way you walk up)

| Stairs | Footprint | Heights | Up toward |
|---|---|---|---|
| MuseumGrandStair (from the park) | X -93.6..-66.4, Z 76.6..82.0 | 6.1 → 7.8 | +Z (north) |
| MuseumStairsN / E / W | N: X -90..-70, Z 166..181; E: X -143..-128, Z 117..131; W: X -32..-17, Z 117..131 | 0.8 → 7.6 | toward the museum |
| DepotStairsN / W | N: X -200..-184, Z 186..193; W: X -142..-135, Z 132..148 | 0.7 → 3.5 | onto the Depot terrace |
| Plot1/2/4 stairs | see section 4 | | |
| Plot3/5/6 stairs (EastQuarter) | see section 4 | | |
| HillStairA (33 steps, in flights) | X -300..-291, Z -93.5..100.5 | 4.4 → 8.1 | onto Hillside A |
| HillStairB (57 steps, in flights) | X -317..-302, Z -54..160 | 8.9 → 15.6 | onto Hillside B (16) |
| ResNEStair | X 68.5..121.5, Z 216.6..223.8 | 0.8 → 3.6 | +Z |
| ResSStair | X -238.5..-176.5, Z -369..-362.6 | 1.1 → 3.6 | -Z |
| HomesStairsS / E (3 steps each) | S: X 6..18, Z 187..190; E: X -23..-20, Z 215..225 | 0.7 → 1.6 | onto NorthHomesTerrace |
| Bridge stairs | 9 bridges × 26 steps | 0.7 → 7.7, deck 8.5 | both ends up to the deck |
| Canal-walk stairs | in `CanalsV2` (step parts along the walks) | 0.4 → 4.0 | |

Standard step: 0.38 tall × 0.8 deep (Hillside flights differ). Every Step and Cheek part is listed in section 3.

## 8. Problems found

1. **No unnamed parts or models.** There are no parts or models called "Part", "Model", "Union" or "MeshPart".
2. **Exact duplicates (same class, position, size and rotation): 2.**
   - `CanalTownWow.Decor.Bloom` appears twice in the same spot. This is a real duplicate.
   - `BlenderBuildings.Sulit.Sulit_Red_mesh` and `Sulit_Purple_mesh` have identical bounds. These are probably two coloured stripe meshes that share a bounding box, so likely not a real duplicate.
3. **Old and new versions of the same thing are both still in the map:**
   - Two fountains: the old `Environment.Landmarks.Fountain` (small pillar + spout at (-80, 190), on the old north plaza paving) and the central `CanalTownWow.Fountain` at (-80, 0).
   - Old north-plaza paving, `Environment.Paving.PlazaInner/Ring/Outer/Top/LinkN`, around (-80, 192) at top ~1.1. Its centre is under the Warehouse forecourt and museum north stairs area.
   - Old blocky buildings in `CanalTownAssembly.Buildings`, all alongside the newer Blender buildings: SariSariStore (32.7, -231.7), PandesalBakery (-114.3, -106.5), and West/East Home North/South near (20 / -5, 205 / 232).
   - `Environment.Paving.Forecourt` (60 × 60 at (-80, -180)) is the old shop-5 forecourt.
4. **`Workspace.Street`** is a 260 × 64 cobblestone slab at (-78, 0.9, -57), top 1.4. It runs under the central park (lawn top ≈ 6), so most of it is hidden. It's probably a leftover.
5. **Marker slabs, not real builds:** `BasketballCourt` and `MarketLane` are 35% transparent coloured slabs only.
6. **Off the Baseplate edge:**
   - 80 `Detailing.TerracePilaster` and 1 `TerracePlinth` at X -330.3. That's only 0.3 past the edge.
   - One `BlenderHouses.HouseC` part reaches X ≈ -340, and several hillside houses overhang the -X (east) edge (house bounds reach X -342). They poke through the `Environment.Horizon.EdgeW` wall at X -332..-330.
   - The +X (west) side has no edge wall at all. The names EdgeN/S/W follow an older compass where W = -X.
7. **Bridges: 9, not the expected 14** (see section 5).
8. **Floating or buried:** nothing has its top below Y 0. Of the 8 parts whose bottom is above Y 30, all are expected (shop signs/roofs, museum dome, letters, one house chimney).
9. **Not in Workspace (so not in the export):**
   - Back Rooms: runtime clones from `ServerStorage.Expansions`.
   - `ServerStorage.ItemImports`, `HouseTemplates`, `ShopShellTemplate*`, `OldLayoutArchive`.
   - BridgeFrames: CFrameValues, not parts.
10. **Hard to identify by name alone:**
    - `CanalTownBlockout.Detailing` (725 parts: pilasters, plinths, balustrades, lamp posts).
    - `CanalTownWow.Decor` / `ParkDecor` (planters, benches, lamps, palms).

    These are decoration. Their exact positions are in section 3.
