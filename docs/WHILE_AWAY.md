# CATCH-UP for Dwayne and Sean (latest, 2026-11-16: read this first)

Written by Ace's Claude session. The older report further down is from an earlier session; it is kept below.

**LAYOUT CHANGED (2026-11-16, place v109): the six shops now sit on ONE street (Workshop Lane). Plots 1-3 are the west side facing east, Plots 4-6 the east side facing west, whole-plot PivotTo, nothing inside a plot changed. Sean: re-check customer paths in each shop and the Visit teleport if you can. Details: docs/Environment_Art.md "New layout".**

**UI RESTYLED (2026-11-16, place v110): dark charcoal panels, warm-white text, terracotta and deep-teal accents, Gotham fonts; `UiTheme.luau` colours changed (names kept). Sean: please re-check every screen on desktop and phone and fix any text with poor contrast (details: docs/Environment_Art.md "UI restyle").**

## Where main is (everything below is pushed unless marked "Studio only")
- **Pull main BEFORE you press Play.** `Main.local.luau` now lists new client controllers; if one is missing in your Studio, the client waits forever. If a file did not reach your Studio, link Script Sync for `src/Client` (it must map to `StarterPlayerScripts.Client`).
- **Restoration works by hand now.** Inventory Restore -> server session -> step runner (`Controllers/RestorationController.luau`) -> minigame per step -> Restored (stars, XP, finish card). Server rules: `Services/RestorationService.luau` (53 tests). Contract: `docs/Restoration_Contract.md`.
- **Minigames.** Dwayne: Wipe and Polish (`RestorationMinigamesController`, `RestorationView`, `PointerInput`) are merged. Ace: Test, Scrape, Reassemble, Replace in `src/Client/Minigames/` (`Socket`, `Reassemble`, `Replace`, `Scrape`, `Test`) registered by `RestorationMoreMinigamesController`. **Test works with no model** (tap the needle). Scrape/Reassemble/Replace use `ctx.model` + `ctx.attachPointer` from Dwayne's view; if the view or a model part is missing they fall back to a hold-the-button placeholder, so a step never gets stuck.
- **Runner hook** (Dwayne, please keep): `RestorationController.RegisterMinigame(stepType, fn(ctx))`, `SetViewProvider(fn)`, `RunPlaceholder(ctx)`. `ctx` = `{uid, stepIndex, step, seed, sessionId, benchName, bench, startedAt, model, attachPointer, setProgress(0..1), complete(score)}`. `complete()` holds the report until the server's minimum step time has passed.
- **Item models** (Studio only, not in Git): `ReplicatedStorage.Assets.Items.<ItemId>`: 19 placeholder blocks by Ace (attribute `Placeholder = true`, replace freely) + Dwayne's real RubberDuck. They follow `docs/Item_Model_Contract_DRAFT.md` (`Base`, `DirtSpots` + `Dirt` decal, `RustSpots` + `Rust` decal + `Layers`, `Sockets`/`LooseParts` with matching names and decoys for Replace, `PolishSurfaces`, `TestPoint`).
- **Sean's work merged:** customer NPCs, Visit list + likes + invite, Restoration screen, banner, buyable Expansions, tutorial (4 steps, `TutorialService`), readable shelf tags. Ace wrote `Tests/TutorialCheck.luau` (19 checks) for the tutorial.
- **PlotService builds Expansion rooms** (Back Room, Showroom) from `ServerStorage.Expansions`, so Expansions are safe to buy.
- **Checks.** In Play: `game.ServerStorage.DevTools:Invoke("testAll", player)` runs every automated check (577, ends GREEN or RED); add `true` as 3rd argument to also walk the live loop. `PlotCheck` (44) and `DevToolsCheck` (27) must be run from the command bar (they read script Source). PlotCheck now also fails if any Plots/Environment part is unanchored.
- **Dev commands (Studio only, chat):** `/cmds`, `/fly`, `/noclip`, `/speed n`, `/jump n`, `/zoom n`, `/tp x y z`, `/tp name`, `/plot n`, `/normal` (`AdminController`). Zoom is limited to 20 studs for players (`StarterPlayer.CameraMaxZoomDistance`).
- **Security check done:** 589 malformed remote calls changed nothing and caused no server errors.
- **Economy pacing re-check** is in `docs/02_Economy.md` (first sale about 2 min, first upgrade about 3 min, Lv 5 about 25 min).

## Town restyle ("Modern Boutique District", Studio only; restore point v105)
Ace asked for a premium, modern look. Done so far (place v106): warm golden-hour grading, one muted palette (see `docs/Environment_Art.md`), one accent per shop (P1 teal, P2 terracotta, P3 mustard, P4 plum, P5 sage, P6 navy), matte black fascia signs with warm-white text (the `OwnerName` label still gets the owner's name), flat modern canopies, layered trees, string lights and outdoor seating in the square, no balloon-like hills. Parts 3,054 -> 3,025; enabled point lights still 49.
- **Please do NOT edit** `Workspace.Environment`, `Plots.PlotN.Facade`, `Lighting`, `Baseplate`. Gameplay parts were only recolored, never moved or renamed.
- **Sean:** re-check HUD pill and panel contrast and shelf tags against the new warmer, darker light. **Dwayne:** re-check rarity and Golden colors on the new oak shelves and plaster walls, and the bench camera.
- **One manual step for Ace:** set `Lighting.Technology = Future` in Properties (a script cannot set it).

## Waiting on
- Dwayne: nothing blocking; please test Scrape/Reassemble/Replace on your view with the placeholder models and tell Ace what to change.
- Sean: shelf-tag and HUD check on the new light (above).
- Ace: link Script Sync for `src/Client`; 2-player test; leave-mid-restore and customer-reserved save tests.

---

# While you were away: report (Dev 1 files)

Nothing was committed or pushed. Everything is in your working tree (`git status` shows the new files).
Only `src/Shared`, `src/Server/Lib` and docs were touched. Nothing in Studio was deleted except my own temporary
test copies (a throwaway clone of `Shared`, and three renamed/cloned module copies). I checked afterwards that
Studio and disk contain no leftovers.

## Final decisions (restoration parts + economy dependencies)

**Correction to something I said earlier:** the Item Model Contract IS written: `docs/01_GameDesign.md` §C2. I had wrongly reported it as missing, and the onboarding doc repeated that. `docs/07_Onboarding.md` is fixed. The contract says each socket is "named after the part that fits" (examples `ArmL`, `Wheel1`), so one name = one socket + one loose part.

**Final 15 restoration part names** (Ace's decision; no longer waiting for Dwayne): ToyCar `Wheel`, DeskLamp `Bulb`, AlarmClock `Bell`, CassettePlayer `Button`, MusicBox `Dancer`, RetroCamera `Lens`, CopperKettle `Lid`, TinRobot `LeftArm`, Gramophone `Horn`, Jukebox `Record`, PocketWatch `Gear`, TubeRadio `Tube`, RotaryPhone `Handset`, Marionette `Leg`, ShipInBottle `Mast`.
- Rules used: understandable for ages 9-14, a real object, short for mobile UI (all 7 characters or fewer), unique, singular (one socket each).
- Changed: `Wheels` -> `Wheel` and `Limbs` -> `Leg` (plural names did not match "one name = one socket"; a marionette has one loose leg here), `ArmL` -> `LeftArm` (plain English, no code-style suffix). The other 12 are unchanged.
- Updated to match: `Items.luau`, `Types.luau` (comment), docs/01 §C2 (example + final table), docs/02 §4 recipe notes ("wheel", "leg", "left arm"), docs/03 §10.1 example, STATUS, onboarding. No parts were added.

**Economy sim:** `tools/econ_sim.py` now respects `requires` (FishTank needs BackRoom, Fountain needs Showroom). Two lines changed: a small `REQ` table and the purchase condition. No prices, levels, XP or other numbers were touched. Result (200 runs): Lv 5 = 23 min, Back Room 58, Lv 10 = 83, Lv 12 = 120, Lv 15 = 187 (all same as before); **Showroom 231 -> 211, Sign 3 192 -> 172**; Fish Tank 72 (same); Fountain 229 (was 168, before the Showroom). Violations: Fish Tank before Back Room 0/200, Fountain before Showroom 0/200 (was 200/200). docs/02 pacing table: Showroom simulated median now 211 min. The target column still says "~4 hours"; 211 min is about 3.5 h, a bit faster than the target. I did not change the target or any balance number.

**Tests:** ConfigCheck 231 passed, 0 failed. FormulasCheck 77 passed, 0 failed. Lv 15 XP check still expects 16078.

**Left for later:** UpgradeService (still a stub; requirements documented in STATUS.md and docs/03). `tools/econ_sim.py` keeps its own Fountain level of 10; the config says level 1 + requires Showroom (Showroom needs Lv 10), so behavior is the same.

## Update: your decisions applied (re-run done)

1. XP formula kept. docs/02_Economy.md §7 now says Lv 15 ~ 16,100 cumulative XP.
2. Kid, Grandpa, Teen set to neutral (no rarity preference, tipBonus 0, walk speed 10, equal weight 25). Only the Collector differs.
3. All decor unlocks at Lv 1; Fish Tank requires the Back Room, Fountain requires the Showroom.
4. Upgrade effect field names kept. Recipe part names were kept at the time, then finalized later (see "Final decisions" below).

**Re-run result after your decisions: ConfigCheck 221 passed, 0 failed. FormulasCheck 77 passed, 0 failed.** The only test edit then was the label of the Lv 15 XP check (the expected value 16078 did not change). **Later consistency review: ConfigCheck is now 231 passed, 0 failed (10 checks added, see "Consistency review" below); FormulasCheck still 77 passed, 0 failed.**

The report below is the original; sections 2, 3 and 6 are edited to reflect these decisions.

## Consistency review (before ProfileStore work)

**Changed in this review**
- `src/Shared/Tests/ConfigCheck.luau`: +10 checks (every `requires` points at an existing upgrade; all decor unlocks at Lv 1; Fish Tank requires Back Room and Fountain requires Showroom). No existing check or expected value was changed. Result: 231 passed, 0 failed. FormulasCheck unchanged: 77 passed, 0 failed, Lv 15 still expects 16078.
- `docs/03_Architecture.md`: §6 `RequestBuyUpgrade` row and §10.3 now state that `requires` must be validated in addition to `requiredLevel`.
- `src/Shared/Types.luau`: comment on the `requires` field.
- `docs/STATUS.md`: new "Implementation requirements (not built yet)" section for `UpgradeService`; contract-change log rows.
- Not changed: XP formula, config numbers, `tools/econ_sim.py`, `docs/02_Economy.md`.

**UpgradeService:** still an empty stub (Init/Start print only). So nothing validates purchases yet. The rule is written down as an explicit requirement in STATUS.md and docs/03.

**Wording check (resolved):** Fish Tank requires the **Back Room** and Fountain requires the **Showroom**, as docs/02 §6 and decision 3 say. This was reconfirmed in the final-decisions request.

**[Superseded: `tools/econ_sim.py` now enforces `requires`; the final numbers are in "Final decisions" below.]** **econ_sim.py rerun** (Python 3.14, unchanged script, seeds 0-199, deterministic): Lv 5 = 23 min, Back Room = 58, Lv 10 = 83, Lv 15 = 187, Showroom = 231. These equal the doc table. Crate EV = $37.5 (Starter) and $203.8 (Flea), equal to the doc. So the XP documentation fix needs no pacing change. **One discrepancy to decide:** the sim does not model `requires`. It buys the Fountain before the Showroom in 200 of 200 runs (median minute 168 vs 231). With the rule enforced (scratch copy, not saved in the repo), Showroom moves 231 -> 211 min, Sign 3 192 -> 172, Fountain 168 -> 229; Lv 5/10/12/15, Back Room and Fish Tank are unchanged. Updating the sim and the doc pacing table is a balancing choice, so it has not been done. (Correction to an earlier remark: the sim never printed the Lv 15 cumulative XP; its print list shows "reach 16" = 19,125. 16,078 comes from the same formula, not from a sim line.)

**Part names:** at the time of this review the 15 names in STATUS.md matched `Items.luau` exactly (checked by script). They are now final: see "Final decisions" below.

**Open at that time (all now resolved, see "Final decisions" below):** Back Room vs Showroom wording, updating the sim, Dwayne's part-name confirmation. **Still true:** UpgradeService does not exist yet; not tested: 2 players, touch, Studio strict-type warnings.

## 1. What's done

| Step | Result |
|---|---|
| Skeleton from setup | Already finished and committed earlier (also `DataService`, from before this task). Not touched. |
| 1. Config | `Economy`, `Rarities`, `Crates`, `Items` (all 20), `Upgrades`, `Customers` in `src/Shared/Config/` |
| 2. `Types.luau` | `ItemInstance`, `PlayerData`, plus `ItemDef`, `CrateDef`, `RarityDef`, `UpgradeDef`, `CustomerDef`, `RecipeStep` |
| 3. `Formulas.luau` | `sellPrice`, `quickSellPrice`, `qualityStars`, `xpToNext`, `ratingStars` |
| 4. `Remotes.luau` | **No change needed.** Diffed against docs/03 §6: 16 client->server, 7 server->client, 1 function. Exact match. |
| 5. `Lib/Validate.luau`, `Lib/Log.luau` | Done. 32 checks on a live server all passed (types, rate limiter incl. reset after 1 s, distance, Log). |
| 6. Playtest | No errors or warnings. 11 services and 9 controllers each print Init/Start once, in order. |
| Quality 1-3 | `Tests/ConfigCheck.luau` and `Tests/FormulasCheck.luau` written and run. Latest: **231 passed, 0 failed** and **77 passed, 0 failed**. |
| Quality 4 | Config compared to docs/02 with scripts + by eye (see section 5). |
| Quality 5 | Files re-read against CLAUDE.md §4 and §5. Three files had headers over the 6-line limit (`ConfigCheck`, `FormulasCheck`, `Log`); trimmed. |

## 2. Choices I made for you (the docs were silent or ambiguous)

Please review these, especially the ones marked **(placeholder)**.

**Formulas**
1. **Rounding:** prices round to the nearest whole dollar, `.5` rounds up. Doc examples ("about $21") fit this.
2. **`sellPrice` excludes the tip and the +10% checkout bonus.** They are random / timing based, so `CustomerService` adds them. `sellPrice` = base x quality x variant x wish only.
3. **Bad input never errors:** unknown or missing item -> price 0. Stars: missing/NaN/0/negative -> 1, above 3 -> 3, decimals round down. Score: clamped 0-100. Tool bonus clamped 0-10. Level below 1 counts as 1. Negative or missing rating points count as 0.
4. **`xpToNext` at or above level 15 returns `math.huge`** ("can't level up"). The doc only says the cap is 15.
5. **`qualityStars(averageScore, toolBonus)`** takes the average score and the combined tool bonus (the caller averages and adds tool levels). Thresholds are 90 / 70 from docs/01 B8.

**Config shapes** (docs/03 §10 only defines Items, Customers, Upgrades)
6. **Crates:** `{ id, name, boxModel, price, requiredLevel, itemCount, tier, odds }`. `tier` means "draw from items of this tier" (Free Delivery and Starter -> tier 1, Flea Market -> tier 2). `boxModel` names come from docs/03 §2 (`Box`, `CrateStarter`, `CrateFlea`).
7. **Antique Dealer and Estate Sale crates are not included.** They are Update 1/2 and there are no Tier 3+ items to put in them.
8. **Rarities:** no display colors. The docs give none; Dev 3 picks them with the UI.
9. **Economy.luau also holds** categories, the six step types, minimum step seconds (docs/03 §7), quality thresholds and the tool-bonus cap, so nothing is hardcoded elsewhere.
10. **Items:** step parameters come from the "(...)" notes in docs/02. `Replace` also uses a `parts` list. The 15 part names are FINAL MVP decisions (see "Final decisions" below; the first version was `Wheels`, `Limbs`, `ArmL`). Only TinRobot has `layers`, `greenZone` and `flavor` (from docs/03 §10.1). `model` = item id.
11. **Customers (decided by Ace):** Kid, Grandpa and Teen are neutral: no rarity preference, `tipBonus` 0, walk speed 10, equal spawn weight 25 each. Only the Collector differs (prefers Rare+, `tipBonus` 0.05, weight 15, from docs/03 §10.2). The weight 25 is my pick for "equal"; any equal number works.
12. **Upgrades (effect field names and unlocks are mine):**
    - Tool speeds: Brush 1.25/1.5/1.75 (doc example). Polisher "+30% per level" -> 1.3/1.6/1.9.
    - Repair Toolkit effect = `hoverHighlight`, `replaceGlow`, `qualityBonus` (0,0,5 per the doc's L1/L2/L3 text). Polisher L3 `qualityBonus` 5.
    - Display Shelves effect = total slots `{6, 9, 12}`; Storage Racks = capacity `{16, 24, 40}`; Shop Sign = `signLevel`, and customer interval comes from `Economy.CustomerSpawnSignFactor ^ level`.
    - **Decor unlock levels (decided by Ace):** all decor unlocks at Lv 1. Fish Tank also requires owning the Back Room (`requires = "BackRoom"`) and Fountain requires the Showroom (`requires = "Showroom"`). `requiredLevel` is 1 for both; the `requires` field is what enforces it, so `UpgradeService` must check it.
    - **Potted Plants** is one upgrade with 2 levels (80 each, 1 point each) so it fits the level model.
    - The decor named "Neon RE:STORE Sign" in the doc is called **"Neon Sign"** in config (game was renamed; the in-game text is Dev 3's call).
13. **`Types.luau`** only declares types and returns `{}`. It is `--!strict`; I could not run Studio's strict analysis from here (see section 4).
14. **Tests are ModuleScripts** with a `run()` function, in `src/Shared/Tests/` (so they sync to `ReplicatedStorage.Shared.Tests` and clients can see them; harmless, but you may want them in a dev-only place later). Run in the Studio command bar: `require(game.ReplicatedStorage.Shared.Tests.ConfigCheck).run()`.
15. **`Validate`:** `rateLimit` default is 5 per second (docs/03 §6). Counters are cleared on `PlayerRemoving`. `withinDistance` accepts a Vector3 or a BasePart and uses the character's `HumanoidRootPart`. Added `isConfigId(id, configTable)` for the "exists in config" check from docs/03 §7.
16. **`Log.new(tag, debugEnabled)`** returns `info` (prints only when debug is on) and `warn` (always).

## 3. Problems found

1. **Real bug, fixed:** `quickSellPrice("Jukebox", 3)` returned 2047 instead of 2048. The exact value is $2,047.50, but floating point stores 2925 x 0.7 as 2047.4999999999998. Fixed in `Formulas.round` (adds 1e-9 before rounding). The test was correct and was not changed.
2. **Doc inconsistency (resolved by Ace):** docs/02 §7 said cumulative XP to Lv 15 was "~15,000", but its own formula `round(40 x L^1.6)` gives 16,078. Decision: keep the formula, and docs/02 §7 now says "Lv 15 ≈ 16,100". Lv 5 = 761 and Lv 10 = 5,348 already matched the doc. `tools/econ_sim.py` has not been re-run for the slightly higher total.
3. **Test-method note:** Studio caches a module after the first `require`, so after editing `Formulas` my re-run used fresh copies of the modules (a cloned `Shared` folder, destroyed afterwards). The final PASS/FAIL below was produced that way, from the current code.
4. Nothing failed twice. No Studio disconnects.

## 4. What I could not verify

- **Strict typing:** I did not see Studio's script-analysis warnings for `Types.luau` or the typed `Validate` / `Formulas` signatures. The playtest showed no errors, but warnings may exist in the Script Analysis window.
- **Client use:** `Formulas` and `Config` were only required on the server and in Edit mode. A client-side `require` (using `WaitForChild`) was not tested.
- **Real handlers:** `Validate` was tested with direct calls. No remote handler uses it yet.
- **Config not used by any service yet.** The tests check the data is complete and consistent, not that gameplay balance feels right.
- **Balance:** doc pacing figures (section 9 of docs/02) were not re-simulated.
- **Not tested:** 2 players, phone/touch.

## 5. Config vs docs/02_Economy.md (comparison done)

- **Items:** all 20 compared by script on id, name, rarity, category, base value and recipe step order: **identical**. Tier split 12 / 8. Part names: the 15 final names now match between `Items.luau` and docs/01, 02, 03 and STATUS (checked by script, see "Final decisions").
- **Tool and shop upgrades** (costs and required levels, all 6): **identical** (scripted).
- **Decor and expansions** (costs, points, Lv 4 / Lv 10, rating points 3 / 8, +6 slots, +3 pedestals, customer cap 5): checked by eye, **identical**.
- **Crates, rarities, Economy numbers:** re-read line by line against §1, §2, §3, §5, §6, §7: identical. One sanity check by hand arithmetic (not a script): average item value per crate from my config = Free Delivery about $22.4, Starter exactly $37.50, Flea Market about $203.8, matching the doc's ~$22, $37.50, $204.
- **Numbers I changed or could not match:** none changed. The only mismatch was the Lv 15 XP total, now resolved by correcting the doc (see section 3, item 2). Values with no doc number are listed in section 2 (effect field names, recipe part names).

## 6. Test by hand (about 10 minutes)

1. Studio command bar (Edit mode): run both `require(...).run()` lines above and confirm 231/0 and 77/0.
2. Press Play: Output should show the usual Init/Start lines and no red or yellow text.
3. Customers and decor decisions are applied (see Update below). Nothing to review there.
4. XP question is settled (docs/02 now says ~16,100). Recipe part names are final (no confirmation needed).
5. Run `git status`, review, then commit when happy. Nothing is staged.

## 7. Full PASS/FAIL output (final run, fresh copies, current code)

### FormulasCheck
```
PASS sellPrice ToyCar 3 stars (doc example, ~$21) = 21
PASS sellPrice RubberDuck 2 stars (doc example, $12) = 12
PASS sellPrice RubberDuck 1 star = 10
PASS sellPrice RubberDuck 3 stars = 16
PASS sellPrice Gramophone 2 stars = 450
PASS sellPrice Jukebox 3 stars = 2925
PASS sellPrice Golden Gramophone 2 stars is exactly 3x normal = 1350
PASS sellPrice Golden ToyCar 3 stars = 62
PASS sellPrice wish match RubberDuck 2 stars = 15
PASS sellPrice Golden + wish RubberDuck 2 stars = 45
PASS sellPrice golden nil counts as normal = 12
PASS sellPrice stars 0 counts as 1 star = 10
PASS sellPrice negative stars count as 1 star = 10
PASS sellPrice stars above 3 count as 3 = 16
PASS sellPrice missing stars counts as 1 star = 10
PASS sellPrice NaN stars counts as 1 star = 10
PASS sellPrice 2.9 stars rounds down to 2 stars = 12
PASS sellPrice unknown item is 0 = 0
PASS sellPrice missing item is 0 = 0
PASS sellPrice wrong item type is 0 = 0
PASS quickSell RubberDuck 2 stars = 8
PASS quickSell ToyCar 3 stars = 15
PASS quickSell Gramophone 2 stars = 315
PASS quickSell Golden RubberDuck 2 stars = 25
PASS quickSell RubberDuck missing stars counts as 1 star = 7
PASS quickSell Jukebox 3 stars = 2048
PASS quickSell unknown item is 0 = 0
PASS quickSell ignores wish (is below the normal price) = true
PASS quickSell negative stars count as 1 star = 7
PASS qualityStars 100 = 3
PASS qualityStars 90 is 3 stars = 3
PASS qualityStars 89.9 is 2 stars = 2
PASS qualityStars 70 is 2 stars = 2
PASS qualityStars 69.9 is 1 star = 1
PASS qualityStars 0 is 1 star = 1
PASS qualityStars 85 + bonus 5 reaches 3 stars = 3
PASS qualityStars 65 + bonus 5 reaches 2 stars = 2
PASS qualityStars 59 + bonus 10 is still 1 star = 1
PASS qualityStars bonus is capped at 10 (80 + 50 -> 90) = 3
PASS qualityStars bonus cap really is 10 (79 + 50 -> 89) = 2
PASS qualityStars negative bonus counts as 0 = 3
PASS qualityStars negative score counts as 0 = 1
PASS qualityStars score above 100 counts as 100 = 3
PASS qualityStars missing score is 1 star = 1
PASS qualityStars missing bonus counts as 0 = 3
PASS qualityStars NaN score is 1 star = 1
PASS xpToNext level 1 = 40
PASS xpToNext level 2 = 121
PASS xpToNext level 3 = 232
PASS xpToNext level 4 = 368
PASS xpToNext level 5 = 525
PASS xpToNext level 10 = 1592
PASS xpToNext level 14 = 2728
PASS xpToNext level 15 (cap) is infinite = inf
PASS xpToNext level 16 (above cap) is infinite = inf
PASS xpToNext level 0 counts as level 1 = 40
PASS xpToNext negative level counts as level 1 = 40
PASS xpToNext missing level counts as level 1 = 40
PASS xpToNext NaN counts as level 1 = 40
PASS xpToNext 1.9 rounds down to level 1 = 40
PASS cumulative XP to reach level 5 (doc says ~760) = 761
PASS cumulative XP to reach level 10 (doc says ~5,350) = 5348
PASS cumulative XP to reach level 15 (doc says ~16,100) = 16078
PASS ratingStars 0 points = 1
PASS ratingStars 7 points = 1
PASS ratingStars 8 points = 2
PASS ratingStars 19 points = 2
PASS ratingStars 20 points = 3
PASS ratingStars 39 points = 3
PASS ratingStars 40 points = 4
PASS ratingStars 64 points = 4
PASS ratingStars 65 points = 5
PASS ratingStars 1000 points = 5
PASS ratingStars 7.9 points = 1
PASS ratingStars negative points = 1
PASS ratingStars missing points = 1
PASS ratingStars NaN points = 1
[FormulasCheck] 77 passed, 0 failed
```
(Before the rounding fix, the run was 76 passed, 1 failed: the `quickSell Jukebox 3 stars` line, expected 2048, got 2047.)

### ConfigCheck (231 checks; 221 in the original run + 10 added in the consistency review)
The 231 lines are the same on every run and are produced by `ConfigCheck.run()`: 9 crate checks (odds = 100, known rarities,
every rarity listed), 7 checks for each of the 20 items (fields, id matches key, positive value, tier 1/2, recipe uses the six
allowed types, rarity exists, category exists), 3 crate-tier coverage checks, 4 checks for each of the 15 upgrades
(id matches key, costs length, requiredLevel length, levels never go down), item count 20, tier 1 = 12, tier 2 = 8, rarity
indexes, 4 customer checks and "4 customer types". Final line, copied from the run:
```
[ConfigCheck] 231 passed, 0 failed
```
Per-check lines (all `PASS`) are printed to Output and returned by `run()` if you want every line.
