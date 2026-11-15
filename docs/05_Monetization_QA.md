# 05: Monetization, Testing & QA

---

## K. Monetization

### K1. Principles
1. **No pay-to-win.** Robux never buys cash, XP, faster income, better odds, or exclusive items that give an advantage.
2. **No Robux randomness.** Nothing random is sold for Robux, directly or indirectly.
3. **Cosmetic and self-expression first.** Players pay to make their shop and avatar look like theirs.
4. **Kind to kids.** No countdown "limited offers", no pop-ups on join, no fake discounts, no purchase prompts during restoration.
5. Everything purchasable is shown in one **Store** tab with a clear "what you get" description.

### K2. Suggested items (launch with 4–6)
| Item | Type | Price idea | Notes |
|---|---|---|---|
| **Shop Theme: Retro Arcade** | Game Pass | 199 R$ | Swaps wall/floor/sign style. Decor points equal to in-game decor (no rating advantage). |
| **Shop Theme: Cozy Cabin** | Game Pass | 199 R$ | Same rules. |
| **Golden Apron & Name Tag** | Game Pass | 99 R$ | Avatar cosmetic shown while in the game. |
| **Exhibit Spotlights Pack** | Game Pass | 149 R$ | Colored spotlights, confetti on exhibits. Visual only. |
| **Big Storage Room** | Game Pass | 149 R$ | +16 inventory capacity. Convenience: it lets you hold more, not earn faster. Keep it modest and also earnable in-game. |
| **Private Server** | Private server | low price (e.g. 25–50 R$/month) | Play with friends only. |
| **Support the Shop** | Developer Product | 25 R$ | "Tip jar": a thank-you message and a cosmetic "Supporter" badge on your sign. Repeatable, no gameplay effect. |

Passive income: Roblox's **Creator Rewards** program (which replaced Premium/engagement-based payouts on July 24, 2025) pays for engagement and bringing in players, so retention matters more than aggressive selling.

### K3. Why we never sell cash packs or Robux crates
- Roblox's paid random items rules apply to random items bought with Robux **or with in-game currency that was bought with Robux**. That would turn our crates into paid random items, which require odds disclosure, PolicyService checks for ineligible users, and trading restrictions.
- Selling cash makes the economy pay-to-win and pushes kids to spend.
- Because crates are bought **only with earned in-game cash**, RE:STORE stays simple and fair. We still show odds on every crate.

### K4. Avoid list
Robux loot boxes, cash or XP boosts, "2× money" passes, energy/timer skips, Robux-only items with gameplay effects, limited-time pressure, purchase prompts on spawn, social pressure ("your friend bought…").

---

## L. Testing & Quality Assurance

### L1. Multiplayer testing
| Test | How | Pass |
|---|---|---|
| Plot assignment | Studio → Test → *Start* with 3 clients | Each gets a unique plot + name; leaving frees it |
| Visitor safety | Client 2 walks into Client 1's shop and tries every prompt | Nothing works for the visitor |
| Simultaneous customers | All 3 display items | No errors; each shop's sales go to the right owner |
| Announcements | Force a Legendary roll (debug command) | All clients see the message once |
| Likes cap | Like the same shop twice / 11 shops' worth with alts | 1 per shop per day; reward cap holds |
| Join mid-session | Client joins after others have customers walking | Sees correct shop states |
| Real servers | Publish to a private test place; play with 3 real accounts on 2 devices | Same results online |

### L2. Data saving tests
- [ ] Earn cash, buy upgrade, leave, rejoin → everything restored (cash, items, upgrades, decor visible, collection).
- [ ] Leave **mid-restoration** → item returns as `InProgress` with the same step.
- [ ] Leave while a customer has an item **reserved** → item returns to inventory as `Restored` (not lost, not duplicated).
- [ ] Close the server (Studio stop / shut down servers in dashboard) → data saved (BindToClose).
- [ ] Rejoin quickly into a **different server** → session lock handled; no rollback or duplication.
- [ ] Old-version profile (set `version = 0` in a test key) → `migrate()` upgrades it.
- [ ] Studio uses `PlayerData_DEV`; live uses `PlayerData_v1` (print store name on startup).
- [ ] Inventory full + free delivery → handled gracefully.

### L3. Exploit prevention tests
Use a test LocalScript or the client command bar to fire remotes with bad data:
- [ ] Wrong types (`RequestBuyCrate(123)`, `nil`, tables) → ignored, no errors.
- [ ] Someone else's item uid → rejected.
- [ ] Buy crate/upgrade without enough cash → rejected.
- [ ] Spam `RequestBuyCrate` 100×/s → rate limited.
- [ ] `ReportStepComplete` instantly after start → rejected (min duration).
- [ ] Skip steps (report step 3 first) → rejected.
- [ ] Score `9999` or `-5` → clamped.
- [ ] Use another plot's bench/counter from far away → rejected (distance + ownership).
- [ ] Place the same item on two slots → rejected.

### L4. Economy balancing
- Keep the economy spreadsheet and `tools/econ_sim.py` matched to Config.
- Playtest with **3–5 fresh players**; record time to: first sale, first upgrade, Lv 5, Back Room, Lv 10. Compare with targets in `02_Economy.md`.
- Debug panel (Studio only): give cash, set level, force rarity, speed up timers. **Disabled in live** (`RunService:IsStudio()` check + server-side only).
- After launch: `AnalyticsService` funnels (tutorial steps → first upgrade → Lv 5 → Back Room) and economy events (cash sources and sinks).

### L5. Performance
- MicroProfiler (Ctrl+F6) during a 6-player test with all customers active: no long server frames.
- Developer Console (F9) → Memory and Network on a phone: memory stable over 20 minutes.
- Part count per plot reasonable; item models ≤ 60 parts; no unanchored scenery.
- Reduce Effects setting actually reduces particles.

### L6. Mobile compatibility
- Device Emulator: small phone, large phone, tablet, in both orientations the game supports (landscape).
- Every minigame playable with touch only; Exit button reachable; prompts tappable.
- Text readable (≥ 14 px at phone scale); buttons ≥ 44 px.
- Real-device test on at least one Android and one iPhone before launch.

### L7. Bug tracking
- **GitHub Issues** with labels: `bug`, `crash`, `data`, `exploit`, `ui`, `mobile`, `balance`, and priority `P0` (data loss/crash) · `P1` (blocks the loop) · `P2` (annoying) · `P3` (polish).
- Template: *Steps · Expected · Actual · Device · Output log · Screenshot*.
- P0/P1 fixed before any new feature. Ask Claude Code to "find the cause first, then propose the smallest fix."

### L8. Release checklist
**Gameplay**
- [ ] Tutorial completes on PC and phone without help (3 new testers)
- [ ] All 20 items restorable; every recipe step works
- [ ] All upgrades purchasable and effective; persist after rejoin
- [ ] Customers buy correctly; Quick Sell works; no stuck NPCs after 30 minutes

**Data & security**
- [ ] All L2 data tests pass on live servers
- [ ] All L3 exploit tests pass
- [ ] Debug tools disabled in live; live DataStore name set

**Platform**
- [ ] Place owned by the team's Roblox **group**; revenue split agreed in writing
- [ ] Maturity & Compliance questionnaire completed
- [ ] Icon, 3+ thumbnails, description, genre tags
- [ ] Monetization items cosmetic-only and correctly granted (test purchases in Studio)
- [ ] Chat/announcements filtered (system messages only use our own text)
- [ ] Server size set to 6; StreamingEnabled tested

**Polish**
- [ ] No placeholder UI or textures; sounds on every action; music volume sensible
- [ ] Settings save; Reduce Effects works
- [ ] Feedback link (group wall / Discord) in the game description

**Launch plan**
- [ ] Friends & family soft launch (1 week) → fix P0/P1
- [ ] Public launch; monitor errors (Creator Dashboard → Error Report) daily for the first week
