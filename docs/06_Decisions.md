# 06: Feasibility Review, Technical Decisions, Assumptions, Open Questions

---

## 1. Feasibility review: what we simplified (and what we kept)

We reviewed every requested system against a three-person beginner team. The gameplay *experience* stays; the *implementation* gets simpler.

| Original idea | Risk for beginners | Simpler version we chose | Experience kept? |
|---|---|---|---|
| Unique restoration minigame per object | Dozens of scripts, endless bugs | **4 reusable modules → 6 interactions**, items differ by recipe + model | ✅ variety from data |
| Free 3D handling/rotation of items | Camera + input math, mobile pain | **Fixed bench camera**, tap/drag raycasts | ✅ hands-on feel |
| Dirt/rust painted on textures | EditableImage/shader complexity | **Decals on "spot" parts** that fade | ✅ visible transformation |
| Physics assembly of parts | Unstable, hard to debug | **Tap part → tap socket → tween** | ✅ satisfying snap |
| Rarity rolled per object instance | Hard to balance and show | **Fixed rarity per item type** + Golden variant | ✅ chase and discovery |
| Smart customer AI with pathfinding | Stuck NPCs, performance | **Waypoint paths + 6-state machine**, max 3 per shop | ✅ customers with wishes |
| Free building / placing furniture | Biggest feature in tycoons; save format, collisions, UI | **Fixed upgrade slots**, pre-built hidden rooms | ✅ visible shop growth |
| Private shops + inviting into instances | Teleports, reserved servers, edge cases | **6 plots on one server**, walk next door | ✅ visiting and show-off |
| Co-op restoration in MVP | Permissions and shared ownership logic | **Update 1**, after solo restoration is solid | ⏳ delayed, designed |
| Trading | Scams, dupes, policy | **Not planned** | n/a |
| Custom DataStore code | Data loss, duplication | **ProfileStore** (session locking) | ✅ safer |
| Haggling | Extra UI + balancing | **Update 1**; MVP has wish bonus + checkout bonus | ✅ light interaction |

**Biggest real risk:** art and content volume (20 item models with dirt spots, sockets, and polish surfaces). Mitigation: build Common items first, keep models simple and part-built, reuse decals, use Creator Store assets only with clear licenses, and consider Studio's AI generation tools for base meshes (then add our own spot parts).

---

## 2. Important technical decisions

| # | Decision | Why | Alternative / fallback |
|---|---|---|---|
| D1 | **Team Create + Studio Script Sync + Git (snapshots by Dev 1) + Claude Code** | Official, low-setup way to let Claude Code edit synced `.luau` files while the team collaborates live in Studio. No merge conflicts for 3D/UI. | **Rojo + Git**, each dev with a local place, PR merges. More robust for code merging, more setup. Switch if Script Sync (beta) causes problems. |
| D2 | **Roblox Studio MCP (built-in)** for inspection, console, and playtests; code edits via files | Claude can verify its own work (read errors, run playtests) while edits stay visible in Git | Copy Output logs manually into Claude Code |
| D3 | **Plain ModuleScript services/controllers with Init/Start**, no framework | Easy to read, easy for Claude to follow, nothing extra to learn | Knit-like frameworks (not needed) |
| D4 | **ProfileStore** for saving | Session locking, autosave, widely used, single ModuleScript | Raw DataStoreService with UpdateAsync (riskier) |
| D5 | **Server-authoritative economy; client-reported minigame scores, capped** | Real security where it matters (cash, items, rolls) without making minigames laggy | Server-simulated minigames (too complex) |
| D6 | **Config-driven content** (`Shared/Config`) | Add items, upgrades, crates without code changes; designers can edit | Hardcoded tables in services (fragile) |
| D7 | **State sync via `StateChanged(path, value)` + `ClientState` mirror** | One simple pattern for all UI updates | ReplicaService-style libraries (later if needed) |
| D8 | **Fixed-slot upgrades and hidden pre-built expansions** | Classic tycoon technique, very reliable | Free placement (Update 3) |
| D9 | **6 plots per server** | Enough social life, low NPC/part counts on mobile | 8 plots if performance allows |
| D10 | **One currency (Cash)** | Simple economy, no Robux confusion | None |
| D11 | **Separate DEV DataStore in Studio** | Never corrupt live data during testing | none needed |
| D12 | **Rarity colors and UI tokens defined once** (`Config/Rarities`, UI contract) | Visual consistency across screens | — |
| D13 | **Waypoint NPC movement** (Humanoid:MoveTo) | Predictable, cheap | PathfindingService |
| D14 | **ProximityPrompts** for world interactions | Built-in PC/mobile/console support | Custom click detection |

---

## 3. Assumptions
1. Team availability ≈ 8–10 hours per person per week for ~4–5 months.
2. Target audience 9–14 primary; PC + mobile at launch; console later.
3. The team will create a **Roblox group** to own the game and share revenue.
4. Art is simple and stylized (part-built models, decals, Creator Store assets with checked licenses, Studio AI tools where useful).
5. Audio comes from the Creator Store (licensed for use) or is made by the team.
6. Script Sync remains available and stable enough (it is a **beta**); fallback D1.
7. Studio MCP is available on all three PCs (it's built into current Studio).
8. Economy numbers are starting points and will change after playtests.
9. English-only at launch; UI built to allow translation later (no text baked into images).

---

## 4. Unresolved decisions (decide in Stage 1 unless noted)
| # | Question | Options | Suggested default |
|---|---|---|---|
| U1 | Who is the **integrator / Git committer**? | Dev 1 or rotating | Dev 1 |
| U2 | Revenue split and group ownership | equal thirds, by contribution | Equal thirds, written down |
| U3 | Free Delivery interval | 2 / 3 / 5 min | 3 min, tune in playtests |
| U4 | Should Quick Sell exist at 70% or lower? | 60–80% | 70% |
| U5 | Can solo players use the Back Room bench for a 2nd item? | yes (alternate benches) / co-op only | Yes, but one active restoration at a time per player |
| U6 | Golden variant rate | 1–3% | 2% |
| U7 | Level cap in MVP | 15 / 20 | 15 |
| U8 | Music style | lo-fi cozy / upbeat shop jingle | lo-fi cozy, mute option |
| U9 | Game icon & final art direction pass | team vote | Use the concept screenshots as reference |
| U10 | Server size final | 6 / 8 | 6, test 8 in Stage 10 |
| U11 | Update 1 priority order | co-op, Antique tier, haggling, daily crate | Decide after soft-launch feedback |
| U12 | Script Sync vs Rojo | see D1 | Try Script Sync for 1 week in Stage 1; switch early if painful |
