# Restoration server draft (for Dwayne to review)

Branch: `ace/restoration-server`. Files: `src/Server/Drafts/RestorationServiceDraft.luau` and
`src/Server/Tests/RestorationDraftCheck.luau` (40 checks pass). **Nothing is loaded by the game**: `Main` only loads
`Services/`, so this draft changes no behaviour until you decide to adopt it. `RestorationService.luau` (yours) is untouched.

## What it does (server rules only, docs/01 B8 and docs/03 §7)
- `StartRestore(player, uid, benchName)`: item is mine and `Dirty` or `InProgress`; one session per player; bench is
  `Bench1`, or `Bench2` only with the Back Room; sets the item `InProgress`; fires `RestoreSession(uid, recipe, stepIndex, seed)`.
- `ReportStepComplete(player, uid, stepIndex, score)`: must be the current step of the active session, the minimum time for
  that step type must have passed (`Economy.MinStepSeconds`), the score must be a real number (clamped 0-100). Progress
  (`stepIndex`, `stepScores`) is saved in the item after each step, so leaving and coming back resumes.
- Last step: stars from `Formulas.qualityStars(average, toolBonus)` (tools = Repair Toolkit + Polisher `qualityBonus`),
  item becomes `Restored`, collection best stars, XP by rarity (x2 for tier 2), `stats.restored + 1`, fires `ItemRestored(uid, stars, value)`.
- `ExitRestore(player, uid)`: ends the session, keeps progress.
- Remote handlers (in `Start`): rate limits (3/s, `ReportStepComplete` 2/s), and the bench must be in the player's own plot and within
  `Economy.InteractMaxStuds` of the `Benches.<name>` part.

## What you decide
- Adopt it as is (copy into `Services/RestorationService.luau`), or take the parts you want.
- The score each minigame reports: Wipe, Scrape and Polish should report 100 on completion; Reassemble and Test reduce it (docs/01 B8).
- Client payloads: `RestoreSession` sends the whole recipe table from Config, `ItemRestored` sends `value` = the price at that quality.

## Not covered
- The minigames themselves (client) and the bench camera.
- Anti-cheat beyond the minimum durations and score clamping (accepted risk, docs/03 §5).
- Testing with a real client: only the logic is tested (fake clock, fake data).
