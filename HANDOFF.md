# Current development handoff
Updated 2026-11-27. Read PROJECT_BRAIN.md and AGENTS.md first.
Live release 0.0.21; immutable source 871746df1760f7b5b502688e6b327141682be1e2. Owner supplied Windows screenshots and GUI feedback (v0.0.21); creator opens and AI description generation reported visually; full production smoke/rollback not independently run.

| Field | Value |
|---|---|
| Task | P0-02 Windows GUI refinement |
| Status | Implementation checkpoint complete; awaiting runtime checks and release authorization |
| Owner/environment | ChatGPT Project lead |
| Base | 5dbb2285190bbd27e7edf9611519dc52da15bcd5 (coordination commit follows) |
| Feature branch | feature/p0-windows-gui-feedback |
| Write scope | creator, manager, full sheet, relevant presentation assets/helpers, layout tests, GUI docs, Brain |
| Last remote implementation checkpoint | 202cf09a8a6557665958b0303d3cd439730cce11 |
| Release authorization | Not granted |
| Tests | Source inspection and Git tree/preload path checks passed; runtime not run (Godot executable absent) |
| Next action | Run Godot import/smoke and review candidate, authorize and publish playtest only after review; Windows visual acceptance pending |

Owner requests: fixed 70% sheet size (no zoom controls), left saved character portrait list, manager controls bottom-left; centered identity fields with in-field prompts rather than duplicate labels, fewer heavy black nested boxes, sample portrait default, Generate with AI fills description/personality/ideal/bond/flaw/backstory only, all ability score cards visible before choosing method, verify Godot random dice, compact in-bounds selection dropdowns and bounded wrapped tooltips. Compare approved images and supplied menu font exemplar; preserve data and mechanics. No unrelated changes.
Previous handoff history is retained in Git. Coordinate one writer, push checkpoints, recheck branch heads; do not publish without authorization.

Checkpoint: feature/p0-windows-gui-feedback at 202cf09a8a6557665958b0303d3cd439730cce11. Game files changed: game/players/character_creator.gd, game/players/character_manager.gd, game/players/full_character_sheet.gd, game/players/portrait_art.gd, game/tests/layout_smoke.gd. All changed-script literal preload/load targets exist and no duplicate top-level function declarations found; character rules, project.godot, version and channel unchanged. No GDScript parser/import or Windows test executed. Latest owner-requested GUI refinement supersedes older zoom acceptance criteria; see feature-branch design/GUI_SPEC.md. Feature code is not merged into godot. No new game release published.
