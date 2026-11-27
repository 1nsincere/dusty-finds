# 14: Robber design proposal (WP8 + WP9). DRAFT, nothing built

> Written 2026-11-27 by Claude for Ace to approve or change. **No code exists for this.** WP8/WP9 of `docs/13_NPC_Life_Brief.md` start only after
> the "Decisions needed" section below is answered. Audience includes children: cartoon "shoo", no violence, no pay-to-win, nothing lost for good.

## 1. The event in one paragraph
Shops close at 19:00 game time (`Shared/Hours`). At night, rarely, a **robber** NPC walks to a shop whose owner is online, the owner gets a warning
toast, the robber slips in through a server-only **breach** of the roll-down shutter, grabs ONE item, and runs for the plaza. The owner can chase
and "shoo" the robber with a **walis tambo**. If shooed, the robber drops the item and flees. If not, the item goes to the **lost-and-found post**
and can be reclaimed.

## 2. Rules (all server-side, numbers in a new `Config/Robber.luau`)
- **When:** only between `SHOP_CLOSE` and `SHOP_OPEN`; at most one robber per server at a time; chance per night per owner (config, default low);
  never in a player's first sessions (needs a "nights played" counter held in server memory first, see Data below); never when the shop has only
  one stealable item; never a quest or tutorial item.
- **Target:** weighted pick, pedestal ("flex") items weigh more than shelf items (config weights, e.g. pedestal 3, shelf 1). Only `Displayed` items.
- **Warning:** toast to the owner when the robber starts walking ("Someone is near your shop!"), second toast on breach. Owner can come back from anywhere.
- **Breach (WP9):** `HoursService.Breach(plot, durationSeconds)` opens a small server-only gap in that shop's shutter for the robber only, for a
  few seconds (an animation: shutter lifts a hand-width + a creak sound). Owner and visitor rules are unchanged: visitors still cannot enter,
  `HoursCheck` still passes. The breach function is the ONLY way in and is tested separately.
- **Shoo:** a `WalisTambo` prompt/tool for the owner (and friends visiting? default no: owner only). Hit range check on the server, cooldown, a few hits
  needed (robber has "stubbornness", config). On success: robber drops the item (item returns to its slot), says a funny line, runs off and fades.
- **Escape:** robber reaches the plaza exit with the item.

## 3. Consequence if the robber escapes (my recommendation)
1. The item becomes **Stolen** (cannot be sold or displayed) and appears at a **Tanod / lost-and-found post** at the plaza for a **recovery window**
   (default 10 game-minutes). The owner can walk there and **reclaim it for a small cash fee** (config, cheap, scaled by rarity).
2. If nobody claims it, it **returns to the owner's inventory** when the window ends, with a small **rating penalty** (config). Never lost for good.
3. Epic and above: longer window + extra warning. 4. Never sell protection for Robux. A free cash-bought "Lock" upgrade (alarm / guard dog) lowers the chance.

## 4. Data: needs your OK (CLAUDE.md 6.6)
Keep a stolen item **in the saved inventory marked unavailable via a server-only set** (Dwayne's idea): a crash or rejoin returns the item and **no
schema change is needed**. The server-only set is rebuilt empty on rejoin (item simply becomes normal again). "Nights played" can start as memory-only.
**Needed from you:** confirm no `DataService.TEMPLATE` change for v1. If you later want robbery history saved, that is a separate, explicit change.

## 5. Files (when approved), for a plan with your go
New: `Config/Robber.luau`, `Services/RobberService.luau`, `Tests/RobberCheck.luau`. Changed: `Services/HoursService.luau` (adds `Breach` only),
`Shared/Remotes.luau` (+ `docs/03` section 6: toast + shoo request + reclaim request, each validated), one client controller for toasts / prompt, `DevTools`, `STATUS`.
That is more than 3 files plus Remotes, so it needs a plan and your go first.

## 6. Decisions needed
1. Accept the consequence in section 3 (recovery window, fee, rating penalty)? Preferred defaults, or your numbers?
2. Accept "no data change for v1" (section 4)?
3. Can friends visiting help shoo, or owner only?
4. Is the robber visible to everyone on the server (fun to watch) or only the owner's shop?
5. Should the robber ever appear when the owner is offline? (My default: no.)

## 7. Tests (RobberCheck, planned)
Weighted target pick favours pedestals; never picks the last item or a quest item; only one robber at a time; breach only at night and only for the
robber; visitors still blocked; shoo validates range / cooldown / ownership; escape sets Stolen + window; reclaim charges the fee exactly once; expiry
returns the item; nothing runs for a player in their first sessions.
