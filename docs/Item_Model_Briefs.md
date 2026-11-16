# Item model briefs (all 26 items)

How to read: **Method** = which Blender helper in `tools/blender/common.py` fits best (lathe = solid of revolution, tube = tapered Bezier pipe, box, sphere, torus). **Parts** = Blender objects to make (one per colour group, exact names). **Restore parts** = what the recipe (see `src/Shared/Config/Items.luau`) needs: the Replace/Reassemble part name becomes a Socket + LooseParts pair named `<Part>1` (the wrapper adds them; just model the object WITHOUT that part, or model it and name it `<Part>1`). Colours from `PALETTE` in `common.py` or the item colours in `docs/Blender_Pipeline.md` section 6. Status: DONE = in the game as a real model; PILOT = script exists, import + wrap pending; TODO.

Style target: smooth, soft bevels, clean silhouette, 3,000 to 5,000 triangles, about 1.6 to 2.2 studs wide. See `tools/blender/kettle_hq.py` for the quality bar.

## Tier 1 (Starter crate)
| Id | Name (rarity) | Method | Parts | Restore parts | Status |
|---|---|---|---|---|---|
| RubberDuck | Rubber Duck (C) | by hand | Body, Head, Beak, Eyes, Tail | Wipe, Polish | DONE (Dwayne) |
| Teacup | Floral Teacup (C) | lathe + tube | Body, Saucer, Handle, Rim, Trim, Flower, Leaf | Wipe, Polish | DONE |
| ToyCar | Toy Race Car (C) | box + lathe wheels | Body (rounded), Cabin, Wheel x4 (one is the Replace part), Stripe, Spoiler | Reassemble `Wheel` | TODO |
| SpinningTop | Spinning Top (C) | lathe | Body, Cap, Stem, Tip | Wipe, Polish, Test | TODO |
| SlimeJar | Slime Jar (C) | lathe | Jar (glass), Slime (green, wobbly top), Lid | Wipe, Polish, Test | TODO |
| StickerAlbum | Sticker Album (C) | box | Cover, Spine, Pages, 3 Stickers | Wipe, Polish | TODO |
| AlarmClock | Alarm Clock (U) | lathe + torus | Body (round), Face, Hands, Bell x2, Feet | Reassemble `Bell` | TODO |
| SnowGlobe | Snow Globe (U) | lathe + sphere | Globe (glass sphere), Base (lathe), Snowflakes, tiny tree | Wipe, Polish, Test | TODO |
| PlushBunny | Plush Bunny (U) | spheres + tube | Body, Head, Ears, Tail, Eyes | Replace `Eye` | HARD (soft shape): try spheres with subsurf, or ask |
| PocketCompass | Pocket Compass (U) | lathe | Case, Ring, Face, Needle, Lid hinge | Wipe, Polish, Test | TODO |
| MusicBox | Music Box (R) | box + lathe | Box (rounded), Lid, Dancer figurine, Key, Comb | Reassemble `Dancer` | TODO |
| InstantCamera | Instant Camera (R) | box + lathe | Body, Top, Lens (lathe), Flash, Viewfinder, Stripe | Replace `Lens` | TODO |
| TinRobot | Sir Clank, the Tin Robot (E) | box + lathe | Head, Body, Arms, Legs, Antenna, Eyes, Key | Reassemble `LeftArm` | TODO |
| CopperKettle | The Brass Baron Kettle (E) | lathe + tube | Body, Lid, Knob, Bands, Spout, Handle, Rivets | Reassemble `Lid` | PILOT (`kettle_hq.py`) |
| Gramophone | The Silver-Tongue Gramophone (L) | box + lathe + tube | Base box, Turntable, Horn (big flared lathe), Arm, Crank | Replace `Horn` | HARD |

## Tier 2 (Flea Market crate)
| Id | Name (rarity) | Method | Parts | Restore parts | Status |
|---|---|---|---|---|---|
| VinylRecord | Vinyl Record (C) | lathe | Disc (grooves via rings), Label, Sleeve | Wipe, Polish | TODO |
| EnamelMug | Camp Mug (C) | lathe + tube | Body, Rim, Handle | Scrape, Polish | TODO |
| LunchBox | Lunch Box (C) | box | Box, Lid, Handle, Latch, Sticker | Scrape, Polish | TODO |
| RotaryPhone | Rotary Phone (U) | box + lathe + tube | Body, Handset, Dial (ring with holes), Cord | Reassemble `Handset` | TODO |
| LavaLamp | Lava Lamp (U) | lathe | Foot, Glass, Cap, Blobs | Replace `Bulb` | TODO |
| PocketWatch | Pocket Watch (R) | lathe + torus | Case, Face, Hands, Crown, Chain | Replace `Gear` | TODO |
| Boombox | Boombox (R) | box + lathe | Body, Speakers x2, Tape window, Handle, Dials | Replace `Dial` | TODO |
| PixelBrick | The Pixel Brick (E) | box | Body, Screen, D-pad, Buttons, Speaker grill | Reassemble `Button` | TODO |
| Jukebox | The Midnight Neon Jukebox (L) | box + tube + lathe | Cabinet, Arch top, Glass, Record, Speaker, Neon tubes | Replace `Record` | HARD |
| StarlightOrrery | Starlight Orrery (Relic) | lathe + torus | Base, Arms, Sun, Planets, Rings | Reassemble `Ring` | TODO |
| GoldenCartridge | The Golden Cartridge (Relic) | box | Body, Label, Grip ridges, Pins | Replace `Chip` | TODO |

## Finishing an item (see `docs/Blender_Pipeline.md`)
1. Script + run + LOOK at the preview, iterate. 2. Import the `.glb` (Home > Import 3D). 3. Edit `CONFIG` in `tools/studio/WrapImportedItem.luau` (item id, colours by part name, polish parts, spots, sockets) and run it in the Command Bar. 4. Save, Play, restore it. 5. Tick the status in this file.

Split suggestion so two people do not collide: Dwayne takes the top half of each tier table, Ace the bottom half; whoever finishes an item changes its Status in this file and pushes.
