# Dusty Finds: Development Blueprint

*Find it. Clean it. Fix it. Sell it. Grow your shop.*

A multiplayer restoration simulator and shop tycoon for Roblox, built by a team of three with Roblox Studio, Luau, and Claude Code.

## Start here
1. **Everyone:** read `docs/01_GameDesign.md` §A (10 min) and `docs/04_Team_Roadmap_MVP.md` §G–I.
2. **Set up tools** (Stage 1): `docs/03_Architecture.md` §1.
3. Put this whole folder in your Git repo root. `CLAUDE.md` is picked up automatically by Claude Code.
4. Start every Claude Code session with a template from `CLAUDE.md` §7.

## What's in here
| File | Contents |
|---|---|
| `CLAUDE.md` | Master prompt: rules for Claude Code, architecture summary, conventions, prompt templates |
| `docs/01_GameDesign.md` | GDD, all gameplay systems, restoration interaction design, multiplayer, UI/UX |
| `docs/02_Economy.md` | Prices, odds, item list, upgrades, XP, pacing, balancing |
| `docs/03_Architecture.md` | Tooling workflow, folders, services, remotes, validation, data structures, saving |
| `docs/04_Team_Roadmap_MVP.md` | Three roles, 10-stage roadmap with estimates, MVP checklist |
| `docs/05_Monetization_QA.md` | Fair monetization, testing checklists, release checklist |
| `docs/06_Decisions.md` | Feasibility review, technical decisions, assumptions, open questions |
| `docs/STATUS.md` | Living status board (update after every feature) |
| `tools/econ_sim.py` | Economy pacing simulation used for `02_Economy.md` |
