# v0.0.24 — gameplay GUI specialist queue
ChatGPT Project only; no Codex. Branch feature/p3-game-gui. Live release v0.0.23. Owner supplied game GUI reference; see design/GAME_GUI_SPEC.md. Sequential write ownership; other specialists may do read-only review only until assigned.
1. COMPLETE (source checkpoint; runtime and visual acceptance pending) — 01 Godot UI & Character System: implement game workspace from the design spec. Scope new game/gameplay/ UI scripts and assets using approved existing art, narrowly scoped campaign_manager.gd/main.gd integration, read-only campaign data accessor only if required, game GUI smoke test, docs/UI.md, PROJECT_BRAIN.md, HANDOFF.md, TESTING.md and this queue. Preserve v0.0.23 opening workflow, no turn simulation. Checkpoint early and upon completion. Use actual campaign-local actor data. Record exact reference visibility/runtime limitations. 
2. READY — 02 SQL & D&D Rules Engine: review data projection, dice and equipment/weight/spell/skill display correctness; fix scoped defects. No new rule subsystems.
3. WAITING — 03 Campaign & World Engine: review save/resume/exit, opening retry, log and navigation integration; ensure no campaign corruption or duplicated openings.
4. WAITING — 04 Gemini Agent Pipeline: verify existing opening/narration constraints and define future typed turn interface, no unimplemented gameplay or direct mechanics calls.
5. WAITING — 05 QA: independent checks and regression runtime tests where available.
6. WAITING — 06 Release: manifest/update compatibility and readiness, no publication.
7. 00 Lead: review and request/obtain release authorization.
Before development read live PROJECT_BRAIN.md, HANDOFF.md, AGENTS.md, then feature branch equivalent and design/GAME_GUI_SPEC.md. Verify branch head and use expected SHA. Update Brain and handoff in every code commit. No force push, no channel change. Owner opens each chat, lead verifies checkpoint. Current game install/runtime acceptance of v0.0.23 not independently confirmed.

Task 01 source checkpoint ca08e05, fidelity correction and regression in this commit; owner reference now inspected. No runtime or pixel-level rendered acceptance claimed. Next 02.
