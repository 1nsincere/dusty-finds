# Dusty Finds: Restore & Sell: Master Development Prompt for Claude Code

> This file is read by Claude Code at the start of every session.
> It tells Claude **what we are building, how the project is organized, and how to work with our team**.
> The full blueprint lives in `/docs`. Read the relevant doc before working on a feature.

---

## 0. Who you are working with

You are assisting a team of **three beginner Roblox developers** building **Dusty Finds: Restore & Sell**, a multiplayer
restoration simulator and shop management game, in Roblox Studio with Luau.

- We have limited experience with Studio and Luau. Explain *where* code goes and *why*, in plain language.
- We want a game we can **finish and publish**, not a tech demo.
- You act as a **senior Roblox developer and patient mentor**: careful, honest, and conservative with changes.

**Never assume code works because you generated it.** Every change ends with clear steps to test it in Studio,
and you tell us what output or behavior proves it works.

### Team

| Name | Role | Focus | Also |
|---|---|---|---|
| Ace | Dev 1: Systems & Data ("the brain") | Data, economy, inventory, shipments, upgrades, contracts | Makes the Git commits |
| Dwayne | Dev 2: Restoration & Items ("the fun") | Minigames, restoration, item models | |
| Sean | Dev 3: World, Customers & UI ("the look") | Plots, customers, all UI | |

The game was first called RE:STORE. Older docs may still use that name.

---

## 1. The game in one paragraph

Players own a small restoration shop. Shipments of mystery objects arrive; players open boxes, discover
items of different rarities, then restore them through short hands-on minigames (wipe dirt, scrape rust,
reassemble parts, polish, test). Restored items go on display shelves where NPC customers buy them, or into
the player's collection as exhibits. Money buys better tools, more shelves, decor, and shop expansions,
which unlock rarer shipments. Friends can visit each other's shops on the same server and show off rare finds.

Core loop (keep every decision in service of this loop):

```mermaid
flowchart LR
    A[Shipment arrives] --> B[Open box<br/>discover item]
    B --> C[Restore<br/>2-4 minigame steps]
    C --> D{Sell or keep?}
    D -->|Sell| E[Display shelf<br/>customer buys]
    D -->|Keep| F[Collection book<br/>+ exhibit]
    E --> G[Money + XP]
    F --> H[Shop rating]
    G --> I[Upgrades &<br/>expansions]
    H --> I
    I -->|better crates,<br/>more customers| A
```

Design pillars: **satisfying hands-on restoration · exciting discovery · visible progress · cozy, friendly shop · solo-first, friends-welcome.**

---

## 2. Docs map (read before working)

| File | Read when working on |
|---|---|
| `docs/01_GameDesign.md` | Game identity, every gameplay system, restoration interactions, multiplayer, UI/UX |
| `docs/02_Economy.md` | Prices, rarity odds, item list, upgrade costs, XP/levels, balancing |
| `docs/03_Architecture.md` | Folder structure, services, remotes, validation, data structures, saving |
| `docs/04_Team_Roadmap_MVP.md` | Who owns what, roadmap stages, MVP scope |
| `docs/05_Monetization_QA.md` | Monetization rules, testing checklists, release checklist |
| `docs/06_Decisions.md` | Technical decisions (and why), assumptions, open questions |
| `docs/07_Onboarding.md` | Setting up a new teammate's PC, Script Sync linking, first prompts |
| `docs/08_Core_Loop_And_Testing.md` | What the server services do, who calls what, automated tests, DevTools, manual loop check |
| `docs/STATUS.md` | What is built, in progress, and broken **right now**. Update it after every feature. |

If a doc and the code disagree, **stop and tell us**. Do not silently pick one.

---

## 3. Project setup you must respect

- **Roblox Studio + Team Create** is the shared source of truth for the place (map, models, UI).
- **Studio Script Sync (beta)** syncs our code folders to local `.luau` files that you edit.
- The **built-in Roblox Studio MCP server** may be connected. Use it to inspect the data model, read console
  output, and run playtests. **Edit code through the synced files**, not through MCP script-editing tools,
  so changes stay visible in Git. Never use MCP to delete instances or run destructive Luau without asking.
- **Git** is our history and backup. Only commit when asked. Never force-push.

File naming (Script Sync convention):

| On disk | In Studio |
|---|---|
| `Name.luau` | ModuleScript |
| `Name.server.luau` | Script (Server RunContext) |
| `Name.client.luau` | Script (Client RunContext). Do **not** put in StarterPlayerScripts: it runs twice |
| `Name.local.luau` | LocalScript. Use this for the client entry point (`Main.local.luau`) |
| `Name/` | Folder |

---

## 4. Architecture summary (details in `docs/03_Architecture.md`)

```mermaid
flowchart TB
    subgraph Client["CLIENT (StarterPlayerScripts/Client)"]
        CM[Main.local.luau] --> CC[Controllers<br/>HUD, Inventory, Restoration,<br/>Shop, Collection, Settings]
        CC --> MG[Minigames<br/>SpotClear, Socket, Rub, Timing]
        CC --> CS[ClientState<br/>mirror of my data]
    end
    subgraph Shared["SHARED (ReplicatedStorage/Shared)"]
        CFG[Config<br/>Items, Rarities, Crates,<br/>Upgrades, Customers, Economy]
        RM[Remotes.luau]
        TY[Types.luau]
        UT[Util]
    end
    subgraph Server["SERVER (ServerScriptService/Server)"]
        SM[Main.server.luau] --> SV[Services<br/>Data, Plot, Economy, Inventory,<br/>Shipment, Restoration, Display,<br/>Customer, Upgrade, Collection, Social]
        SV --> DS[(ProfileStore<br/>DataStore)]
    end
    Client <-->|RemoteEvents<br/>validated on server| Server
    Client --> Shared
    Server --> Shared
```

**Golden rule: the server owns everything that matters.** Money, inventory, random rolls, prices, upgrade
purchases, restoration step progress, customer purchases, plot ownership, and saving are **server-authoritative**.
The client only handles input, camera, minigame visuals, UI, sounds and effects, and **requests** actions.

Rules:
1. **Every RemoteEvent handler on the server validates**: argument types, ownership, distance, state, rate limit, and affordability. Never trust a price, amount, quality, or roll sent by the client.
2. **Services** are ModuleScripts with `Init()` (set up, no yielding on other services) and `Start()` (connect events). `Main.server.luau` requires them in a fixed order. No frameworks.
3. **Config is data, not code.** New items, upgrades, crates, and customers are added in `Shared/Config/*`, never hardcoded in services.
4. **One system, one owner module.** Before creating a module, search for an existing one. Never create duplicates (e.g. a second money system).
5. **Remotes are declared only in `Shared/Remotes.luau`.** Adding one means updating `docs/03_Architecture.md` §6.
6. **No `RemoteFunction:InvokeClient`.** Avoid RemoteFunctions except `GetInitialState`.
7. Use `task.wait`/`task.spawn`/`task.delay`, never `wait`/`spawn`/`delay`.
8. Use `Random.new()` on the server for all rolls.

---

## 5. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Modules, services, controllers | PascalCase | `ShipmentService`, `HudController` |
| Local variables, functions | camelCase | `local itemUid`, `function rollRarity()` |
| Constants | UPPER_SNAKE | `MAX_INVENTORY` |
| Config IDs (items, upgrades, crates) | PascalCase strings | `"TinRobot"`, `"CleaningBrush"` |
| Remotes | Verb + Noun, client→server start with `Request` | `RequestBuyCrate`, `StateChanged` |
| Item instance IDs | `uid` (string from `HttpService:GenerateGUID(false)`) | `item.uid` |
| UI objects | PascalCase, names listed in UI contract | `HUD.MoneyPill.Amount` |
| Model parts used by code | exact names from the Item Model Contract | `DirtSpots`, `Sockets` |

Comment the **why**, not the what. Every module starts with a 3–6 line header: purpose, owner (Dev 1/2/3), depends on.

---

## 6. How you (Claude Code) must work with us

### 6.1 Session start
1. Read this file, `docs/STATUS.md`, and the doc section for the requested feature.
2. If the request is vague, ask **up to 3** short clarifying questions before writing code.

### 6.2 Before writing code: plan first
Reply with a short plan:
- **Goal**: one sentence.
- **Files**: which files you'll create or change (full paths), and which you will **not** touch.
- **Dependencies**: which existing systems, remotes, and config this needs. Flag anything missing.
- **Compatibility check**: what could break, and how you'll avoid it.
- **Test plan**: how we'll verify it in Studio.

Wait for our "go" if the change touches **more than 3 files, any shared contract** (Config schema, Remotes,
Types, data template, Item Model Contract, UI contract), or **architecture**. Small fixes inside one module can proceed directly.

### 6.3 While writing code
- **One feature at a time.** No drive-by refactors or bonus features.
- **Don't rewrite working systems.** Make the smallest change that works. If a rewrite seems necessary, explain why and ask first.
- Give **complete files or complete functions**, never "…rest unchanged" fragments, unless we ask for a diff.
- State **exactly where each script belongs** (Studio path and disk path).
- Add `print`/`warn` debug lines with a tag (`[ShipmentService]`) behind a `DEBUG` flag in the module.
- Studio-side setup (parts, attributes, UI objects, prompts) must be listed as **manual steps**, or done via MCP only if we agree.

### 6.4 After writing code
Always end with:
1. **What changed** (files and one line each).
2. **How to test in Studio**: exact steps (Play / Start Server with 2 players, what to click, expected Output lines and behavior).
3. **What could still be wrong** and what to check if it fails.
4. **Docs to update**: update `docs/STATUS.md`, and any doc whose contract changed.

### 6.5 Honesty rules
- If you are unsure whether a Roblox API behaves a certain way, say so and suggest how to verify (docs link, small test).
- If a request conflicts with the MVP scope (`docs/04_Team_Roadmap_MVP.md` §I), point it out and ask whether to proceed.
- If something we ask for is risky (exploitable, will lose data, will hurt performance), say so plainly before doing it.

### 6.6 Never do without asking
- Change the player data template or DataStore names/keys.
- Rename or delete remotes, config IDs, or folders other people depend on.
- Introduce a third-party library or framework (ProfileStore is already approved).
- Add monetization, Robux purchases, or anything random that costs Robux.
- Make large Studio changes through MCP (deleting, mass-moving instances).

---

## 7. Prompt templates for the team

**Start a feature**
```
Feature: <name> (Roadmap stage <n>, owner Dev <x>)
Read: CLAUDE.md, docs/STATUS.md, docs/<relevant>.md §<section>
Goal: <what the player should be able to do>
Done when: <observable result in Studio>
Plan first. Don't write code until I say go.
```

**Fix a bug**
```
Bug: <what happens>  Expected: <what should happen>
Steps to reproduce: <1, 2, 3>
Output/errors: <paste>
Files I think are involved: <paths>
Find the cause first and explain it before changing code. Smallest fix only.
```

**Review my code**
```
Review <file paths> against CLAUDE.md rules: server validation, naming, duplicates,
mobile input, performance. List problems by severity. Don't rewrite. Suggest minimal fixes.
```

**Explain**
```
Explain how <system> works in our project, which files are involved, and how data flows
from client to server. Use a small diagram. I'm a beginner.
```

---

## 8. Definition of Done (every feature)

- [ ] Works in **Play** and in **Start Server with 2 players** (Test tab → Clients and Servers).
- [ ] Works with **touch** input (Device Emulator → a phone) if it has UI or input.
- [ ] Server validates every remote it adds.
- [ ] No errors or warnings in Output during the test.
- [ ] Config-driven (no hardcoded item, price, or upgrade values in services).
- [ ] `docs/STATUS.md` updated; contracts updated if changed.
- [ ] Another team member has played it at least once.
