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
Open Claude Code inside the `dusty-finds` folder and paste your prompt.

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
