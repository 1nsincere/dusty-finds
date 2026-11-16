# Restoration server contract (PROPOSAL, for Dwayne and Sean to accept or change)

Owner of the rules: Dev 1 (Ace). Owner of the minigames and `RestorationController`: Dev 2 (Dwayne). Dev 3 (Sean) only calls
`RestorationController.RequestStartRestore(uid)` from his Restore button.
Based on `ace/restoration-server` (`docs/Restoration_Server_Draft.md`). Nothing here is built into `main` yet.

## Why a contract
Today the remotes are fire-and-forget (`RequestStartRestore`, `ReportStepComplete`, `RequestExitRestore`). If the server says
no, the client hears nothing and can sit in a minigame forever. Three cases need a defined answer: **rejection**,
**cancellation / late acceptance**, **failed data update**.

## 0. Status
Built on branch `ace/restoration-v1` (`Services/RestorationService.luau`, `Tests/RestorationCheck.luau` 53 pass), using the Notify fallback: no new remote yet. `RestoreSession` has a 5th argument `sessionId`; `ReportStepComplete` takes it as a 4th argument. Rejections: `Notify Info` text + a fresh `RestoreSession`.

## 1. Rejection feedback
**Proposal (needs team OK, because it adds a remote to `Shared/Remotes.luau` and docs/03 §6):** one new server-to-client event
`RestoreResult(kind, uid, ok, reason, data)`.

| kind | When | ok = false reasons | ok = true data |
|---|---|---|---|
| `"start"` | answer to `RequestStartRestore` | `noItem`, `notRestorable`, `alreadyRestoring`, `badBench`, `noBackRoom`, `tooFar`, `rateLimited`, `saveFailed` | none (`RestoreSession` still follows with the recipe) |
| `"step"` | answer to every `ReportStepComplete` | `noSession`, `wrongItem`, `wrongStep`, `badScore`, `tooFast`, `noItem`, `saveFailed` | `{ stepIndex = next step, done = false }` or `{ stars, value, done = true }` |
| `"exit"` | answer to `RequestExitRestore` | `noSession` | none |

Client rule: on `ok = false` the minigame **stops, restores the dirt/camera, and shows the reason** (plain text per reason, kept in
the controller). On `tooFast` or `wrongStep` the client re-reads the current step from the next `RestoreSession`.
Without the new remote (fallback): reuse `Notify` for the text and re-send `RestoreSession` as the "resync" message.

## 2. Cancellation and late acceptance
The client never decides that a step counted. A step is **pending** from the moment the client sends `ReportStepComplete` until
it receives `RestoreResult("step")`.

- **Exit while pending:** the client sends `RequestExitRestore` and shows the shop view at once, but it keeps listening. The server
  answers the step first (accepted or not) and then the exit. The item's real state is whatever the server says. An accepted
  late step is **not undone**; the item just resumes at the new step next time.
- **Late acceptance (step answered after the player already left):** the client ignores any visual change, applies the data
  through `ClientState` (the saved `stepIndex`/state arrives via `StateChanged`), and if `done = true` shows the normal
  "Restored" feedback from `ItemRestored`.
- **Session ids:** `RestoreSession` includes a number `sessionId`; every client report and every `RestoreResult` carries it, and
  either side drops messages from an older session. This stops a late answer from a cancelled session from touching a new one.
- **Server:** `ExitRestore` while a step is being saved waits for that save, then ends the session. Leaving the game
  (`OnPlayerReleasing`) ends the session and keeps saved progress.

## 3. Failed data updates
- `InventoryService.Update` / `DataService.Set` can fail (returns false). The server **never** reports success for a failed save and never
  fires `ItemRestored` for it.
- Per step: the server writes progress first, and only if it saved does it advance its session and answer `ok = true`.
  If the save fails: session stays on the **same step**, answer `ok = false, "saveFailed"`, nothing is awarded.
- Final step: item state, collection best stars, XP and stats are changed in this order: item becomes `Restored` (the one that
  matters); if that fails, answer `saveFailed` and award nothing. Collection, XP and stats are secondary: if one of them fails after
  the item saved, the item stays Restored, the failure is logged (`[RestorationService]`), and the player still gets the result.
  (No double reward on retry: a Restored item can't be restored again.)
- Client on `saveFailed`: show "Couldn't save, try that step again" and let the player repeat the **same step**. Do not reset
  the whole recipe.

## 4. What each person does
- **Ace:** adopt the draft into `Services/RestorationService.luau` with the changes above, tests for each reason, session id, late
  accept, save failure (fake data that fails on demand). Update docs/03 §6 once the new remote is approved.
- **Dwayne:** `RestorationController.RequestStartRestore(uid)`, listen to `RestoreSession`, `RestoreResult`, `ItemRestored`;
  report **score 100** on completion for Wipe, Scrape and Polish. Handle pending steps as in section 2. Confirm the final
  interface to Sean.
- **Sean:** the Restore button calls `RestorationController.RequestStartRestore(uid)` only, and shows nothing about step logic.

## Open questions
1. Approve the new `RestoreResult` remote, or use the Notify fallback?
2. Which bench opens the minigame: the nearest `Bench1` by prompt, or the player's choice? (draft: `Bench1`, `Bench2` with the Back Room)
3. Should a player be able to start a second item while one is `InProgress`? (draft: one session per player, items stay `InProgress`)
