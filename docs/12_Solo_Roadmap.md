# 12. Solo Roadmap: Warehouse Market, collecting and gentle monetization (proposal, needs Ace's OK per stage)

> Written 2026-11-25. For Ace + Claude working alone (Sean and Dwayne are paused; hand-off notes are marked "if they return").
> Nothing here is built or priced. Robux items need Ace's explicit approval (CLAUDE.md §6.6). Trading is OFF for now (see Stage 8).
> Builds on docs/10 (stock shop and skins) and docs/11 (monetization plan). Where they disagree, this page records the newer decision.

## The head-of-product view in six lines
1. **Retention first, money second.** A Robux that is spent comes from a player who came back on day 7. Stage 1-4 make people stay; Stage 5 lets some of them pay.
2. **Monetize inside the world, never in their face.** Sell from stalls and from the Edit Mode Style button, not pop-ups. Visitors see cosmetics, which advertises them for free.
3. **Two roads to every cosmetic:** cash from the stock rolls (slow) or Robux from the Collector's Corner (instant, fixed price, never random).
4. **Auras and titles are earned; VIP only changes their style.** If a pass could buy rank, rank would mean nothing.
5. **Measure before you push.** Instrument the funnel in Stage 2 (before any Robux exists), so Stage 5 decisions use real numbers.
6. **Ship small and often.** Every stage ends with something playable, committed and tested on a phone.

## Stage 0: Housekeeping (about 1 day)
- Commit the pile of uncommitted work in three logical commits: restoration UI/camera, customers/haggling/edit mode server, Warehouse market + docs. Save the Studio place.
- Delete the leftover duplicate `Workspace.Scene` imports (ask first) and stray backups once the market is signed off.
- Resolve the open design answers in section "Decisions" below and tick them in this file.
- **Exit:** clean `git status`, STATUS.md current, one-page decisions list approved.

## Stage 1: Make what exists solid (about 1 week)
- Human-verify the restoration fixes (polish restart, tool speed, missing-part markers, full Lava Lamp playthrough) and customers (hesitation, queue, haggle).
- Play-test the Warehouse: stairs, upper floor, Supply and Skins prompts, 2-player visit.
- Re-run DevTools `testAll`; fix anything red.
- **Exit:** a 15-minute play session with no bug you would be embarrassed by. This is the base everything else sits on.

## What already exists (found 2026-11-25, built by Sean; do NOT rebuild)
- `Shared/Config/Skins.luau` (shelf, pedestal and cashier skins, Common to Mythic, colour/material looks AND model skins with auras), `Shared/Config/Stock.luau` (restock every 300 s, chance per rarity), `Shared/Stock.luau` (the roll: a pure function of the restock number, so server and every client get the same list with no network traffic), `SkinService` (buy, apply, draw), `SkinShopController` + `SkinModelController` (window, model skins), data field `skins = { owned, shelf, pedestal, cashier }`, `SkinCheck` (29 tests).
- **So the stock is currently SHARED: everyone sees the same stock at the same time.** That is the social version (friends talk about "the Cosmic shelf is in!"). The earlier decision "per-player rolls" is therefore changed to a recommendation: KEEP shared stock (see Decisions).

## Stage 2: Extend, measure, and add the data we still need (about 1 week)
- **Analytics (rbx-instrument-analytics skill):** funnel (join, first restore, first sale, first stock buy), economy events, store views. The numbers start collecting before any Robux exists.
- **Colourway variants (config only):** `Skins.LIST` entries get `family` (e.g. "Machuca") and `colorway` ("Terracotta", "Teal", "Navy"). The roll already picks ONE skin per kind and rarity from a pool, so with 3 colourways in the Legendary pool only one is in stock at a time: the "wait for the colour you want" feeling comes for free.
- **First Filipino families as `look` tables (no new models needed):** Rattan, Narra, Capiz, Machuca, Banig, Inabel, Jeepney, as colour + material + trim looks; model skins can follow later through the Blender pipeline.
- **Data template (ask Ace first), small:** `paints = { owned = {}, wall = "", floor = "" }`, `wishlist = {}` (skin ids to notify about, max 5), `entitlements = {}` (passes, written only by the server after a Marketplace check), `vip = { title, pet, petColor, auraStyle }`. Collector score and aura tier are DERIVED from existing data, so nothing is saved for them.
- **New remotes (docs/03 section 6):** `RequestBuyPaint`, `RequestApplyPaint`, `RequestSetWishlist`; the VIP and Robux ones wait for Stage 5.
- **Tests:** extend `SkinCheck` for colourway pools and wishlist; new `PaintCheck`.
- **Exit:** a colourway shows in stock, can be bought and applied; wishlist notifies; analytics events appear in `testAll`/Output.

## Stage 3: Market MVP, no Robux (about 2 weeks)
- **Paints:** Paint Bar buy/apply screen (wall and floor colours with the Filipino food names), client-only **Preview** (60 s try-on).
- **Market stalls:** point the existing `SkinShopController` at the new Skins Booth counter (already moved) and add the Shelves & Pedestals and Paint Bar prompts; restock countdown on a sign; wishlist toast.
- **Decor rooms (Cozy Living, Kitchen Nook, Gallery & Study):** only after paints work; needs edit-mode placement rules (docs/10 build step 4).
- **Exit:** a new player can buy a skin or paint with cash, apply it, and see it in their shop and in a visitor's view.

## Stage 4: Collector score and auras (about 1 week)
- Server computes the **collector score** (rarity points of unique items + Collection Book % + shop rating). No RAP; no trading.
- Tiers: Dusty, Polished, Brass, Gilded, Radiant. Client renders aura with a "hide others' auras" toggle, distance cull, Reduce Effects respected.
- **Exit:** 2-player test; both see each other's aura; phone frame rate is fine.

## Stage 5: Gentle monetization soft launch (about 2 weeks)
Only after Stage 3-4 feel good and the funnel shows people reaching a stock buy.
- **Collector's Corner** (always-available fixed-price stall, Rare to Legendary pieces).
- **Passes (phase 1):** 2 Themes, Glow Pack, Saved Layouts (3), Shopkeeper's Companion, Big Storage; **tip jar**.
- **VIP pass:** pet (3 choices + colour), filtered title, aura **style**, nameplate colour, chat tag, +1 saved layout. Never cash, XP, speed or odds.
- Server-side `MarketplaceService` receipts, idempotent grants, `entitlements` in the profile, prices in ConfigService.
- **Exit:** buy a pass with a test account, rejoin, still owned; refund path tested; docs/11 §12 policy checklist ticked.

## Stage 6: Content and live ops (ongoing, 2 to 3 weeks per drop)
- Legendary/Mythic/Secret colourways (3 each): Capiz Glass, Machuca Tiles, Jeepney Chrome, Inabel.
- Seasonal drops that come back yearly: Parol Night (Dec), Fiesta bunting (May), Sakura (spring). Honest "returns next year", no countdown panic.
- Secret tier earned through milestones; a fixed Robux price is optional and approved separately.
- **Gifting** (developer product + unboxing show) and **Bundles** ("Shop Makeover").

## Stage 7: Review and tune (monthly)
- Read the numbers: D1 above 35%, D7 above 12%, paying share 1 to 3%, preview-to-buy above 8%, gift share above 10%, complaints near 0.
- Reprice, retire or rotate what did not sell. Only then consider Amber items ("Restock now") with guard rails, and the Patron subscription.

## Stage 8: Trading (later, only if wanted)
Needs its own plan: anti-scam confirmation screens, no Robux-for-item, value display off by default, rate limits, server-validated swaps. Do not start before Stage 7 data says players ask for it.

## Decisions (tick when answered)
- [x] Trading off for now.
- [x] Collector score instead of RAP.
- [x] Aura tier is earned; VIP picks only the style.
- [x] Robux road: Collector's Corner fixed purchases, no skip-wait (Ace, 2026-11-25). "Restock now" stays an Amber idea for Stage 7 only.
- [x] Secret tier: milestone-earned only (Ace, 2026-11-25).
- [~] Stock: shared 5-minute clock (Ace, 2026-11-25). "Per-player rolls" is REVISED: Sean's system already shares one stock for everyone, which is more social and already tested. Recommendation: keep shared, no pity counter. Ace to confirm.
- [x] VIP perks (pet, filtered title, aura style, nameplate colour + chat tag, +1 saved layout, VIP market corner), starting price 399 R$ (Ace, 2026-11-25; price is a config value and can change).
- [ ] Approve data-template change (needed before Stage 2) and the price ladder (needed before Stage 5).

## Risks and how we handle them
| Risk | Plan |
|---|---|
| Too much at once for two people | Stages ship independently; each ends committed and tested. Skip Stage 6 content if time is short |
| Models are the slow part | Blender pipeline already works (warehouse took one session); reuse parts, 2 families first |
| Feels pay-to-win | Rules in docs/11 §2 and §11 never change; review every new product against them |
| Phone performance | Part/effect budget in Stage 3-4, test with the Device Emulator each stage |
| Data bugs lose purchases | Idempotent receipts, server-owned data, `testAll` coverage before Stage 5 |
| Burnout / drift | One feature at a time; update STATUS.md after every stage |

## If Sean and Dwayne return
- Sean: stall buy screens (Stage 3) and the Style picker, using the existing WindowKit.
- Dwayne: family models and colourways (Stage 4/6), following the Blender pipeline in docs/Blender_Pipeline.md.
