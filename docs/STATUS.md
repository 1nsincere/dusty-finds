# STATUS: what's real right now

> Update after every feature. Claude Code reads this at the start of each session.
> Format: one line per item. Newest first inside each section.

**Current stage:** 1: Project setup
**Last updated:** 2026-11-15 by Dev 1 (Ace, with Claude Code)

## ✅ Done
- Core economy loop, server side (Dev 1, built while away; services in `src/Server/Services/`): **EconomyService** (`AddCash`, `Spend`, `CanAfford`, `AddXp`; `xp` = progress inside the current level; level-up pays $50 x new level; whole numbers only), **InventoryService** (`Add`, `Get`, `Remove`, `Update`, `ClearField`, capacity from Storage Racks, `CountWaitingBoxes`, `QuickSell` + `RequestQuickSell`), **CollectionBookService** (`RecordFound`, `RecordRestored`, `GetRatingPoints/Stars`), **UpgradeService** (`BuyUpgrade` + `RequestBuyUpgrade`, all 5 checks incl. `requires`, refunds if saving fails, calls `PlotService.RefreshSlots`), **ShipmentService** (`RollItem`, `BuyCrate`, `ClaimFreeDelivery`, `GrantFirstBox`, `OpenBox` + `RequestBuyCrate/RequestOpenBox/RequestClaimFreeDelivery`, Legendary announcement, first-find bonus). Tests: `Server/Tests/SystemsCheck.luau` (117 passed, 0 failed; fake in-memory data, mock players, never touches DEV data; run in Play: `require(game.ServerScriptService.Server.Tests.SystemsCheck).run()`), ConfigCheck 231 / FormulasCheck 77 still pass. Rolls verified over 200k samples: Starter avg item value ~$37.5, Flea ~$204, rarity odds and 2% Golden match docs/02. Live boot clean; a real player got the first Rubber Duck box. NOT tested with a real client/UI (none of the buy/open/sell buttons exist yet). Not built: expansion models (Back Room/Showroom clone), decor visibility, customer sales (Sean/DisplayService), page-completion rewards.
- PlotService (Dev 1): `src/Server/Services/PlotService.luau`. When a player's data loads they get the first free plot (Plot1..6), are teleported to its `Spawn` (also on every respawn), `Sign.SurfaceGui.OwnerName` shows their DisplayName, and DisplaySlots/ExhibitSlots `Enabled` follows their upgrades (Config only: Economy starting slots, `DisplayShelves`, `Showroom`). On leave the plot resets (sign "For Sale", slots back to start, owner cleared). API: `GetPlot(player)`, `RefreshSlots(player)` (UpgradeService calls this after a purchase). Tested in Studio Play (real player: Plot1, sign, 3.4 studs from Spawn, respawn returns to the shop) and on a copy of the plots with mock players (6 players get 6 plots, 7th gets none without errors, release and reuse, double release, display 3/9/12 and exhibit 1/4 slots). 2-player test passed (Ace, 2026-11-15): each player got a different plot and sign, closing one client released its plot and left the other connected. Decor and expansions are not rebuilt yet (comes with UpgradeService).
- Final MVP decisions (Dev 1): the 15 restoration part names are final (see below; `Wheel`, `Leg`, `LeftArm` replaced `Wheels`, `Limbs`, `ArmL`), and `tools/econ_sim.py` now enforces `requires` (Fish Tank needs Back Room, Fountain needs Showroom). Sim result: Showroom median 231 -> 211 min and Sign 3 192 -> 172 min; Lv 5/10/12/15, Back Room and Fish Tank unchanged. docs/02 pacing table updated. Tests: ConfigCheck 231 pass, FormulasCheck 77 pass, Lv 15 XP still 16078.
- Greybox HUD: `StarterGui.HUD` built with all §8 HUD names (incl. new `TopRight.{Settings,Visit}`), J1 palette, FredokaOne + Builder Sans, placeholder values ($100, 1★, Lv 1 at 30%). Phone-first sizes: 52 px left buttons, fits a 706×392 viewport below the topbar with room to spare. Play test: HUD appears in PlayerGui, no errors. Saved as place v25. HudController now sets `HUD.UIScale` from screen height (0.85–1.4; 706×392 → 0.93, buttons 48 px). Plays with Ace's PlotService: player gets Plot1, sign shows their name, spawns at `Spawn`, 3 slots enabled. **Money/XP not wired yet** (needs ClientState). UI lives in Team Create only, not Git. Not yet checked in the Device Emulator.
- Greybox plots: `Workspace.Plots.Plot1..Plot6` built in Studio with the §2 part names (docs/03 §2 updated with the exact structure), 60 studs apart along a `Street` part; default SpawnLocation moved onto the street. All parts anchored; a script confirmed Plot1 has every required name. Play test: 6 plots, player spawns on the street, no errors. Saved as place v24. Not yet walked through by hand or on the phone emulator. Plot2-6 are copies of Plot1: **edit Plot1, then re-copy**.
- Config + math + server helpers (Dev 1, built while away; see `docs/WHILE_AWAY.md`): `Shared/Config/{Economy,Rarities,Crates,Items,Upgrades,Customers}.luau` (all 20 items, numbers match docs/02), `Shared/Types.luau`, `Shared/Formulas.luau` (sellPrice, quickSellPrice, qualityStars, xpToNext, ratingStars), `Server/Lib/{Validate,Log}.luau`. `Remotes.luau` re-checked against docs/03 §6: exact match. Tests in `Shared/Tests/` (ConfigCheck 231 pass, FormulasCheck 77 pass; run from the Studio command bar). Playtest clean. Committed in 1a79b9c. Re-run 2026-11-15 in a fresh session via Studio MCP (fresh module copies): ConfigCheck 231 passed / 0 failed, FormulasCheck 77 passed / 0 failed. Customers set neutral (only the Collector differs), all decor unlocks at Lv 1 (Fish Tank needs Back Room, Fountain needs Showroom), docs/02 §7 corrected to Lv 15 ~ 16,100 XP.
- DataService (ProfileStore): loads profile on join (template from docs/03 §10.5, store `PlayerData_DEV` in Studio / `PlayerData_v1` live), Reconcile + migrate stub, kicks if session fails, ends session on leave. `DataService.Get/Set` for other services; `GetInitialState` returns a copy of the data. Tested in Studio Play: loads cash=100, Set works incl. nested paths, bad input rejected, and data persists across Stop/Play (cash 250 reloaded; Studio API access is now on). Rewrite reviewed: `StartSessionAsync` is wrapped in `pcall` (error or nil -> kick, `loading` always cleared) a `releasing[player]` flag stops a normal leave being treated as a lost session, and a `removed[player]` flag releases a profile whose load finishes after PlayerRemoving fired (no leaked session lock). Re-tested on an isolated store (`PlayerData_TEST_*`, not DEV): load, Reconcile, Get copy, Set, nested/invalid Set, release, duplicate load, injected load failures, persistence across Stop/Play all pass. 2-player test passed (Ace, 2026-11-15): both loaded own data, one client left with no session-loss kick and the other stayed connected. Still untested: real shutdown save and a real cross-server session loss. ProfileStore installed at `ServerScriptService.Packages.ProfileStore` (not synced, do not edit).
- Project skeleton boots with no errors: 11 server services + 9 client controllers load in the §4 order, each prints Init then Start once (checked in a Studio playtest). Remotes from 03 §6 are created by `Shared/Remotes.luau` (23 events + `GetInitialState`). All stubs have `DEBUG = true`; turn off when real code lands.
- Script Sync linked for `ServerScriptService.Server`, `ReplicatedStorage.Shared`, `StarterPlayerScripts.Client` ↔ `src/Server`, `src/Shared`, `src/Client` (verified two-way with test files).
- Studio MCP connected to place "Dusty Finds: Restore & Sell" (placeId 113871213495650).
- Team recorded in CLAUDE.md §0 and `docs/04` §G; game renamed to Dusty Finds in titles.

## 🔨 In progress
| Feature | Owner | Notes |
|---|---|---|
| Item Model Contract draft | Dev 2 (Dwayne) | `docs/Item_Model_Contract_DRAFT.md` expands the existing game-design outline; Ace's review done (see "Review notes for Dwayne" below); awaiting Sean's review. No Wipe code or Studio model built yet. |
| Tooling setup (Team Create, Git, Claude Code, MCP) | All | Dwayne and Sean still need to link Script Sync on their PCs (see Notes) |
| Contracts: Types, Item Model Contract, UI contract, plot part names | Dev 1 / 2 / 3 | Remotes list is done (see skeleton) |

## 📝 Review notes for Dwayne (Item Model Contract draft, by Ace)
The draft fits the architecture and needs no Config, Types or Remotes change. Please fix before finalizing:
1. The socket example `Sockets/Wheel1` / `LooseParts/Wheel1` should use the final names: `Wheel`, `LeftArm`, ... (singular, no digit; see the part-name table below and `Items.luau`).
2. Model location `ReplicatedStorage/Assets/Items/<ItemId>` matches the Config convention (`model` = item id). OK.
3. Code must read the spot folders, not assume 3 spots (the draft already says so). OK.
4. Still open (not needed for the Wipe prototype): rust texture names, assembly transforms, item scale and pivot (with Sean).

## ✅ Decision: decor slot names (Ace)
Plot `DecorSlots` names are approved as decor IDs for `NeonSign`, `PendantLamps`, `Rug`, `WallPosters`. `PottedPlant1` and `PottedPlant2` stay as slot names; in Config they are ONE upgrade `PottedPlants` with 2 levels (level 1 shows `PottedPlant1`, level 2 shows `PottedPlant2`; UpgradeService does the mapping). `FishTank` and `Fountain` have no plot slot: they live in the Back Room / Showroom expansion models in `ServerStorage.Expansions`. Sean: please keep the slot `DecorId` attributes as they are.

## 🐞 Known broken
- (none)

## 🧱 Implementation requirements (built: UpgradeService enforces all 5 checks, see Done)

**UpgradeService** (`src/Server/Services/UpgradeService.luau` is still an empty stub). When `RequestBuyUpgrade` is built it MUST validate, in this order, on the server:
1. rate limit, `upgradeId` is a string, and it exists in `Config/Upgrades`;
2. the next level exists (owned level + 1 <= `maxLevel`);
3. player level >= `requiredLevel[nextLevel]`;
4. **if the upgrade has `requires`, the player owns that upgrade** (`upgrades[requires] >= 1`). `requiredLevel` alone is not enough: all decor is level 1, so only this check stops the Fountain being bought before the Showroom (and the Fish Tank before the Back Room);
5. the player can afford `costs[nextLevel]`, spent through `EconomyService`.

Config today: `FishTank.requires = "BackRoom"`, `Fountain.requires = "Showroom"` (docs/02 §6: "Fish Tank (Back Room)", "Fountain (Showroom)"). `ConfigCheck` verifies this data but nothing yet enforces it at purchase time.

## ✅ Final MVP decision: restoration part names
Decided by Dev 1 (Ace). **No longer waiting for confirmation.** These 15 names are final for the MVP. Rules used: understandable for ages 9-14, a real object, short enough for mobile UI, unique, and one socket + one loose part per name (Item Model Contract, docs/01 §C2). Source of truth: `Shared/Config/Items.luau`. Do not add parts or rename without Ace.

| Item | Part name | Item | Part name |
|---|---|---|---|
| ToyCar | `Wheel` | PocketWatch | `Gear` |
| DeskLamp | `Bulb` | TubeRadio | `Tube` |
| AlarmClock | `Bell` | RotaryPhone | `Handset` |
| CassettePlayer | `Button` | Marionette | `Leg` |
| MusicBox | `Dancer` | ShipInBottle | `Mast` |
| RetroCamera | `Lens` | Jukebox | `Record` |
| CopperKettle | `Lid` | Gramophone | `Horn` |
| TinRobot | `LeftArm` | | |

Changed from the earlier proposal: `Wheels` -> `Wheel`, `Limbs` -> `Leg`, `ArmL` -> `LeftArm` (singular, plain English). The other 12 are unchanged. Test styles (`Switch`, `Wind`, `Shake`, `Play`, `Flash`, `Whistle`, `Ring`, `Tick`, `Tune`, `Light`) are unchanged. Only TinRobot has `layers` and `greenZone` set; Dev 2 decides the rest.
## 📝 Notes for the team
- **Script Sync linking:** right-click the Studio folder → Script Sync → Sync with Directory → pick the **parent `src` folder**. It creates `src/<FolderName>` itself. Picking `src/Server` makes a nested `src/Server/Server`. Stop an old sync before re-linking.
- **Client entry file is `Main.local.luau`** (a LocalScript). `Main.client.luau` is a Script with Client RunContext and runs twice inside StarterPlayerScripts.

## ⏭ Next up
1. Walk the greybox plots by hand + phone emulator (Dev 3). Decor slot names are confirmed (see decision above)
2. Wipe minigame prototype in test place (Dev 2)
4. Wire the UI to the new server API (Dev 3): `RequestBuyCrate`, `RequestOpenBox`, `RequestClaimFreeDelivery`, `RequestQuickSell`, `RequestBuyUpgrade`; show `BoxOpened`, `SaleMade`, `Notify`. Wire restoration to `InventoryService.Update` + `CollectionBookService.RecordRestored` + `EconomyService.AddXp` (Dev 2)
5. Test skeleton with 2 players (Test tab → Clients and Servers) and a phone emulator before Stage 2

## 📝 Contract changes log
| Date | File | Change | By |
|---|---|---|---|
| 2026-11-15 | docs/03 §8, docs/01 J2/J3 | UI contract: added `HUD.TopRight.{Settings,Visit}`, `Stars.Star1..5`, `Banner.Text`, `UIScale`; XP bar moved under the pills (jump button clash) | Dev 3 |
| 2026-11-15 | docs/03 §2 | Plot part names fixed: Counter, Bench1, SupplyBoard are Parts holding their prompts; Sign.SurfaceGui.OwnerName; Exhibit slots get SlotIndex/Enabled; DecorSlots placeholder IDs; Spawn is a plain Part | Dev 3 |
| 2026-11-15 | Config/Economy, Types, docs/03 §10.4 | Additive only: `Economy.MaxWaitingBoxes` (3) and `InteractMaxStuds` (25); `ItemInstance.crateId` and `ItemInstance.boxId` (optional). No remote or data-template change. | Dev 1 |
| 2026-11-15 | docs/STATUS.md | Decor slot names approved as Config IDs (`PottedPlant1/2` map to `PottedPlants` levels 1/2) | Dev 1 |
| 2026-11-15 | CLAUDE.md §3, docs/03 §1/§3 | Client entry is `Main.local.luau`; Script Sync link instructions corrected | Dev 1 |
| 2026-11-15 | docs/01 §C2, docs/02 §4, docs/03 §10.1, Items.luau | Final part names: `Wheels`->`Wheel`, `Limbs`->`Leg`, `ArmL`->`LeftArm` (other 12 unchanged); final table added under the Item Model Contract | Dev 1 |
| 2026-11-15 | tools/econ_sim.py, docs/02 pacing table | Sim enforces `requires`; Showroom simulated median 231 -> 211 min | Dev 1 |
| 2026-11-15 | docs/03 §6 and §10.3 | Upgrade definitions have an optional `requires` field; `RequestBuyUpgrade` must validate it | Dev 1 |
| 2026-11-15 | Shared/Config/*, Shared/Types | New Config schema files: Crates `{id,name,boxModel,price,requiredLevel,itemCount,tier,odds}`, Upgrade `effect` field names, placeholder Customers, proposed recipe part names. Dev 2 / Dev 3 should review. | Dev 1 |
