# Isolated Polish prototype

Owner: Dwayne (Dev 2). **Studio tests: partially verified; see results below.** This folder adds `Rub.luau`
and `PolishTest.local.luau`; reuse [Wipe's PointerInput](../Wipe/PointerInput.luau)
unchanged. No production modules, remotes, player state, rewards, XP or saving.
Completion means a local Polish step only, never a Restored item.

## Separate test place and runner selection

Use the separate unsynced test place, not the production place. Leave Studio API
Services disabled and production Script Sync disconnected. This runner refuses
the production place ID and production Shared/Remotes/Client folders.

Stop Play before changing runner settings. Under StarterPlayerScripts:

- To test Polish: disable the existing `WipeTest` LocalScript (set Enabled=false,
  or Disabled=true if that is the property shown). Enable `PolishTest`.
- To test Wipe later: stop Play, disable `PolishTest`, then enable `WipeTest`.
- Never enable both runners in one Play session. Polish checks for an enabled
  runner named WipeTest/another PolishTest and for the existing Wipe test GUI.

Do not edit/delete the Wipe scripts or `Workspace.WipeTestItem`. Disabling its
runner for the test is sufficient. Polish only clones/restores PolishTestItem.

## Test model

Build a new model separately from the existing Wipe fixture:

```text
Workspace
└── PolishTestItem (Model; PrimaryPart = Base)
    ├── Base (Part)
    └── PolishSurfaces (Folder)
        ├── Surface1 (Part)
        └── Surface2 (Part)
```

| Object | Example properties |
|---|---|
| Base | Anchored=true; Size `10, 1, 6`; Position `16, 4, 0`; Transparency=0 |
| Both surfaces | Anchored=true; Size `3, 0.1, 3`; Transparency=0; CanQuery=true; CanCollide=false; CanTouch=false |
| Surface1 / Surface2 | Positions `14, 4.56, 0` / `18, 4.56, 0` |
| Surface appearance | SmoothPlastic; Reflectance=0; medium grey, e.g. RGB `90, 100, 110` |

Keep Archivable=true on the model and all descendants. No scripts inside the
model. Surfaces must be direct child BaseParts of PolishSurfaces, at least one;
their names may vary. Keep them non-overlapping, visible from above, with a gap
between them. They are opaque surfaces, not Wipe's transparent decal carriers.
No image or decal is required. Keep the character away from the new model; use
a SpawnLocation away from both fixtures if making a new test place.

## Manual script installation

Under `StarterPlayer → StarterPlayerScripts`, create Folder `PolishPrototype`:

| Name | Class | Paste complete source from |
|---|---|---|
| PointerInput | ModuleScript | `prototypes/Wipe/PointerInput.luau` (unchanged copy) |
| Rub | ModuleScript | `prototypes/Polish/Rub.luau` |
| PolishTest | LocalScript | `prototypes/Polish/PolishTest.local.luau` |

Install one runner only. No server scripts, production Main or manual GUI are
needed. Open Output, press Play, then Start. The runner frames the Polish model
and builds temporary progress, Start, Restart and Exit controls. If changing
orientation during Play leaves poor framing, press Restart to frame again.

## Movement, shine and score

Hold and rub over the visible surfaces. Holding still gives no progress. Rub
discards the first rendered sample after each press, each re-entry, a switch
between surfaces, or a viewport-size change. Invalid hits (including the test UI
panel) clear the baseline. The next valid sample establishes a new one without
crediting travel outside the surface. Menu/focus loss requires a fresh press.

Progress is shared across all surfaces. Reflectance moves from its original
value toward 0.3, colour moves toward silver as explicit test feedback, and
Material becomes Metal at completion. A grey starting colour makes the change
visible even under lighting where reflections are subtle.

`TEST_ONLY_MOVEMENT` in the runner contains all prototype tuning:

| Setting | Value | Meaning |
|---|---|---|
| requiredTravel | 2 | Sum of credited screen movement divided by viewport short side |
| minSampleTravel | 0.0005 | Ignore smaller movements/jitter |
| maxSampleTravel | 0.08 | Reject larger single-sample jumps entirely |
| maxCreditPerSample | 0.02 | Cap credit per rendered sample |

There is no time-based progress or upgrade multiplier. These sample limits can
make fast/low-frame-rate rubbing slower; they are test tuning, not production
balance or anti-cheat. Input is sampled each rendered frame: excursions away
and back between samples cannot be reconstructed. Large sampled jumps are
rejected; this prototype does not prove continuous contact between samples.

Completion calls the local callback once with score 100, matching GameDesign B8.
No speed bonus, penalty, quality stars or production tool rules are invented.
Ace must agree production movement tuning, existing polishSpeedMult use, the
4-second server minimum and acknowledgement/retry behavior before integration.

Exit discards progress and restores the original Polish fixture and camera.
Start after cancellation/completion and Restart create a fresh dull clone.
Completion leaves the shiny clone visible until a new run or Exit. The unchanged
input adapter prints `[WipePointerInput] attached/detached` even for Polish;
Rub/runner messages use `[PolishRub]` and `[PolishTest]`.

## Studio results and remaining checks

Codex exercised the isolated `WipePrototype.rbxl` place through Studio MCP on
2026-11-15, using mouse input and iPhone 17 Pro emulated touch. Dwayne confirmed
saving the model/script setup. These results do not verify production restoration.
Temporary invalid-fixture changes and diagnostic observers existed only during
Play; after Stop, both original fixtures were checked. No prototype source fix
was made during these checks. Each row states the observed scope, rather than
assuming the whole original checklist passed.

| Check | Exact action and expected result | Status |
|---|---|---|
| Start/initial press | Start and hold without moving. Travel remains 0.000. | Passed: mouse and emulated touch. |
| Movement | Rubbing advances progress and surface reflectance to 0.3. | Passed: mouse, landscape touch, fresh portrait touch. |
| Stationary | Holding still for 5 seconds gives zero progress; pausing after re-entry also leaves shine unchanged. | Passed within the tested runs. |
| Outside/re-entry | Dragging wholly over Base or empty space gives no progress; rubbing after re-entry advances. | Passed for invalid regions and stationary return. Exact entry-sample credit remains unverified. |
| Surface switch | Moving between surfaces can earn legitimate progress while traversing their valid portions. | Exact switch-sample jump suppression remains unverified; automated movement did not isolate it. |
| UI | Dragging wholly over the feedback panel gives no progress. | Passed with mouse. Full touch boundary/re-entry coverage pending. |
| Completion | Rubbing reaches local score 100 and a completion message; reflectance reaches 0.3. | Passed: mouse and emulated touch. Further-input and repeated-callback stress checks pending. |
| Exit/Start | Exit removes active clone, restores original fixture and Custom camera; subsequent Start runs. | Passed for tested runs. Explicit midway Exit and disabled-input-after-Exit checks pending for Polish. |
| Restart | Restart after completion resets progress, SmoothPlastic material and reflectance 0. | Passed: mouse and both phone orientations. Five-repeat speed/callback check pending. |
| Menu | Open menu with pointer held, move, close and move again without a new press: shine stays fixed; fresh press and rubbing advance. | Passed with mouse. |
| Focus loss | Switch to another window while rubbing and return; require a fresh press. | Pending for Polish; Wipe's separate focus result is not reused as a Polish pass. |
| Touch | iPhone 17 Pro landscape and fresh portrait: rubbing, holding still, Start, Restart and Exit. | Passed for listed actions. Second finger, boundary detail and physical phone pending. |
| Live rotation | Rotate during Play, then rub using current coordinates. | Passed in controlled retest; initial intermittent stall remains unexplained. See note below. |
| Counts | Exit first so the original is visible; use Play-only client edits to try one and several surfaces, then Start. Count matches; shared shine updates all valid surfaces. Stop Play to restore the original two-surface fixture. | Pending |
| Bad fixture | Play-only client edits: missing/empty PolishSurfaces or Surface1.CanQuery=false. | Passed: explanatory warnings, setup error, no active session/false completion; original properties restored after Stop. |
| Preservation | Check originals after Stop; leave Wipe source untouched. | Verified: original three Wipe spots, two queryable Polish surfaces, both PrimaryParts = Base. Wipe runner disabled only. |
| Physical phone / teammate | Physical-device check and another teammate's playtest. | Pending |

Output should include `[PolishRub] ready: 2 surfaces`, `[PolishTest] started`,
25/50/75/100% shine milestones, and exactly one local completion per run.
Bad fixtures deliberately produce a setup warning. Diagnostic commands also
produced errors during investigation; these must not be presented as prototype
runtime failures or omitted to claim an entirely clean test log.

### Rotation investigation

An initial landscape-to-portrait run stopped earning progress; a fresh portrait
Play session worked. Later controlled live rotation and Exit/Start without a Play
restart both allowed rubbing to advance. Input-event inspection also proved an
automation targeting error: the path-based Start click landed at touch y=613,
above the button at y=652..698. A corrected click at y=675 activated Start.
This explains some failed automated actions, not the original stall conclusively.
No source change is justified by that evidence alone. Retain the intermittent
case for manual/device follow-up; rotate while held/released and retest both
orientations. The camera is framed at Start/Restart, not continuously on resize.

## Review readiness

Implemented and partially verified in isolation; not fully signed off. Remaining:
the partial/unverified rows above, one/several-surface count variants, physical
phone and teammate checks, and production movement/tool/timing agreements.
Production integration and server acknowledgements remain a separate milestone.
