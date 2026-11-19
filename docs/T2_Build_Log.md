# T2b Terraced Town build log (Dev 1)

Rules: see the T2b master rules from Ace (levels, steps, protected list). Backups in `ServerStorage.T2Backup.<Phase>`,
archived old parts in `ServerStorage.OldLayoutArchive` (each has an `OriginalPath` attribute). New parts in `Workspace.TownT2.<Phase>`.

## Phase 1: clean-up (2026-11-18, approved)
Archived: old north fountain, old north-plaza paving (PlazaInner/Ring/Outer/Top/PlazaLinkN) and Forecourt,
`CanalTownAssembly.Buildings`, `Workspace.Street`, JeepneyStop_Plaza/Canal/Warehouse (Entrance kept), the 3 dry boats at
X 108.6, one overlapping yellow `Decor.Bloom` at (-304.9, 10.4, 147.7), and the 5 back-row hillside houses
(`BlenderHouses` HouseA-E at X -330, Y 16) that stuck out past the -X edge.

## Phase 2: entrance square + lagoon (2026-11-18, awaiting approval)
- Lagoon water X -140..40, Z -398..-362 (deep X -135..35, Z -395.5..-369.5), clear of ResS terraces and HouseE.
- SeaWall + cap on the north edge, centre (-50, -361), 180 long.
- 3 piers at X -120 / -80 / -10, 32 long (Z -394..-362), 4 post pairs at Z -366/-374/-382/-390, lamp at Z -393.
  6 surplus PierPosts archived.
- Kainan and Sulit raised +0.1 (floors at 0.75), Gate raised +0.35 (bottom 0.75). SpawnLocation unchanged.
- New paving `TownT2.Phase2.EntranceSquare_Main` (X -154..40, Z -338..-285) and `_West` (X -200..-154, Z -338..-302), top 0.75.

## Phase 3a: +8.5 core platform (2026-11-18, awaiting approval)
- Prep: SpawnLocation lowered 0.25 (bottom 0.75); `Lagoon.Plaza` archived. Place saved v201 before 3a.
- `TownT2.Phase3a.CorePlatform_Fill` (996 grass blocks, Y 0..8.5) + `CorePlatform_Edge` (762 Limestone strips, 1 stud
  wide, Y 0..8.9 = wall + 0.4 cap) on every edge that drops to a lower level. Built from a 0.5-stud grid.
- Stops at canal walls/walks (CanalsV2, east canal walls + EastWalkW at X -258.4), Z -285, X 160, the warehouse yard,
  and the plaza / Depot / Museum zones (3b). Covers the 3-stud strip of east Promenade between X -258.4 and -255.4.
- Raised: Bakery, DomedHall (+ blockout), 2 HouseC, MarketLane, BasketballCourt, ParkGardens, a bench (+8.1);
  ResNE HouseB + HouseC (+4.55).
- Archived 371: NorthHomes terrace, HomesStairs, ResNE terraces/stair/pilasters, MuseumStairs N/E/W, DepotStairs N/W,
  and Detailing trim of those stairs/terraces, of the bridge street steps, and old pilaster rings with no terrace.
- Follow-up (approved answers): save check OK (data stores slot numbers; rooms/NPC points come from plot parts).
  Plots 1/2/4 raised +3/+5/+5 (floor tops 10) with their StorageRoomSpace signs; their terraces, stairs and trim
  archived (210 parts); `PlotPodiums` 62x62 (8.5..9.8 + 0.4 cap ring). Cafe, Directory, SariSari +7.45; Pond Park
  and 10 trees +8.1. Holes filled (69 fill + 57 edge blocks). Plot 4 corner paved at +0.75 (`TownT2.Phase2`).
- `BridgeLandings`: 13 solid landings (9 wide, top 8.5) at Bridges 1-5 (both ends) and 6-8 (town end). Edge caps cut
  to 8.5 where a landing crosses them. Not done: Bridges 6-8 hillside ends, Bridge 9 (west strip, +4).
- Sulit moved -1 Z (walls now flush with the Z -285 wall).
- Railings: held until phase 8. Market-stall cluster at X -131..-123: raised with the Depot in 3b.

- Back-room supports (`PlotPodiums`, saved v205): Plot1 X 105..137 Z 30..92 (8.5..9.8); Plot2 X 136..168 Z -106..-44
  (X 160..168 solid from Y 0, edge finished in 3c); Plot4 X -217..-155 Z -303..-271 (solid from Y 0 south of Z -285,
  south face: plinth, 5 pilasters, 4 blind arches, cornice). Cap on 3 outer sides; back cap segment of each podium
  removed (T2Backup.Phase3.3a_replaced). Back-room spaces above +10 empty.

## Phase 3b: +18 plaza, +18 Depot, +26 Museum (2026-11-18, awaiting approval)
- Archived: `CanalTownBlockout.DomedHall` (35% transparent 62x26x62 blockout box), old park ring (44 RetainingWall +
  44 WallCap), park stairs (33 Step + 6 StairCheek), Depot/Museum terraces, MuseumGrandStair, 106 trim parts.
- Raised: park (Park, ParkDecor, Fountain, FoodCarts, PlazaPlatform) +12.05; Depot, ClockTower, DepotJeepney,
  DepotTricycle, Depot rooftop tree +13.75; MarketStalls +16.9 (they stood on 1.10, so +13.75 would bury them);
  MuseumBlender, Districts.Museum (CollectionPedestal), 2 museum trees +18.05; WaitingShed marker +8.1 (missed in 3a).
- `TownT2.Phase3b`: Plaza18 (circle r82, top 18, plus a thin pinch fill up to the museum wall), DepotTerrace18,
  MuseumTerrace26; 1-stud stone walls with 0.4 cap on every side.

## Phase 3c: +4 yard and west strip, streets (2026-11-18, awaiting approval)
- Before: archived the tree standing in the south canal (-198, -150). ParkSpots (16 Vector3Values) are read by no script
  anywhere in the place, so left alone.
- Raised: Warehouse + Districts.Warehouse (SupplyCounter/Desk) +1.4 (floor top 4.1); 3 yard trees +3.6.
- `TownT2.Phase3c.WarehouseYard4` (X -110..10, Z 188..300, top 4, cobblestone; wall + cap on the map edge) and
  `WestStrip4` (X 160..330, Z -285..300, top 4, grass; skips the canal, Plots 3/5/6 areas and Plot 2's support; wall + cap
  on the map edges and at Z -285). Plot 2 support stands 5.8 above the strip with its stone face and cap.
- Bridge 9: walkable from the +4 strip, steps rise 0.75 max to the 8.5 deck.
- Streets: 13 StreetV2 parts archived and rebuilt as 178 `Streets` strips (top 8.55 on the core, 4.05 on yard/west,
  0.70 south of Z -285); they stop at every wall, canal and podium, and leave the phase 4 EntranceSpine box clear.
  The two south-road parts (Z -360..-338) are kept as they are.

## Phase 4: stairs (2026-11-19, awaiting approval)
- `TownT2.Phase4`: EntranceSpine (carved into the platform, 12 platform blocks split), PlazaS/E/W, MuseumGrand,
  DepotW (+ top landing X -143.2..-131, Z 107.6..116.6 onto the Depot terrace), YardS, WestN/M/S, Plot1/2/4 door
  stairs. 0.4 x 0.8 steps (rises 0.396-0.409; door stairs 0.325), 2.4 landing after step 12, stepped stone cheeks,
  1.5-stud top apron; wall/podium caps lowered where a flight arrives. All walk-tested: max step 0.41.
- `CanalWalkStairs`: 12 stairs (11 steps, 3.6-4.8 wide) on the canal walk beside a bridge landing, rising to it.
  Skipped: Bridge 4 south bank (Pond Park LawnBase overhangs the walk), Bridges 6-8 hillside banks, Bridge 9.

- Pond Park move (requested after phase 4): NOT done - it cannot clear both the canal walk (+1) and Plot 4's podium
  within 10 studs, even with LawnBase shrunk (pond rim, SW tree, stones, flower bed hit the podium; NE bench/tree hit
  the walk). Bridge 4 south-bank walk stair still waiting on it.

## Phase 5: moved shops (2026-11-19, awaiting approval)
- Bakery -> centre (-118, -238), front -X (no turn); SariSari -> (-48, -268), turned 180 to face +X. Bottoms 8.5.
- Plot3 -> (-190, 50) and Plot6 -> (-190, -85), turned 180 (doors +X); Plot5 -> (-32, -126), turned +90 (door +Z).
  Floor tops 10.00; StorageRoomSpace signs moved with them.
- `TownT2.Phase5.PlotPodiums`: Plot3/6 podium X -221..-159 + BackRoomSupport X -253..-221 (full podium width);
  Plot5 podium X -63..-1 Z -157..-95 + BackRoomSupport X -60..-4 Z -188..-157 (exact strip width: the wider version
  clips the canal-edge wall and the Bridge 5 walk stair). Caps on outer sides. Plot3 podium corner touches the plaza
  wall by ~0.5 stud (hidden).
- Door stairs Plot3/6/5 (4 steps, 0.325 rise), podium caps cut at the top.
- West strip: 113 EastQuarter parts archived; old plot areas filled at +4 (`Phase5.WestStripFill`, wall + cap at Z -285).
- Play test (Plot1/2/4 then 3/5 parked in ServerStorage per session, all restored): Plots 3, 5 and 6 each claimed, got
  the Back Room on its support (all samples at 9.8), took a displayed item and kept it across leave/rejoin.

- Follow-up: Pond Park moved by (-55, +446) to lawn centre (-205, 251) (bounds X -231..-179, Z 225..277); ParkGardens
  slab archived. Bridge 4 south-bank walk stair built (4.2 wide).

## Phase 6: businesses (2026-11-19, awaiting approval)
- `TownT2.Phase6.Businesses`: SarapExpress (X -15.3..23, Z -326..-294, 2 floors, front -X) and TipidMart
  (X -191..-150.7, Z -335..-305, 1 floor, front +X). Placeholder blockouts (Plaster walls, ClayRoofTiles gable, Fabric
  awning, wood sign board with SurfaceGui text), attribute Placeholder = true.
- `Phase6.JeepneyTerminal`: JeepneyBay in the road's north lane X -5..40, Z -349..-338 (the spec's Z -338..-330 overlapped
  the shed spot); WaitingShed X 7..23 Z -336.5..-328.5; JeepneyStop_Entrance X 24..34; DepotJeepney in the bay along X.
- Market Lane: MarketLane slab archived; 3 market stalls at X -98.5..-89.5 (Z -256..-248, -236..-228) and
  X -70.5..-61.5 (Z -246..-238), counters facing the avenue; 5 bunting rows Z -260..-220, rope at +16, poles X -89/-71.

## Phase 7: infill (2026-11-19)
- District A (awaiting approval): `TownT2.Phase7.DistrictA`, 23 buildings (6 HouseD templates recoloured, 14 blockout
  houses, 3 blockout shops: PANCITERIA, BARBERO, SASTRE) + 5 planters; attributes Infill = true, District = "A".
  Packed on a 1-stud mask (2 off walls/objects, 3 off the Pond Park, 6 off stairs/landings/Museum/Depot/plaza,
  streets kept clear, 3-stud gaps). Footprints 12-20 wide x 12-20 deep, 2-3 floors, all bottoms at 8.5.
  HouseC template fits only as 22 x 22 and was not used; it gets an added terracotta gable when it is.

- Plot 3 moved again (approved Option 1): floor centre (87, 186), top 10, turned 180 (door -X onto lane L3).
  `Phase7.Plot3Move`: podium X 56..118 Z 155..217, BackRoomSupport X 118..150 Z 155..217, caps, door stair
  X 52.8..56 Z 180..192, forecourt (X 48..56 Z 174..184 + X 41..56 Z 184..198 + link X 35..41 Z 184..197 to District
  A's street) with 2 planters and a lamp. Old plaza-side podium/support/caps/door stair archived. Play test passed
  (back room on its support 209/209, item kept across rejoin). Its StorageRoomSpace sign sits at (101, 222.4), inside
  the edge of ResNE HouseB (non-collide marker). Freed area X -253..-159, Z 19..81 goes to District E.
- District B (rebuilt after an accidental Studio undo): lanes L2 (X 45..157 Z 252..260), L3 (X 45..52, split around the
  forecourt) + stub to the main street; 9 buildings (HouseA, HouseB, HouseC, HouseE, 4 HouseD, 1 blockout) + 6 planters.
  Saved v221 (buildings) and again after greenery.

- Plot 3 StorageRoomSpace sign (read by no script) moved to the back-room support's far edge, X 150.05..150.25,
  Z 183..189, same height. District B: 3 of the 6 planters swapped for Props.Tree copies.
- District C: 8 buildings, all templates (3 HouseA, 3 HouseD, HouseC, HouseE): canal-front row X 79..151 Z -33..-12
  (6-stud walk kept along the canal edge), X 45..61 Z -89..-70 on the street, south band X 46..147 Z -149..-121 facing
  District D's street. Garden pocket X 140..158 Z 37..90 (3 trees + 2 planters) + 2 trees + 2 planters by the buildings.
  The infill mask now also blocks the canal channel and every non-platform cell (2-stud margin).

- District D: lanes D1 (X 20..157, Z -260..-253, behind the Domed Hall) and D2 (X 150..157, Z -253..-174, links the
  WestS stair top and D1 to the street). 13 buildings: 7 HouseD facing D1 (X 14..144, Z -280..-261), HouseE
  (X 115..144, Z -205..-177) on the street, HouseC + HouseD facing D2 (X 127..149, Z -251..-210), shop X 46..60 on the
  street, 2 blockout houses in the west block (X 28..48). Domed Hall apron X 63..113, Z -188.6..-168.6 kept empty; it
  opens straight onto the street. Greenery: 3 existing trees + 2 new trees + 2 planters. Saved v226 / v227.
- Left open for phase 8 greenery and benches: District C canal-end slot X 66..79 and the thin strip by Plot 2.

- Ground: all 1,077 core platform blocks and the Depot terrace top switched from grass to the street Cobblestone in a
  lighter tone (streets keep their darker tone). Green kept: Pond Park lawn, planters, the District C garden pocket and
  18 grass discs under trees (`TownT2.GreenPatches`, thin non-collide patches at 8.47..8.52). West strip stays grass.
  Saved v228.
- New infill rules from District E on: lots 10-30, 2-stud gaps, 2-row blocks with lanes/courtyards, 3-4 floors within
  120 of the plaza centre, fillers, 30+ buildings per full district.
- District E: street Street_EN (X -255.4..-162, Z 43..58, continues the X -162..-125 street), lanes EL1 (Z 12..18),
  EL2 (Z -42..-36, from the Bridge 7 landing), Lane_Link (X -214..-208, Z -42..43), square X -208..-183.6 Z -12..12 at
  the foot of PlazaE. 26 buildings (25 blockouts, 1 HouseD; 15 x 2 floors, 7 x 3, 3 x 4) + 8 kiosks along EL2 + a garden
  wall; courtyard X -255..-237 Z -21..-3. Square: 3 trees + 1 planter at the corners, 2 benches. Greenery 4 trees +
  8 planters in all. Archways did not fit (pillar spots fall in building gaps). Saved v229 / v230.

- District F: lanes F1 (X -235..-229, Z -278..-187), F2 (X -235..-195, Z -187..-181, meets the street), F3
  (X -137..-131, Z -278..-189) + F3 link to the street's south-east end (X -148..-131 Z -189..-185 and
  X -148..-142.5 Z -185..-181; only flush 8.5 wall caps under it). 13 buildings (11 blockouts, 2 HouseD): 5 west of F1,
  1 east of F1, 2 facing F2, 2 facing the street in front of Plot 4, 3 facing F3; 8 kiosks (6 along the 8-wide strip
  east of F1, 2 facing F2); greenery 2 trees + 7 planters (+1 existing tree). Plot 4 and its supports fill most of F.
  Saved v233 / v234.

- District G (+4 west strip): paths P1 (X 238..244) and P2 (X 305..311), each split at the canal (north Z 39..297,
  south Z -277..-4), and E-W paths Z 143..149 and Z -167..-161 linking them to the street at X 190..206. 47 homes, all
  templates (34 HouseE, 7 HouseA, 5 HouseD, 1 HouseC), 2-stud gaps, rows on both sides of the street and both paths.
  65 garden lots = 35% of lot area (28 houses converted: all blockouts + 5 HouseD), each with a hedge + gate, a flower
  bed and a tree. Canal (+2) margin, Bridge 9, WestN/M/S stairs, Plot 2's support and the map-edge wall kept clear.
  Saved v235 / v236.

- District G tweak: the 34 HouseE copies recoloured (walls cream/ochre/peach/pastel blue/mint/pink, 3 terracotta roof
  tones, 5 shutter colours, mixed flowers/trim); no two neighbours share a wall colour. Not turned or mirrored: turning
  would point fronts away from the street, and Roblox cannot mirror meshes. Saved v237.
- District H (Hill B top, +16): 19 terrace houses in 6 attached groups (2-stud gaps between groups), walls
  X -329.1..-319.3 (9.8 deep; eaves -329.9..-318.5, clear of the map-edge wall EdgeW at X -332..-330), 2-stud walk
  along the front edge, fronts +X. 10 x 3 floors, 9 x 2; six wall colours, 3 roof tones. Gaps left at the HillStairB
  arrivals: Z -60..-42, 38.5..56.5, 148..166.

- Densify pass A-D (new rules, nothing existing moved or removed; new models in `DistrictX.Densify`, attribute
  Densify = true): A +2, B +3 (1 template), C +2 (2 HouseD), D +1. The districts were already close to full under the
  2-stud / 6-stud margins; no rectangle was deep enough (26+) for a back lane, so no new lanes or kiosks were added.
  First A attempt was discarded (its mask skipped TownT2 models and overlapped existing buildings); fixed mask
  `districtMask3` marks every TownT2 model +2. Found: District C's HouseD from the first fill (X 45..61, Z -89..-70) now
  stands at X 30..46, Z -145..-127 (moved outside this pass); left as found. Saved v240-v243.

- District I (south waterfront park, X 40..325, Z -398..-290): `JeepneyRoundabout` centre (125, -349), carriageway
  r 17 (top 0.74), island r 6.5 with 3 palms, drive circle r ~11 (phase 9); `BarangayCourt` slab X 49..103 Z -334..-302,
  full court 47x25 with lines/keys/2 hoops, 3-tier bleachers on the north side, roof on 6 posts; `LagoonPromenade`
  X 41..48 Z -396.5..-361 (kerb, 3 benches, 3 lamps); 8 road buildings (KAPEHAN, CARINDERIA, LUTONG BAHAY, MERIENDA +
  4 homes, 1-2 floors) at X 50..96 / 146..188; `Playground` X 222..250 Z -332..-304; `PicnicArea` 4 tables X 269..299
  Z -375..-347 with 4 trees; 7 more trees + 2 palms. BasketballCourt marker archived. South road unchanged. v244/v245.
- Roof pass: 174 infill roofs (A-I) spread over bright terracotta / dark clay / brown / faded orange; no building's
  nearest neighbour shares its tone. v246.
- Edge check: District H (furthest east X -329.90), hillside BlenderHouses (X -315.52) and a sweep of 965 building
  models are all inside X -330..330, Z -400..300. Nothing moved.

- Stray District C HouseD archived (OldLayoutArchive); a tree in its spot at (38, -134). v247.

## Phase 8: greenery + safety (2026-11-19, awaiting approval)
- `TownT2.Phase8.Railings`: 1,133 Limestone balustrades (2.6 tall, collision on) on every capped wall strip with a
  drop over 2 (core edges 736, plaza 372, Depot/Museum, west strip/yard/fill walls, 8 back-room support caps) + 4 runs on
  Hill B's front edge. Gaps where caps were lowered for stairs/landings/door stairs (110 strips) and at the 3 HillStairB
  arrivals; podium caps (drop 1.3-1.7) skipped. Walk checks on all flights, bridges and stair tops still pass. v248.
- `Phase8.Decor`: Market Lane palms 4/8 (X -101 Z -262/-250, X -59 Z -250/-226; the other spots hit stalls/SariSari),
  6 route palms up the street to PlazaS; Museum terrace statue + 8 planters + 4 benches + 8 lamps; Depot terrace fountain
  + 3 benches + 7 planters + 9 lamps; 4 plaza-ring benches (planters did not fit between the park decor); 15 stair-end
  planters; 314 wall-cap lamps (~16 apart); reserved slots 11 benches + 13 planters + 7 lamps.
- Performance: 2,635 decor parts CanCollide/CanTouch/CastShadow off (104 meshes Box collision); balustrades keep
  collision, shadows off. Canal walks already have rails, so none added there. v251.
- Performance fixes (v252): no Seat/VehicleSeat/ProximityPrompt/ClickDetector was inside the decor pass (food carts,
  pedestal, kiosks, court, bleachers were never touched) and no script references the decor folders, so 0 touch
  restores. Collision back on 628 bumpable decor parts (bench seats/backs, planter boxes, tree and palm trunks, lamp
  poles/bases on the ground, fountain basin/column/bowl, statue, playground and park play equipment, picnic tables,
  bunting poles); flowers, canopies/leaves, lamp heads, bunting, signs, trim and grass patches stay non-collide.
  Lights: only 3 light objects in Workspace (2 in Plot1, 1 in the Museum); shadows off, the one over range 16 capped.
  The 851 lamp heads glow Neon at night via LightingController, whose runtime pool of 10 PointLights (range 16, no
  shadows) follows the lamps nearest the camera.

## Phase 9: jeepneys, entrance level (2026-11-19, awaiting approval)
- `TownT2.Transit`: JeepTurnaround paving (disc r 15 at (-238, -345); the road east of X -255 runs into the east canal
  walk at +4, so the loop could not sit at X -265); 98 waypoints JeepPath_001..098 (<= 12 apart, ~2.6-2.9 on curves),
  north lane Z -343.5 westbound past the bay (stop JeepPath_021, StopSeconds 8), roundabout r 11, south lane Z -354.5
  eastbound, turnaround r 10. Jeepneys/Jeepney1 (was CanalTownAssembly.Transport.DepotJeepney) + Jeepney2 (red/yellow
  copy): PrimaryPart Root, 8 Seats (CanTouch off), BoardingPoint.SakayPrompt, Root.Horn (Creator Store "Car Horn"
  127513531122725), body CanCollide/CanTouch off.
- `src/Server/Services/JeepneyService.luau` (+ Main ORDER). Play test: full lap 68 s + 8.6 s stop, jeeps half a lap
  apart, rider stays seated, jump off at the bay drops the rider on the kerb 6.4 from the shed, jeep stops 4.9 studs
  short of a standing player and resumes, smooth on the client. v256.

## Notes for later phases
- **Phase 9:** the jeepney turnaround is `TownT2.Phase7.DistrictI.JeepneyRoundabout`.
- **Phase 9:** DepotJeepney becomes moving jeepney #1; its stop is the bay X -5..40, Z -349..-338. No jeepney stays
  parked in the lane.
- **Phase 4 (replaces earlier numbers):** EntranceSpine stair X -87..-71 (16 wide), Z -285..-267.4, +0.75 -> +8.5,
  19 steps with a landing, up +Z, between Sulit (east edge X -87.3) and Kainan (west edge X -70.25). Keep the square in
  front of it clear.
- **Phase 3:** after the Plot 4 terrace is archived, pave its corner (X -200..-154, Z -302..-285) at +0.75 and run the
  +8.5 retaining wall along Z -285 across it.
- **Phase 7:** Hill B top level (X -330.7..-317.3, Z -95.7..180.7, +16) gets a row of narrow terrace houses, no deeper
  than 12 studs, fully inside the baseplate, to keep the hillside skyline.
- **Phase 3:** the whole central park rises +12.05 as one unit (lawn 6.05 -> 18.1), moat footbridges included.
