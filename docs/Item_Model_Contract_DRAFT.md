# Item Model Contract — draft for Ace and Sean

Owner: Dwayne (Dev 2). Status: Ace's review complete; Sean approved the model contract and placement requirements in the team handoff on 2026-11-16. Later-interaction details noted below remain open.

This expands the outline in `01_GameDesign.md` §C2 for review. It does not replace
that design or change any shared code. The first build will be a Wipe-only item
in a separate test place, before integration into the main game.

## First prototype: Wipe only

```text
WipeTestItem (Model; PrimaryPart = Base)
├── Base (Part)
└── DirtSpots (Folder)
    ├── Dirt1 (Part)
    │   └── Dirt (Decal)
    ├── Dirt2 (Part)
    │   └── Dirt (Decal)
    └── Dirt3 (Part)
        └── Dirt (Decal)
```

- `Base` is the item's main body and the model's PrimaryPart.
- `DirtSpots` contains the small parts the pointer can hit to clean the item.
- Each spot has one dirt decal. Wiping fades the decal from Transparency 0 to 1;
  it does not fade or remove the item's body.
- Spot parts sit just above the body's visible surface, with the decal facing
  outward. The parts themselves are transparent; the decals provide the dirt.
- All parts are anchored. Spot parts have CanCollide = false and CanQuery = true
  so they do not block movement and can still be detected by the pointer raycast.
- `Dirt1`, `Dirt2`, and `Dirt3` are proposed unique example names; the code should
  read the folder's spot parts rather than expect exactly three spots.
- The decal name `Dirt` is a proposed clarification for review, not an existing
  agreed requirement. The existing design specifies a dirt Decal but no name.
- `WipeTestItem` is a test fixture name, not a new shared Config item ID.

## Full item structure for later interactions

These top-level names already appear in the game design. Only include the
folders and parts needed by that item's restoration recipe.

```text
<ItemId> (Model; PrimaryPart = Base)
├── Base (Part)
├── DirtSpots (Folder)       — Wipe: spot Parts with dirt decals
├── RustSpots (Folder)       — Scrape: spot Parts with rust visuals
├── Sockets (Folder)         — Reassemble/Replace: invisible target Parts
├── LooseParts (Folder)      — Reassemble/Replace: movable Parts or Models
├── PolishSurfaces (Folder)  — Polish: Parts whose appearance changes
└── TestPoint (Part)         — Test: position for the timing interaction
```

- Names are case-sensitive: use `DirtSpots`, not `Dirtspots` or `Dirt Spots`.
- Real item model names match Ace's existing item/model IDs. Their eventual
  location is `ReplicatedStorage/Assets/Items/<ItemId>`.
- Socket and loose-part names match exactly, for example `Sockets/Wheel` and
  `LooseParts/Wheel` for ToyCar. Use Ace's final Config part names (such as
  `Wheel` and `LeftArm`), with no added digits. Socket targets remain queryable
  even when invisible.
- The existing design allows an optional NumberValue named `Layers` on rust spots.
  Rust texture names and placement transforms for assembly still need agreement
  before those interactions are implemented.
- Parts remain anchored; assembly will use tweens rather than physics.
- Keep each item at or below 60 parts, following the architecture's mobile limit.
- Models contain visuals and interaction targets. Ownership, value, quality,
  inventory state, and saving remain controlled by server systems.

## Production placement and visibility requirements

Sean's approved requirements apply to production items, not the larger isolated
Wipe/Polish fixtures:

- `Base` is the PrimaryPart and the lowest part of the item. No visual or target
  extends below its bottom face.
- Model pivot is at `Base`'s centre. The model front follows its LookVector
  (local negative Z); keep that convention when placing it at an ItemAnchor.
- Maximum approximate footprint is 2.2 by 2.2 studs. Shelf pads are 2 by 2 studs,
  spaced 2.5 studs apart; pedestal tops are 2 by 2 studs. Keep the item centred.
- Dirt spots must be visible and pointer-reachable from the minigame camera
  angle. Check occlusion by the item's own parts and the bench scene, including
  rotated plots. A matching name alone does not establish visibility.
- Production polish must preserve the item's intended colour/material identity.
  The isolated Polish prototype's silver/Metal finish is test feedback only.

## RubberDuck model milestone

The existing Config ID/model name is `RubberDuck`, with recipe Wipe then Polish.
Build and validate a candidate in the separate unsynced test place before
installing it at `ReplicatedStorage/Assets/Items/RubberDuck` in the shared place.
Use an anchored `Base`, visible duck body parts, `DirtSpots` with queryable
transparent carrier Parts and `Dirt` decals, and visible queryable
`PolishSurfaces`. Use a valid available dirt image; never invent an asset ID.
Keep all parts within the placement limits above and retain the yellow duck
appearance when polishing. No scripts, remotes, player state or rewards belong
inside the model. Candidate construction and runtime integration are separate
from the already-tested large prototype fixtures.

Candidate built on 2026-11-16 at `Workspace.RubberDuck` in the separate local
`WipePrototype.rbxl` place, not the shared game. Codex inspected it through Studio
MCP in Edit mode: 12 anchored parts, bounds approximately 1.65 x 1.824 x 1.97
studs (X/Y/Z), no part below Base, Base-centred pivot, front local negative Z,
three queryable dirt carriers each containing a `Dirt` decal, and four visible
PolishSurfaces (Body, Head, LeftWing, RightWing). All three dirt carrier centres
were first hits in item-only raycasts from a camera 4.4 studs above and 5.5 studs
in front of Base. A screenshot was visually inspected for the yellow silhouette.
This centre-ray check is not full touch-target coverage or a shared-bench test.

Dirt currently uses the existing built-in SpawnLocation test image, tinted brown;
it is placeholder artwork, not approved production dirt. No image was uploaded.
No scripts were placed inside the model and neither prototype runner was changed.
Codex subsequently tested mouse Wipe and Polish separately on temporary candidate
clones during Play, using the unchanged existing runners/modules and an explicitly
positioned front/above camera. Wipe cleared all three decals and completed; some
holds needed repeating, so this is not a wipe-speed or touch-target-size signoff.
For the separate Polish run, dirt decals were hidden and carrier CanQuery disabled
on the runtime clone only; all four polish surfaces were accepted and rubbing
completed with local score 100. The unmodified Polish prototype changed the clone
to silver/Metal: that is a known appearance mismatch, not a pass for the required
yellow-preserving production finish. The two runs were not a connected recipe or
server integration test. After Stop, the yellow candidate and original fixtures
were verified; runner enablement returned to Polish-only. No source changes.

RubberDuck is installed at `ReplicatedStorage.Assets.Items.RubberDuck` in the
shared place. Ace confirmed its structure, as reported in the team handoff.
Production end-to-end testing is still pending, including Bench1/Bench2 framing,
landscape touch, yellow-preserving polish and bright-town readability. Final dirt
art approval remains separate.
Save the separate place in Studio to preserve the model; this document does not
contain an exported model asset.

## Review record and open details

- **Ace:** review complete in `STATUS.md` under "Review notes for Dwayne".
  The item/model ID connection and Wipe structure fit the planned integration;
  the socket example above now uses the final part name. No shared Config,
  Types, or Remotes changes are needed for this prototype.
- **Sean:** approved Base as PrimaryPart for display placement; supplied the
  scale, orientation and pivot requirements recorded above. His Wipe code review
  is complete; his teammate playtest is still pending a reported result.
- **Still open:** rust texture naming and assembly placement transforms before
  those interactions are implemented; final production RubberDuck appearance and
  polish tuning need verification with the actual model.

The isolated Wipe fixture has been built and tested; see `STATUS.md` and
`../prototypes/Wipe/README.md` for evidence and remaining checks. Polish is
partially verified separately. Those results do not verify a production item
model or the production restoration loop.

## Production adapter implementation (2026-11-16, local only)

The five Dwayne-owned client modules and their Main registration are implemented
without modifying the prototype files or Ace's runner. Polish preserves the
model's original colour/material; the disposable view disables completed dirt
carriers before Polish, including saved-step resume. Studio Edit syntax and
isolated module/adapter checks passed; real input/camera/server integration
remains untested. RubberDuck is installed in the shared Items folder and Ace
confirmed its structure (team-reported evidence, not a new Codex runtime test).
The original candidate is retained. The adapters now register the shared view
provider contract from Ace's committed 7bb90ad hook: model, attachPointer and
idempotent cleanup. The pending branch merge still targets 1551c1f; newer main
must also be merged before these provider-based adapters can initialize.
