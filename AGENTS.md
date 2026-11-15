# AGENTS.md: instructions for Codex (and other coding agents)

This project is **Dusty Finds: Restore & Sell**, a Roblox game built by three beginner developers.
All project rules live in **`CLAUDE.md`**. It was written for Claude Code, but it applies to you too.
Keep `CLAUDE.md` as the single source of truth. Do not copy its rules here.

## Before you do anything
1. Read `CLAUDE.md` fully. Where it says "Claude Code", read "you".
2. Read `docs/STATUS.md` and `docs/07_Onboarding.md`.
3. Read the doc section for the feature you were asked to work on (see the docs map in `CLAUDE.md` §2).

## The rules that matter most (details in CLAUDE.md)
- Plan first and wait for the user's "go" before writing code (`CLAUDE.md` §6.2).
- Only edit files owned by the user you are helping (`docs/04_Team_Roadmap_MVP.md` §G).
- The server owns money, inventory, rolls and saving. Validate every remote on the server.
- Work through the synced files in `src/` (Script Sync). Client entry is `Main.local.luau`.
- Explain things in plain language. The team are beginners.
- Never commit, push or force-push unless the user asks. Ace (Dev 1) makes the code commits.

## Differences from Claude Code
- **Studio MCP:** `CLAUDE.md` mentions the Roblox Studio MCP server for playtests and reading Output. It may not be connected in your setup. If it isn't, don't pretend to test. Give the user exact steps to test in Studio and ask them to paste the Output back.
- Never say code works unless you saw it run or the user confirmed it.
