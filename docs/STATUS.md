# STATUS: what's real right now

> Update after every feature. Claude Code reads this at the start of each session.
> Format: one line per item. Newest first inside each section.

**Current stage:** 1: Project setup
**Last updated:** 2026-11-15 by Dev 3 (Sean, with Claude Code)

## ✅ Done
- Greybox HUD: `StarterGui.HUD` built with all §8 HUD names (incl. new `TopRight.{Settings,Visit}`), J1 palette, FredokaOne + Builder Sans, placeholder values ($100, 1★, Lv 1 at 30%). Phone-first sizes: 52 px left buttons, fits a 706×392 viewport below the topbar with room to spare. Play test: HUD appears in PlayerGui, no errors. Saved as place v25. HudController now sets `HUD.UIScale` from screen height (0.85–1.4; 706×392 → 0.93, buttons 48 px). Plays with Ace's PlotService: player gets Plot1, sign shows their name, spawns at `Spawn`, 3 slots enabled. **Money/XP not wired yet** (needs ClientState). UI lives in Team Create only, not Git. Not yet checked in the Device Emulator.
- Greybox plots: `Workspace.Plots.Plot1..Plot6` built in Studio with the §2 part names (docs/03 §2 updated with the exact structure), 60 studs apart along a `Street` part; default SpawnLocation moved onto the street. All parts anchored; a script confirmed Plot1 has every required name. Play test: 6 plots, player spawns on the street, no errors. Saved as place v24. Not yet walked through by hand or on the phone emulator. Plot2-6 are copies of Plot1: **edit Plot1, then re-copy**.
- DataService (ProfileStore): loads profile on join (template from docs/03 §10.5, store `PlayerData_DEV` in Studio / `PlayerData_v1` live), Reconcile + migrate stub, kicks if session fails, ends session on leave. `DataService.Get/Set` for other services; `GetInitialState` returns a copy of the data. Tested in Studio Play: loads cash=100, Set works incl. nested paths, bad input rejected, and data persists across Stop/Play (cash 250 reloaded; Studio API access is now on). Not yet tested with 2 players or the session-failure kick. ProfileStore installed at `ServerScriptService.Packages.ProfileStore` (not synced, do not edit).
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

## 📝 Notes for the team
- **Script Sync linking:** right-click the Studio folder → Script Sync → Sync with Directory → pick the **parent `src` folder**. It creates `src/<FolderName>` itself. Picking `src/Server` makes a nested `src/Server/Server`. Stop an old sync before re-linking.
- **Client entry file is `Main.local.luau`** (a LocalScript). `Main.client.luau` is a Script with Client RunContext and runs twice inside StarterPlayerScripts.

## ⏭ Next up
1. Walk the greybox plots by hand + phone emulator (Dev 3); Ace to confirm the DecorSlots names as Config IDs (Dev 1)
2. Wipe minigame prototype in test place (Dev 2)
3. Test DataService with 2 players (Test tab → Clients and Servers); then PlotService once Sean's Plot1 exists (Dev 1)
4. Test skeleton with 2 players (Test tab → Clients and Servers) and a phone emulator before Stage 2

## 📝 Contract changes log
| Date | File | Change | By |
|---|---|---|---|
| 2026-11-15 | docs/03 §8, docs/01 J2/J3 | UI contract: added `HUD.TopRight.{Settings,Visit}`, `Stars.Star1..5`, `Banner.Text`, `UIScale`; XP bar moved under the pills (jump button clash) | Dev 3 |
| 2026-11-15 | docs/03 §2 | Plot part names fixed: Counter, Bench1, SupplyBoard are Parts holding their prompts; Sign.SurfaceGui.OwnerName; Exhibit slots get SlotIndex/Enabled; DecorSlots placeholder IDs; Spawn is a plain Part | Dev 3 |
| 2026-11-15 | CLAUDE.md §3, docs/03 §1/§3 | Client entry is `Main.local.luau`; Script Sync link instructions corrected | Dev 1 |
