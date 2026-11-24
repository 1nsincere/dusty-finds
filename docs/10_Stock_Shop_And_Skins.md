# Stock shop, skins and furniture: idea assessment (draft for the team)

> Status: **idea / proposal, nothing built, not agreed yet.** Written 2026-11-24 by Sean with Claude Code after the
> team asked: "a shop with rotating stock (shelves, paints, skins for shelves and pedestals), and what can be moved in
> edit mode?" Builds on `docs/09_Edit_Mode_Plan.md` (edit mode, agreed). Decide the questions at the bottom first.

## The big picture: three parts that build on each other

| Part | What it does | Status |
|---|---|---|
| **1. Edit mode** | *Where* things stand in your shop | In progress (`docs/09`): Sean's part done, Ace's saving + customers next |
| **2. Furniture & skins** | *What* you own: pieces, styles, paints | New. Needs a "furniture box" in the player data |
| **3. Stock shop** | *How* you get them: a stall that restocks on a timer | New. A new stall in town |

Build them in that order: each one is useful alone, and each needs the one before it.

## 1. Edit mode: what moves, what stays

| Movable | Fixed (never moves) |
|---|---|
| Display shelves (with their slots and items) | Counter + the customer queue |
| Exhibit pedestals | Door / entrance, spawn, delivery spot |
| Decor bought in the stock shop (rugs, plants, lamps, fountain, fish tank) | Workbenches (Bench1, Bench2) |
| *(later)* wall items (posters, neon sign, clocks) that snap to walls | Storage room + its shelves, the stairs |
| | Walls, windows, Ace's building art, the Supply board |

Fixed = anything customers or the core loop depend on (moving the counter or benches would break customers and restoration).

Small rules that make it nicer:
- **Rugs are "flat":** they may lie under shelves and pedestals (don't count as an overlap).
- **Style in edit mode:** tap a shelf -> **Style** -> pick a skin you own. Edit mode is also where skins are changed.
- **A piece limit per shop** (e.g. 40 decor pieces) to keep phones fast.

## 2. Furniture & skins: what players own

| Kind | Examples | Notes |
|---|---|---|
| **Shelf skins** | Walnut, Mint paint, Coral paint, Brass trim, Antique crate | Owned forever, applied in edit mode |
| **Pedestal skins** | Marble, Velvet top, Wooden crate, Gold rim | Same |
| **Paints** | Wall colour and floor colour for the whole shop | Owned colours, one active at a time |
| **Decor pieces** | The 7 switched-off decor items + new ones | Placed with edit mode; give rating points |
| **Extra exhibit stands** | More pedestals beyond the gallery | Careful: exhibits give rating points |

**Economy guard rails (Ace):**
- Keep the **number of display shelves** coming from Upgrades -> Display Shelves; the stock shop sells shelf **styles**,
  not extra shelves (shelf count drives income).
- Rating points from decor: each decor type counts once (or with diminishing returns), so 30 plants don't buy 5 stars.

**Data (Ace):** a new `furniture` list (what you own, how many of each decor piece) and `skins` (which skin is on which
piece), separate from the item inventory.

## 3. The stock shop (restocking stall)

Our own version, not a copy of another game: a **flea-market vendor's stall** in town (cart + vendor NPC) where "new
stock arrives" every few minutes.

| Rule | Suggestion |
|---|---|
| **Restock timer** | Every 5 minutes, the **same clock for everyone on the server** ("Fresh stock in 2:14"): shared moments |
| **What's in stock** | Rolled on the server with `Random` (never the client). Commons almost always, rare skins sometimes, legendary ones very rarely |
| **How many** | Per player per restock, e.g. 1-3 of a common, 1 of a rare. Sold out = wait for the next restock |
| **Rarity** | Reuse the existing rarity colours (Common -> Legendary), players already know them |
| **Price** | In-game cash only. Robux skins = monetization: team decision first (CLAUDE.md) |
| **Level gates** | Some stock only appears from a level on, so the stall grows with the player |
| **Announcements** | "A Golden Pedestal skin is in stock!" server toast, rare stock only |
| **Config** | New `Shared/Config/Stock.luau`: every item, chance, amount, price, level (data, not code) |

Suggested stock from day one:
- **Always:** basic paints, a couple of common shelf / pedestal skins.
- **Often:** the old decor (rug, plants, posters, lamps).
- **Sometimes:** nicer skins (Brass trim, Marble), neon sign, fish tank.
- **Rarely:** the fountain, gold / "Golden" skins, seasonal pieces later.

## Suggested build order
1. **Finish edit mode** (move existing shelves and pedestals): Sean's part done, Ace's saving + customers next.
2. **Skins & paints** with the edit-mode Style button: no new placement problems, quick to show off.
3. **Stock shop stall:** restock timer, rolls, buy screen; sells skins, paints and the old decor.
4. **Placeable decor + wall items:** needs the "flat" and "wall" placement rules.

## Questions for the team
1. Is the stock shop the **only** place to get decor (the old Decor tab never comes back)?
2. Restock every **5 minutes for everyone** (suggested, more social) or per player?
3. **Cash only**, or will some skins ever cost Robux? (team decision first)
4. Are **extra exhibit stands** sold in the stock shop, or does the Showroom stay the only source of pedestals?
5. Who builds what? e.g. Ace: data + stock rolls (server); Sean: stall, buy screen, Style picker; Dwayne: skin models
   and textures.
