# 13: NPC life brief (for Dwayne + Codex)

> Written 2026-11-26 by Ace + Claude for **Dwayne** (Dev 2) to work through with **Codex**. Read `CLAUDE.md` and `docs/STATUS.md` first.
> Goal: the town and the shops should feel **alive**, so a solo player never feels lonely. Customers queue, wait, get annoyed, haggle, and leave
> reviews. Townsfolk walk real paths, chat at the plaza and use the vendors. Stores become real buildings with a cashier. A night robber is the twist.
>
> **Honesty note:** items marked (seen) were read in the code by Claude; everything else is Ace's intent. Claude did NOT open every file named
> here for this brief. Verify the file and function names yourself before you plan around them.

---

## 0. How Dwayne and Codex work together

- **Codex edits the synced files** (`src/...`). **Dwayne runs Studio**: Play, 2-player test, screenshots, console output. Codex cannot see Studio,
  so Dwayne pastes console output / describes what he sees after every test.
- **Plan first** (CLAUDE.md §6.2): for each work package below, Codex writes a short plan (goal, files, remotes/config touched, tests) and Dwayne
  says "go". One package at a time. No drive-by refactors.
- Studio-side work (building meshes into real buildings, moving parts, placing nodes) is **manual or via the Studio MCP and needs Ace's OK**.
  Codex must list those steps as manual instructions, never assume they happened.
- Ace makes the Git commits. Update `docs/STATUS.md` after every package. New remotes go in `Shared/Remotes.luau` and `docs/03_Architecture.md` §6.
- **Ask Ace before:** changing the player data template (`DataService.TEMPLATE`), adding or renaming remotes / config ids / folders others use,
  anything monetized. Reviews/consequences below may need a data field: stop and ask.

## 1. What exists today (verify)

**Customers (server).** `src/Server/Services/CustomerService.luau` (seen): customer records per shop; `TrySpawn`, `Tick`, `Sweep`, `ChooseItem`,
`Judge`, `HaggleOffer`, `SetNoTip`, `SetPriceMult`, `Reconsider`, `Checkout`, `Leave(reason)`; `MAX_CUSTOMER_SECONDS` (420 s) removes stuck
customers; spawn handler / removed handler hooks (`SetSpawnHandler`, `SetRemovedHandler`). Arrivals stop while the shop is closed (HoursService).
**Customer bodies.** `CustomerNpcService` (seen in logs: "walks into Plot1", "gave up waiting at the till", "removed: impatient") and the client
`CustomerUIController` (thought bubble with the wanted category) and `CashierController` / `CashierService` (the till: count out the change).
**Shop path markers** (seen, per plot, `Plots.PlotN.CustomerPath`): `StreetEntry`, `Approach`, `Door`, `Browse1..3`, `CounterSpot`, `Exit`
(+ `Spawn`, `Counter`, `DeliveryPoint` on the plot). The door faces the street; `HoursService` builds a roll-down `ShopShutter` there.
**Ambient town.** `TownsfolkController` (seen in logs: "36 townsfolk on 34 routes (8 looks), shared clock"): client-side, deterministic from
server time so all players see the same people. `JeepneyService` / `TricycleService` + `Lib/TrafficRules` (seen): vehicles on loops with stops.
**Time + opening hours.** `Shared/Hours.luau` + `HoursService` (seen): game clock (20 min day), shops take customers 7:00-19:00 game time,
`Workspace` attributes `ShopOpen` / `MarketOpen`, shutters closed at night. Shutter collision: only that shop's owner passes (`Lib/AccessGroups`).
**Stores / market.** The market hall and town stores are **Blender meshes** (`assets/models/WarehouseMarket.glb`, `Stores.glb`) with invisible
`WalkCollision` proxy parts. They are not "buildings" in the gameplay sense (no interior, no cashier, no NPC purchases).

## 2. Work packages (do them in this order; each ends with a Studio test)

### WP1: Customers line up and walk properly in shops
- A real **queue** at the till: numbered queue spots behind `CounterSpot` (config-driven offsets per plot, not hardcoded), customers wait in order,
  the next one steps up when the till is free, nobody stands inside another customer or the counter.
- Fix **pathway errors**: customers must not clip through shelves, walls or each other; they walk door -> browse spot(s) -> queue -> counter ->
  exit. Decide: `PathfindingService` with proper agent params, or the authored nodes already on the plot. Report which and why.
- If a path is blocked (player stands in the door, shelf moved), the customer re-routes or leaves politely; never freezes or spins.
- Test: 6 customers at once in one shop, 2 shops side by side, a player blocking the door.

### WP2: Patience, irritation, complaints, walking away
- Each waiting customer has **patience** (config per customer type in `Config/Customers.luau`). While waiting at the till or for service it
  drops; show it in stages: calm, fidgeting (emote / small animation), irritated (bubble "Ang tagal naman!" style, subtle Filipino), then **leaves**
  (walks out, `Leave("impatient")`). The existing 420 s cap stays as a safety net only.
- Waiting should be fair: the player can see who is about to leave (bubble colour / a small meter), and serving fast is rewarded (tip).
- Leaving angry affects the **shop rating** a little, never cash directly. Numbers in config, tune with `docs/02_Economy.md`.

### WP3: Haggling that can fail
- Customers who haggle (`HaggleOffer`) make an offer. If the **player declines**, there is a **chance the customer does not buy at all** and
  leaves (chance from config: higher for stingy types, lower for friendly). If the player accepts or counters within limits, they buy.
- The player must always see the real price, the offer and the consequence ("They may walk away"). No hidden randomness that costs Robux.
- All rolls on the server with `Random.new()`. The client only shows the offer and sends accept / decline.

### WP4: Critiques (reviews)
- Brainstorm with Ace first, then plan: what does a customer say after buying or leaving? Suggested: a short **review line** (config text pool per
  type and mood), shown as a bubble and logged to a small "Reviews" list in the shop window; good service = praise, long waits / refused haggle = a
  complaint. Reviews feed the **shop rating** slightly and give the plaza something to gossip about (WP5).
- A saved review history needs a data field: **ask Ace** (keep the first version in memory / last 10 lines per session).

### WP5: Townsfolk walk "right" and the plaza feels alive
- Replace free random wandering with **authored routes**: a waypoint graph (config data) over the map: streets, plaza, park, market entrance,
  shop doors, bus stops. NPCs only walk edges of the graph, never straight across meshes (warehouse, houses). One graph, one owner module.
- NPCs can **interact** at named points: sit on benches, buy from a vendor, chat in pairs (two NPCs face each other with bubble lines), feed the
  pigeons / watch the fountain, wait at the jeepney / tricycle stop and board. A small state machine per NPC: walk, idle, interact, repeat.
- **Make the plaza / park the busiest place**: more interaction points there, small crowd moments (a vendor shout, a street performer, kids
  playing) so it is fun to watch. Keep the shared-clock design (every player sees the same scene) unless it blocks a feature; if so, say so.
- Performance: phones first. Cap simultaneous NPCs, animate cheaply, no per-frame Pathfinding for ambient NPCs.

### WP6: Vendors interact with NPCs
- Vendor NPCs (food carts, stalls in the plaza) have an **interaction point** and a short loop: call out, serve, hand over. Walking NPCs and
  customers can walk to the vendor, "buy" (animation + bubble, cosmetic cash only, no economy effect unless Ace agrees), and walk away.
- Vendors react to the clock (set up in the morning, pack up at night, `Hours`).

### WP7: Stores as real buildings with a cashier (every store if possible)
- Turn the store **meshes** into real buildings: a walkable interior (collision, door, floor), a **counter with a cashier NPC** standing behind it,
  and **customer NPCs who walk in, browse and buy** from the store. Use the same queue and patience logic as WP1-2 (reuse, do not copy).
- **Limits Codex must flag:** the interiors and counters are Studio / Blender work (meshes, collision proxies, parts for `StreetEntry` /
  `Browse` / `Queue` / `CounterSpot` / `Cashier` markers). If a store has no usable interior, propose the cheapest fix per store and a priority
  order. If it is not possible for every store, do the **plaza stores first** and write the rest down in `docs/STATUS.md`.
- NPC purchases from stores are cosmetic / ambience unless Ace decides they pay the player-owned stores (they only pay **player** shops today).

### WP8: The night robber, the bunal and the consequence (design first!)
- **Twist:** shops close at 19:00 and normal customers stop. At night a **robber NPC** can break in (the roll-down shutter is the entry
  problem: the shutter is solid for non-owners today). Options for Dwayne to propose: the robber pries the shutter up a little (a short
  animation + warning sound), uses a back window, or the shutter keeps its look but has a server-only "breach" the robber uses. Change
  `HoursService` shutter code only through a small, tested function (e.g. `HoursService.Breach(plot)`), and keep the owner / visitor rules.
- The robber **steals an item**, with a **higher chance to target pedestal items** (the "flex" items) than shelf items. Weights from config.
- The owner fights back with a **bunal / walis tambo** (tool or prompt): hit / shoo the robber, who drops the item and runs away.
- **Open question (Ace and Dwayne have struggled with this): what is the consequence if the robber gets away with the item?** Audience includes
  kids and the rule is no pay-to-win and no cruel permanent loss. Claude's recommendation, to discuss:
  1. Stolen item becomes **"Stolen"** (cannot be sold or displayed) and is shown at the plaza's barangay tanod / lost-and-found post for a
     **recovery window** (for example 10 minutes of game time). The owner can walk there and **reclaim it for a small cash fee**.
  2. If nobody claims it, it **returns to the owner's inventory** with a small rating penalty, so it is never lost for good.
  3. Rare items (Epic and above) are **protected by a long recovery window** and a warning toast when the robber targets one.
  4. Never sell protection for Robux. A free "Lock" upgrade (shop alarm / guard dog) can lower the chance, bought with cash.
  A new item state (`Stolen`) is a data-schema question: **ask Ace before writing it** (a first version can hold the stolen item in server memory).
- Robber appears rarely, never on a player's very first sessions, and never steals the last item or a quest item. A toast warns the owner.

### WP9: Closed shops and the roll-down
- Current behaviour: shutter solid for everyone except the owner, visitors walked out. Dwayne may **modify or replace the roll-down visual** as long
  as these rules still hold (tests: `HoursCheck`): players cannot enter a closed shop (except the owner), normal customers do not arrive at night,
  and only the robber event can breach it.

## 3. Rules Codex must follow (from CLAUDE.md)

- The **server owns** anything that matters: customer state, prices, haggling rolls, theft, recovery. The client draws and sends requests.
- Every remote handler validates types, ownership, distance, state, rate limit. No `RemoteFunction:InvokeClient`.
- Config is data: new numbers, text pools, patience, weights, node positions go in `Shared/Config/*`, not in services.
- One system, one owner module. Search before creating. Services have `Init()` / `Start()`. Use `task.*`, `Random.new()`.
- Comment the why. Every module starts with a 3-6 line header (purpose, owner, depends on).
- Works in Play and "Start Server with 2 players", touch input if UI, no Output errors, `docs/STATUS.md` updated, tests added to `DevTools testAll`.
- The audience includes children: no scary violence (the bunal is a "shoo", cartoonish), no insults, Filipino flavour kept subtle.

## 4. Suggested order and definition of done

1. WP1 + WP2 (queue, patience): the player-visible fixes.  2. WP3 + WP4 (haggle, reviews).  3. WP5 + WP6 (town life).
4. WP7 (store buildings), starting with the plaza.  5. WP8 + WP9 (robber), after Ace answers the consequence question.
Each package is done when: a Studio test (Play + 2 players) passes, the new `*Check` tests pass in `testAll`, no Output errors, STATUS updated.

## 5. Paste this to Codex first

> You are helping Dwayne on a Roblox game called Dusty Finds (Luau, Script Sync). Read `CLAUDE.md`, `docs/STATUS.md` and `docs/13_NPC_Life_Brief.md`
> completely before doing anything. Work on ONE work package at a time, starting with WP1. For each package: reply with a short plan (goal, files you
> will create or change, remotes/config you touch, test plan) and wait for Dwayne to say "go". Follow every rule in section 3 of the brief. You cannot
> see Roblox Studio: tell Dwayne exactly what to test and what output to paste back. Do not change the player data template, remotes or shared config
> schemas without asking Ace first. If something in the brief does not match the code, stop and say so. At the end of each package list what changed,
> how to test it, what could still be wrong, and which docs to update.
