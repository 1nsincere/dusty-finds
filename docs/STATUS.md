# STATUS: what's real right now

> Update after every feature. Claude Code reads this at the start of each session.
> Format: one line per item. Newest first inside each section.

**Current stage:** 1: Project setup
**Last updated:** 2026-11-15 by Dev 1 (Ace, with Claude Code)

## ✅ Done
- DataService (ProfileStore): loads profile on join (template from docs/03 §10.5, store `PlayerData_DEV` in Studio / `PlayerData_v1` live), Reconcile + migrate stub, kicks if session fails, ends session on leave. `DataService.Get/Set` for other services; `GetInitialState` returns a copy of the data. Tested in Studio Play: loads cash=100, Set works incl. nested paths, bad input rejected, and data persists across Stop/Play (cash 250 reloaded; Studio API access is now on). Not yet tested with 2 players or the session-failure kick. ProfileStore installed at `ServerScriptService.Packages.ProfileStore` (not synced, do not edit).
- Project skeleton boots with no errors: 11 server services + 9 client controllers load in the §4 order, each prints Init then Start once (checked in a Studio playtest). Remotes from 03 §6 are created by `Shared/Remotes.luau` (23 events + `GetInitialState`). All stubs have `DEBUG = true`; turn off when real code lands.
- Script Sync linked for `ServerScriptService.Server`, `ReplicatedStorage.Shared`, `StarterPlayerScripts.Client` ↔ `src/Server`, `src/Shared`, `src/Client` (verified two-way with test files).
- Studio MCP connected to place "Dusty Finds: Restore & Sell" (placeId 113871213495650).
- Team recorded in CLAUDE.md §0 and `docs/04` §G; game renamed to Dusty Finds in titles.

## 🔨 In progress
| Feature | Owner | Notes |
|---|---|---|
| Tooling setup (Team Create, Git, Claude Code, MCP) | All | Dwayne and Sean still need to link Script Sync on their PCs (see Notes) |
| Contracts: Types, Item Model Contract, UI contract, plot part names | Dev 1 / 2 / 3 | Remotes list is done (see skeleton) |

## 🐞 Known broken
- (none)

## 📝 Notes for the team
- **Script Sync linking:** right-click the Studio folder → Script Sync → Sync with Directory → pick the **parent `src` folder**. It creates `src/<FolderName>` itself. Picking `src/Server` makes a nested `src/Server/Server`. Stop an old sync before re-linking.
- **Client entry file is `Main.local.luau`** (a LocalScript). `Main.client.luau` is a Script with Client RunContext and runs twice inside StarterPlayerScripts.

## ⏭ Next up
1. Greybox plot model with named parts (Dev 3)
2. Wipe minigame prototype in test place (Dev 2)
3. Test DataService with 2 players (Test tab → Clients and Servers); then PlotService once Sean's Plot1 exists (Dev 1)
4. Test skeleton with 2 players (Test tab → Clients and Servers) and a phone emulator before Stage 2

## 📝 Contract changes log
| Date | File | Change | By |
|---|---|---|---|
| 2026-11-15 | CLAUDE.md §3, docs/03 §1/§3 | Client entry is `Main.local.luau`; Script Sync link instructions corrected | Dev 1 |
