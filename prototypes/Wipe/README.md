# Isolated Wipe prototype

Owner: Dwayne (Dev 2). Source: `PointerInput.luau`, `SpotClear.luau` and
`WipeTest.local.luau` in this folder. Test place: separate `WipePrototype.rbxl`.

Completion means **Wipe complete only**. This prototype uses no production state,
remotes, rewards, XP or saving. It does not establish that the production
restoration loop works. A configured multi-step item must finish its whole recipe
on the server before becoming Restored; this prototype cannot do that.

## Studio setup

1. Open a separate empty Baseplate place and save it locally as
   `WipePrototype.rbxl`. Keep production Script Sync disconnected; do not link
   this place to `src/`. Leave Studio API Services disabled.
2. Do not copy production scripts into the test place. The runner is Studio-only
   and refuses the production place ID, `ReplicatedStorage.Shared`,
   `ReplicatedStorage.Remotes`, or `StarterPlayerScripts.Client`.
3. Build the model below in Workspace. Names and capitalization must match.
   Set the model's `PrimaryPart` to `Base`, and leave `Archivable` enabled on
   the model and its contents. The item must contain no scripts.

```text
Workspace
└── WipeTestItem (Model; PrimaryPart = Base)
    ├── Base (Part)
    └── DirtSpots (Folder)
        ├── Dirt1 (Part)
        │   └── Dirt (Decal)
        ├── Dirt2 (Part)
        │   └── Dirt (Decal)
        └── Dirt3 (Part)
            └── Dirt (Decal)
```

Use these example properties for a simple fixture:

| Object | Properties |
|---|---|
| Base | Size `10, 1, 6`; Position `0, 4, 0`; Anchored `true`; Transparency `0` |
| Every spot Part | Size `2, 0.1, 2`; Anchored `true`; Transparency `1`; CanCollide `false`; CanTouch `false`; CanQuery `true` |
| Dirt1 / Dirt2 / Dirt3 | Positions `-3, 4.56, 0` / `0, 4.56, 0` / `3, 4.56, 0` |
| Every Dirt Decal | Face `Top`; Transparency `0`; Texture set to a visible test image |

**Any visible test image can be used for the dirt decals**; it does not need to
look like dirt. Use an image that loads in the test place. An empty Texture makes
the cleaning effect invisible. Spot Parts sit just above the body's surface;
the code fades their decals, not the body.

The runner counts direct child Parts of `DirtSpots`; it requires at least one.
Spot names can vary, but each spot must have its own direct child Decal named
`Dirt`. Do not nest the spot Parts in additional folders. All item parts must
be anchored. Keep the fixture small and its spots separated and visible from
above. Move the SpawnLocation away from it, for example to `20, 1, 0`.

4. Under `StarterPlayer → StarterPlayerScripts`, create a Folder named
   `WipePrototype`. Manually paste the complete source files into these scripts:

| Studio location inside WipePrototype | Class | Source file |
|---|---|---|
| PointerInput | ModuleScript | `PointerInput.luau` |
| SpotClear | ModuleScript | `SpotClear.luau` |
| WipeTest | LocalScript | `WipeTest.local.luau` |

Install exactly one runner. Do not use a Script with Client RunContext. No server
script or prebuilt GUI is needed; the runner creates temporary test UI and a
local item clone.

5. Open Output and press Play. Press Start, then hold the mouse button or a
   finger over the dirt and drag between spots. Each spot takes about 1.5 seconds
   of contact. The bar, percentage and cleared-spot count show progress.
6. Exit discards test progress, restores the original dirty fixture and camera,
   and detaches wiping input. Start begins a fresh run. Restart replaces the
   active clone and resets all spots and progress. After completion, the cleaned
   clone remains visible until Exit, Start or Restart.

With DEBUG enabled, Output includes `[WipeTest] started`,
`[WipeSpotClear] ready: N spots`, cleared counts and a local-step completion
message. Invalid fixture setup produces a `[WipeTest]` warning explaining the
problem and a setup-error message in the UI.

## Reported test results

Attribution: the following Studio interaction results were supplied by Dwayne
for this documentation update, from the separate `WipePrototype.rbxl` place.
They were not rerun during this documentation task.

| Check | Reported result |
|---|---|
| Mouse wiping | Dirt clears; completion occurs after all spots clear. |
| Exit midway | Dirt and camera restore; wiping stays disabled until Start. |
| Starting again and Restart | Passed. |
| iPhone 17 Pro emulation | Touch wiping, Start, Restart and Exit passed in landscape and portrait. |
| Roblox menu | Opening stops wiping; closing requires a fresh press to resume. |
| One-spot and five-spot fixtures | Counts are correct and both fixtures complete. |
| Missing Dirt decal | Explanatory setup error; no run starts or completes. |
| Fixture restoration | Variations were made during Play only; the original three-spot fixture was restored and verified. |

Dwayne separately confirmed manually that switching away from Studio stops
wiping, and returning requires a fresh mouse press.

## Pending checks and integration

- Physical-phone testing; emulator results do not establish physical-device behavior.
- Another teammate's playtest.
- Production restoration integration and agreed server acknowledgements,
  including rejection, pending cancellation and late acceptance.

Production integration is a separate milestone. This test runner must not award
completion rewards or be connected to Sean's production Restore buttons.
