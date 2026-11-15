# STATUS: what's real right now

> Update after every feature. Claude Code reads this at the start of each session.
> Format: one line per item. Newest first inside each section.

**Current stage:** 1: Project setup
**Last updated:** 2026-11-15 by Dev 3 (Sean, with Claude Code)

## ✅ Done
- Final MVP decisions (Dev 1): the 15 restoration part names are final (see below; `Wheel`, `Leg`, `LeftArm` replaced `Wheels`, `Limbs`, `ArmL`), and `tools/econ_sim.py` now enforces `requires` (Fish Tank needs Back Room, Fountain needs Showroom). Sim result: Showroom median 231 -> 211 min and Sign 3 192 -> 172 min; Lv 5/10/12/15, Back Room and Fish Tank unchanged. docs/02 pacing table updated. Tests: ConfigCheck 231 pass, FormulasCheck 77 pass, Lv 15 XP still 16078.
- Greybox plots: `Workspace.Plots.Plot1..Plot6` built in Studio with the §2 part names (docs/03 §2 updated with the exact structure), 60 studs apart along a `Street` part; default SpawnLocation moved onto the street. All parts anchored; a script confirmed Plot1 has every required name. Play test: 6 plots, player spawns on the street, no errors. Saved as place v24. Not yet walked through by hand or on the phone emulator. Plot2-6 are copies of Plot1: **edit Plot1, then re-copy**.
- Config + math + server helpers (Dev 1, built while away; see `docs/WHILE_AWAY.md`): `Shared/Config/{Economy,Rarities,Crates,Items,Upgrades,Customers}.luau` (all 20 items, numbers match docs/02), `Shared/Types.luau`, `Shared/Formulas.luau` (sellPrice, quickSellPrice, qualityStars, xpToNext, ratingStars), `Server/Lib/{Validate,Log}.luau`. `Remotes.luau` re-checked against docs/03 §6: exact match. Tests in `Shared/Tests/` (ConfigCheck 231 pass, FormulasCheck 77 pass; run from the Studio command bar). Playtest clean. Committed in 1a79b9c. Re-run 2026-11-15 in a fresh session via Studio MCP (fresh module copies): ConfigCheck 231 passed / 0 failed, FormulasCheck 77 passed / 0 failed. Customers set neutral (only the Collector differs), all decor unlocks at Lv 1 (Fish Tank needs Back Room, Fountain needs Showroom), docs/02 §7 corrected to Lv 15 ~ 16,100 XP.
- DataService (ProfileStore): loads profile on join (template from docs/03 §10.5, store `PlayerData_DEV` in Studio / `PlayerData_v1` live), Reconcile + migrate stub, kicks if session fails, ends session on leave. `DataService.Get/Set` for other services; `GetInitialState` returns a copy of the data. Tested in Studio Play: loads cash=100, Set works incl. nested paths, bad input rejected, and data persists across Stop/Play (cash 250 reloaded; Studio API access is now on). Rewrite reviewed: `StartSessionAsync` is wrapped in `pcall` (error or nil -> kick, `loading` always cleared) a `releasing[player]` flag stops a normal leave being treated as a lost session, and a `removed[player]` flag releases a profile whose load finishes after PlayerRemoving fired (no leaked session lock). Re-tested on an isolated store (`PlayerData_TEST_*`, not DEV): load, Reconcile, Get copy, Set, nested/invalid Set, release, duplicate load, injected load failures, persistence across Stop/Play all pass. NOT yet tested with 2 players, real PlayerRemoving/shutdown, or a real cross-server session loss. ProfileStore installed at `ServerScriptService.Packages.ProfileStore` (not synced, do not edit).
- Project skeleton boots with no errors: 11 server services + 9 client controllers load in the §4 order, each prints Init then Start once (checked in a Studio playtest). Remotes from 03 §6 are created by `Shared/Remotes.luau` (23 events + `GetInitialState`). All stubs have `DEBUG = true`; turn off when real code lands.
- Script Sync linked for `ServerScriptService.Server`, `ReplicatedStorage.Shared`, `StarterPlayerScripts.Client` ↔ `src/Server`, `src/Shared`, `src/Client` (verified two-way with test files).
- Studio MCP connected to place "Dusty Finds: Restore & Sell" (placeId 113871213495650).
- Team recorded in CLAUDE.md §0 and `docs/04` §G; game renamed to Dusty Finds in titles.

## 🔨 In progress
| Feature | Owner | Notes |
|---|---|---|
| Item Model Contract draft | Dev 2 (Dwayne) | `docs/Item_Model_Contract_DRAFT.md` expands the existing game-design outline; awaiting Ace and Sean's review. No Wipe code or Studio model built yet. |
| Tooling setup (Team Create, Git, Claude Code, MCP) | All | Dwayne and Sean still need to link Script Sync on their PCs (see Notes) |
| Contracts: Types, Item Model Contract, UI contract, plot part names | Dev 1 / 2 / 3 | Remotes list is done (see skeleton) |

## 🐞 Known broken
- (none)

## 🧱 Implementation requirements (not built yet)

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
1. Walk the greybox plots by hand + phone emulator (Dev 3); Ace to confirm the DecorSlots names as Config IDs (Dev 1)
2. Wipe minigame prototype in test place (Dev 2)
3. Test DataService with 2 players (Test tab → Clients and Servers); then PlotService once Sean's Plot1 exists (Dev 1)
4. Build UpgradeService with the `requires` check (see "Implementation requirements") when Stage 6 starts (Dev 1)
5. Test skeleton with 2 players (Test tab → Clients and Servers) and a phone emulator before Stage 2

## 📝 Contract changes log
| Date | File | Change | By |
|---|---|---|---|
| 2026-11-15 | docs/03 §2 | Plot part names fixed: Counter, Bench1, SupplyBoard are Parts holding their prompts; Sign.SurfaceGui.OwnerName; Exhibit slots get SlotIndex/Enabled; DecorSlots placeholder IDs; Spawn is a plain Part | Dev 3 |
| 2026-11-15 | CLAUDE.md §3, docs/03 §1/§3 | Client entry is `Main.local.luau`; Script Sync link instructions corrected | Dev 1 |
| 2026-11-15 | docs/01 §C2, docs/02 §4, docs/03 §10.1, Items.luau | Final part names: `Wheels`->`Wheel`, `Limbs`->`Leg`, `ArmL`->`LeftArm` (other 12 unchanged); final table added under the Item Model Contract | Dev 1 |
| 2026-11-15 | tools/econ_sim.py, docs/02 pacing table | Sim enforces `requires`; Showroom simulated median 231 -> 211 min | Dev 1 |
| 2026-11-15 | docs/03 §6 and §10.3 | Upgrade definitions have an optional `requires` field; `RequestBuyUpgrade` must validate it | Dev 1 |
| 2026-11-15 | Shared/Config/*, Shared/Types | New Config schema files: Crates `{id,name,boxModel,price,requiredLevel,itemCount,tier,odds}`, Upgrade `effect` field names, placeholder Customers, proposed recipe part names. Dev 2 / Dev 3 should review. | Dev 1 |
