# 11. Monetization Plan: "Make them want it" (proposal, needs Ace's approval)

> Status: PROPOSAL, nothing in here is built or priced in the game. Per CLAUDE.md §6.6 nothing that costs Robux is added without Ace's explicit OK.
> Written 2026-11-25. Extends `docs/05_Monetization_QA.md` (K-rules). Where this page and docs/05 disagree, docs/05 wins until Ace approves the change in §10.

## 1. The idea in one paragraph

Players should buy because the shop becomes *theirs* and they love how it looks, never because the game cornered them. Our edge is that
Dusty Finds is a **show-off game**: you restore things, display them, friends visit your shop. So we sell **identity, beauty and
convenience**, make every product **visible to visitors** (free advertising), always let players **earn the same thing slowly with
in-game cash**, and put the price in plain view. Revenue comes from desire and pride, not pressure.

## 2. Rules that never change (the trust contract)

1. No pay-to-win: Robux never buys cash, XP, speed, better odds, or anything that earns more. (docs/05 K1)
2. Nothing random is sold for Robux, directly or through Robux-bought currency. (K2, K3)
3. No hidden or "forced" buying: no fake scarcity timers, no purchase prompts on spawn, no "your friend just bought…" nudges, no confusing
   currency tricks. Every price is shown in Robux, up front, with a Preview button.
4. Everything cosmetic can also be earned in-game; Robux is a *shortcut and a way to support us*.
5. Kid-safe: clear, calm store; parents can understand every item in five seconds.

Why this is also the best business decision: kids tell friends, parents leave good reviews and spend on games they trust, and Roblox
promotes experiences with high ratings and long play time (which also pays us through Premium engagement).

## 3. Who buys what

| Audience | What pulls them in | What we sell them |
|---|---|---|
| **Kids 9-14** | Cute pets, sparkles, gold effects, matching themes, gifts for friends | Pets, restoration effects, avatar items, theme sets, gifts |
| **Teens 14-17** | Aesthetic shops, rare-looking sets, showing off in Visit | Premium themes, fixture sets, Spotlight packs |
| **Adults** | Calm, tidy, convenient, a shop that looks great, supporting the devs | Storage, auto-sort, Patron subscription, supporter bundles, big themes |

## 4. The catalogue (prices are proposals)

### 4.1 Game Passes (one-time, permanent)
| Pass | Price | What it does | Pay-to-win check |
|---|---|---|---|
| **Theme: Retro Arcade** | 199 R$ | Walls, floor, sign, lighting style | Cosmetic; same rating points as free decor |
| **Theme: Cozy Cabin** | 199 R$ | Same | Cosmetic |
| **Theme: Sakura Night** (seasonal, returns yearly) | 249 R$ | Same | Cosmetic |
| **Fixture Set: Brass & Walnut** | 299 R$ | Matching shelf, pedestal, divider, counter | Cosmetic; same slots |
| **Exhibit Spotlights Pack** | 149 R$ | Coloured spotlights + confetti on exhibits | Visual only |
| **Golden Apron & Name Tag** | 99 R$ | Avatar cosmetic shown in your shop | Cosmetic |
| **Restoration Glow Pack** | 149 R$ | Gold cloth shimmer, rainbow polish sparkles, confetti unboxing | Visual only; same speed and score |
| **Big Storage Room** | 149 R$ | +16 inventory slots | Convenience, modest, also earnable by upgrades |
| **Shopkeeper's Companion** | 199 R$ | A pet that follows you and sits on your counter | Cosmetic |

### 4.2 Developer Products (repeatable)
| Product | Price | Notes |
|---|---|---|
| **Support the Shop (tip jar)** | 25 / 100 / 250 R$ | Thank-you toast + a "Supporter" plaque on your sign. No gameplay effect |
| **Gift a theme / fixture set to a friend** | same as the item | Opens a friend picker; the friend gets a nice unboxing of their gift |

### 4.3 Patron subscription (recurring, later)
**99-149 R$ per month** (check Roblox's current subscription rules before building): a Patron plaque, one exclusive cosmetic a month (never
required), +8 storage, an exclusive pet. Cancel any time, clearly explained.

### 4.4 Bundles
**"Shop Makeover" bundle** = theme + fixture set + Glow Pack at about 20% off the parts. Shown only inside the store, never as a pop-up.

## 5. How players come to WANT these (the clever, honest part)

1. **Visitors are the billboard.** Every pass is visible to anyone who visits (Visit window, Players list): themes, spotlights, pets, aprons.
   No ads needed; pride does the selling.
2. **Try before you buy ("Try it for 60 seconds").** Preview any theme or fixture set live in your own shop, then it reverts. Players fall
   in love with *their* shop in the new look. No trickery: a clear "Preview" button and a clear price.
3. **Collection sets with a visible gap.** Matching sets give bonus rating (cosmetic-only math, same points as free decor). A set with one
   empty slot makes completing it feel natural. Every piece also has an earn-it-with-cash path.
4. **Two roads to every cosmetic:** earn it (cash, slow) or support us (Robux, instant). Players who are not ready to spend still get
   there, and they remember it fondly, which brings the friends who do buy.
5. **Seasonal drops that return.** Sakura Night, Winter Lanterns, Retro Arcade: a new look every season, each coming back yearly. Honest
   message ("returns next spring"), no countdown panic.
6. **Gifting.** "Buy this for a friend" is warm, social and a proven earner. The gift unboxing is itself a show (we already have the
   Unboxing system).
7. **Delight loops that cost nothing:** a free daily cosmetic spin of a cosmetic from a free pool, shop-anniversary gifts, milestone
   trophies. A happy player is a returning player, and returning players are the ones who eventually buy.
8. **Premium players are paid by playtime:** friends visiting, collection goals, events and daily tasks all lengthen sessions, which earns
   Robux with no purchase at all.

## 6. Where the store lives

- **Warehouse Market "Collector's Corner"** (the building we already have): a calm, well-lit stall with big previews, Robux clearly
  marked, and the cash-earned price next to it where it exists.
- A small **Shop** tile on the HUD (no pop-ups) and a "Make it yours" button in Edit Mode.
- Never shown on spawn, during restoring, or while a customer is at the till.

## 7. Numbers to watch (real data replaces these guesses)

| Metric | Why | First target (assumption, verify) |
|---|---|---|
| Day-1 / Day-7 return | If low, fix the game before selling harder | D1 above 35%, D7 above 12% |
| Paying share of daily players | Overall health | 1-3% |
| Average spend per paying player | Price ladder check | 150-300 R$ |
| Preview-to-buy rate | Are previews working? | above 8% |
| Refund / complaint rate | Trust | near 0 |
| Gift share of sales | Social loop | above 10% |

Use `ConfigService` (see the rbx-configs-experimentation skill) to change prices and set rotations without a restart, and to run fair A/B tests
on **prices and presentation only**, never on pressure tactics.

## 8. Rollout

1. **Phase 0 (no Robux):** build the Preview system and the cash path for cosmetics. Playtest with Sean and Dwayne.
2. **Phase 1:** 2-3 themes + Spotlights + Glow Pack as Game Passes, tip jar. Server checks every purchase (`MarketplaceService` receipts).
3. **Phase 2:** fixture sets and dividers, Companion pet, gifting.
4. **Phase 3:** Patron subscription and the first seasonal drop.
5. **Phase 4:** review the data, retire or reprice what did not sell, add what did.

## 9. Engineering notes (for Dev 1, Dev 3)

- All purchases are server-authoritative: `PromptGamePassPurchase` on request, ownership checked on the server (`UserOwnsGamePassAsync`
  + `PromptGamePassPurchaseFinished`), saved in the profile as `entitlements` (needs a data-template change: **ask Ace first**).
- Developer products use `MarketplaceService.ProcessReceipt` with idempotent grants (never grant twice, never lose a grant).
- Preview mode is client-only and reverts itself (no server data touched).
- New cosmetics go in `Shared/Config/*` as data (theme id, fixture set id, price, free-path price), never hardcoded in services.
- Add the new remotes to `Shared/Remotes.luau` and `docs/03_Architecture.md` §6 as always.
- Respect Reduce Effects for every visual pack.

## 10. Changes to docs/05 that need Ace's OK

1. Allow **seasonal cosmetics that return yearly** (docs/05 lists "limited-time pressure" as off-limits; we use returning seasons without countdowns).
2. Allow **cash-earnable cosmetics with a Robux shortcut** as the standard pattern.
3. Approve the **price ladder** (§4) and the **Patron subscription** (§4.3).
4. Approve the **data-template change** for `entitlements`.

## 11. What we deliberately will NOT do

- Any hidden, forced or tricked purchase, including fake timers, confusing currencies, or disguised ads.
- Robux crates, mystery boxes, or anything random for Robux; cash, XP, speed or odds packs; "2x money" passes.
- Purchase pop-ups on spawn, social-pressure messages, guilt copy, or prices hidden behind more clicks.
- Marketing aimed at children that hides the cost.

## 12. Policy checklist before launch

- [ ] Re-read Roblox's current rules for paid items, subscriptions and anything involving random items.
- [ ] Every Robux price visible in the store and on the confirmation prompt.
- [ ] No item gives a gameplay advantage (reviewed by Ace, Sean, Dwayne).
- [ ] Parent-friendly names and descriptions.
- [ ] Purchases tested with 2 players, and with a broke account, and a refund.
- [ ] Preview mode tested with Reduce Effects on and on a phone.
