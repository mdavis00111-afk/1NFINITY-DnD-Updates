# Current development handoff
Updated 2026-11-27. Read PROJECT_BRAIN.md and AGENTS.md first.
Live release 0.0.21; immutable source 871746df1760f7b5b502688e6b327141682be1e2. Owner supplied Windows screenshots and GUI feedback (v0.0.21); creator opens and AI description generation reported visually; full production smoke/rollback not independently run.

| Field | Value |
|---|---|
| Task | P0-02 Windows GUI refinement |
| Status | In progress |
| Owner/environment | ChatGPT Project lead |
| Base | 5dbb2285190bbd27e7edf9611519dc52da15bcd5 (coordination commit follows) |
| Feature branch | feature/p0-windows-gui-feedback |
| Write scope | creator, manager, full sheet, relevant presentation assets/helpers, layout tests, GUI docs, Brain |
| Last remote implementation checkpoint | Second implementation checkpoint (current feature branch ref) |
| Release authorization | Not granted |
| Tests | Pending; Godot executable unavailable in current container |
| Next action | Review source and run runtime tests when engine available; obtain release authorization and Windows visual acceptance. |

Owner requests: fixed 70% sheet size (no zoom controls), left saved character portrait list, manager controls bottom-left; centered identity fields with in-field prompts rather than duplicate labels, fewer heavy black nested boxes, sample portrait default, Generate with AI fills description/personality/ideal/bond/flaw/backstory only, all ability score cards visible before choosing method, verify Godot random dice, compact in-bounds selection dropdowns and bounded wrapped tooltips. Compare approved images and supplied menu font exemplar; preserve data and mechanics. No unrelated changes.
Checkpoint changed game/players/character_creator.gd, portrait_art.gd, character_manager.gd, full_character_sheet.gd and game/tests/layout_smoke.gd. Runtime validation not executed; updated smoke assertions are pending. Visual fidelity still needs owner review.
Previous handoff history is retained in Git. Coordinate one writer, push checkpoints, recheck branch heads; do not publish without authorization.
