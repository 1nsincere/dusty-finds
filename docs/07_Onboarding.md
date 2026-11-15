# 07: Onboarding (Dwayne and Sean start here)

Dusty Finds: Restore & Sell. Team: Ace (Dev 1), Dwayne (Dev 2), Sean (Dev 3). See CLAUDE.md §0.

## Part 1: One-time setup on your PC
1. Ace invites you to the Team Create place **Dusty Finds: Restore & Sell** (placeId 113871213495650). Open it in Roblox Studio.
2. Install **Git** and **Claude Code**.
3. Clone the repo:
   ```
   git clone https://github.com/1nsincere/dusty-finds.git
   cd dusty-finds
   ```
4. In Studio: **File → Beta Features**, tick **Script Sync**, restart Studio.

## Part 2: Link Script Sync (3 folders)
For each folder: right-click it in the Explorer → **Script Sync → Sync with Directory** → pick the **parent `src` folder** of your clone (for example `C:\...\dusty-finds\src`).
- `ServerScriptService → Server`
- `ReplicatedStorage → Shared`
- `StarterPlayer → StarterPlayerScripts → Client`

Rules:
- Always pick `src`, never `src\Server`. Picking the inner folder creates a nested `Server\Server`.
- Run `git pull` before linking so your files match the place.
- If a dialog says "Instances in Studio don't match files on disk", stop and ask Ace before clicking anything.
- Never press **Keep Disk version** with an out-of-date clone.
- To re-link a folder, stop its old sync first.
- Untested with several people at once on Team Create. Try with one person first.

## Part 3: Check it works
Press **Play**. Output should show every `[...Service] Init/Start` line, then `[Main] server ready, 11 services started` and `[Main] client ready, 9 controllers started`. No red errors or yellow warnings.

## Part 4: Daily rules
- Edit only your own files (`docs/04_Team_Roadmap_MVP.md` §G).
- Ace commits code. Others may commit docs only.
- Ask the owner before changing shared files: Remotes, Config, Types.
- Update `docs/STATUS.md` after each feature.
- The client entry file is `Main.local.luau` (LocalScript). Do not use `.client.luau` inside StarterPlayerScripts: it runs twice.

## Part 5: First prompt for Claude Code
Open a terminal in the `dusty-finds` folder, run `claude` (Claude Code) or `codex` (Codex users: it reads `AGENTS.md`, which points to `CLAUDE.md`), and paste your prompt.

**Dwayne (Dev 2):**
```
I'm Dwayne, Dev 2 (Restoration & Items). I'm a beginner.
Read CLAUDE.md, docs/STATUS.md, and docs/04_Team_Roadmap_MVP.md section G (my role)
and docs/01_GameDesign.md (restoration minigames).
Then tell me in plain language:
1. What the project is and what is already built.
2. Which files and systems are mine, and which I must not edit.
3. What I should start on first, and why.
Give me a short plan only. Don't write code until I say go.
```

**Sean (Dev 3):**
```
I'm Sean, Dev 3 (World, Customers & UI). I'm a beginner.
Read CLAUDE.md, docs/STATUS.md, docs/04_Team_Roadmap_MVP.md section G (my role)
and docs/03_Architecture.md sections 2 and 8 (plot parts and UI contract).
Then tell me in plain language:
1. What the project is and what is already built.
2. Which files and systems are mine, and which I must not edit.
3. What I should start on first, and why.
Give me a short plan only. Don't write code until I say go.
```

Expected starting points (from STATUS "Next up"): Dwayne builds the Wipe minigame prototype in an isolated test place; Sean builds the greybox plot model with named parts.

## Part 6: Starting each later feature
```
Feature: <name> (Roadmap stage <n>, owner Dev <x>)
Read: CLAUDE.md, docs/STATUS.md, docs/<relevant>.md §<section>
Goal: <what the player should be able to do>
Done when: <observable result in Studio>
Plan first. Don't write code until I say go.
```

---

## Part 7: Your first tasks (step by step)

Always say "plan first, wait for go" (CLAUDE.md §6.2). If Claude proposes touching a file you don't own, stop and ask Ace. Ace makes the code commits.

### Dwayne (Dev 2): Wipe minigame prototype
**Goal:** wipe dirt spots off one item with mouse and touch, in a separate test place.
**Done when:** a Dirty item clears with mouse **and** touch with no errors. Next: bench camera, then Polish.

| Step | What to do | Prompt for Claude Code |
|---|---|---|
| 1 | Learn the design | `Read docs/01_GameDesign.md (restoration section) and docs/03_Architecture.md §11. Explain the Wipe interaction and the data flow in plain words with a small diagram. No code.` |
| 2 | Read the contract | `Read the Item Model Contract in docs/01_GameDesign.md §C2 and the final part names table under it. Explain in plain words what folders and part names an item model needs, using the Rubber Duck and Toy Car as examples. Don't write code.` |
| 3 | Test place | Create a new, empty Roblox place (not the main one). Add a baseplate and one simple item model that follows the contract. |
| 4 | Build Wipe | `Feature: Wipe minigame prototype (Stage 4, Dev 2). Read CLAUDE.md, docs/STATUS.md, docs/03 §3 and §11. Goal: mouse or touch rubs dirt spots off one item. Done when: all spots clear, a progress bar fills, works with mouse and phone emulator. Plan first.` |
| 5 | Test | Play and wipe the item, then use Device Emulator → a phone and repeat. |
| 6 | Report | `Update docs/STATUS.md with what works. Then list what could still be wrong.` |

### Sean (Dev 3): Greybox plot
**Goal:** a plain grey shop plot with every part named as in `docs/03_Architecture.md` §2, then 6 plots.
**Done when:** the part-name check passes on all 6 plots, and plots are small enough to walk around on a phone.

| Step | What to do | Prompt for Claude Code |
|---|---|---|
| 1 | Learn the layout | `Read docs/03_Architecture.md §2 and docs/04 Stage 2. List every named part a Plot needs and what each is for. Explain how PlotService will use them. No code.` |
| 2 | Build Plot1 | In Studio (main place, via Team Create) build `Workspace/Plots/Plot1` from plain grey parts named exactly as §2: `Spawn`, `Sign`, `Counter`, `Benches/Bench1`, `DisplaySlots/Slot1..12`, `ExhibitSlots`, `DeliveryPoint`, `SupplyBoard`, `CustomerPath`. Anchor every part. |
| 3 | Check names | `Use the Studio MCP to inspect Workspace.Plots.Plot1 and compare it with docs/03 §2. List missing or misnamed parts. Don't change anything.` |
| 4 | Copy to Plot6 | Duplicate it five times and rename to `Plot2` ... `Plot6`. |
| 5 | Report | `Update docs/STATUS.md with what is built.` |

### Item Model Contract
It is written in `docs/01_GameDesign.md` §C2, with the 15 final restoration part names under it (decided by Ace). Build item models exactly to it; ask Ace before changing a name.

When stuck, paste the Output errors and use the "Fix a bug" template from CLAUDE.md §7.
