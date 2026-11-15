# Item Model Contract — draft for Ace and Sean

Owner: Dwayne (Dev 2). Status: proposed; Ace's review complete, awaiting Sean's review.

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

## Review requested

- **Ace:** review complete in `STATUS.md` under "Review notes for Dwayne".
  The item/model ID connection and Wipe structure fit the planned integration;
  the socket example above now uses the final part name. No shared Config,
  Types, or Remotes changes are needed for this prototype.
- **Sean:** confirm that using `Base` as PrimaryPart fits bench and display
  placement. Agree on item scale, orientation, and pivot placement with Dwayne
  before building production item models; these are not standardized here yet.
- **Both:** review the proposed spot/decal naming and query settings above.

After review: build one anchored Wipe test item in a separate baseplate, then
implement and test mouse and touch cleaning. Ace has reviewed this draft;
Sean's review is still pending. No Studio setup or playtest has been performed for it.
