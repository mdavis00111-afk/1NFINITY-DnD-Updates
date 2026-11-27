# 1NFINITY D&D — Roadmap
Baseline: v0.0.22 Windows playtest (channel authoritative), 2026-11-27. Proposed priorities; not delivery promises. PROJECT_BRAIN.md defines current architecture; TESTING.md defines evidence; CHANGELOG.md records releases.

| Priority | Workstream | Workstream | Status / acceptance gate |
|---|---|---|---|
| P0 | Windows baseline and GUI fidelity | 01 / 05 | GUI follow-up 0.0.22 playtest prepared on owner authorization. Windows visual acceptance, production SQLite and updater validation pending. |
| P1 | Structured 2014 rules coverage | 02 | Partial: batch 001 core stats only. Add verified actions, traits, character options, encounters, treasure and traps with provenance and deduplication; distinguish licensed public data from private references. |
| P2 | Campaign persistence | 03 | Feature checkpoint implements isolated DB creation/load/soft-delete, actor/location/inventory/event transaction, roster/synopsis and maturity profile settings. Owner definitions, Godot tests, Windows acceptance and publication pending. |
| P3 | Turn resolution | 02 / 03 | Not implemented. Typed action contract, Godot deterministic checks/dice/state, reproducible tests; no AI write authority. |
| P4 | Gemini gameplay pipeline | 04 | API prose only today. Rules-Check proposes validated action; Godot commits outcome; Narration reads committed facts. Reject invalid responses; test retries without duplicate actions. |
| P5 | Persistent living world and gameplay | 03 / 04 | Not implemented. Populate settlements, persist NPCs, maps, travel/time, encounters and consequences; support sandbox play without forced plot escalation. |
| P6 | Advancement and deeper mechanics | 02 / 03 | Incomplete. Level progression, full applicable class features, spell effects, combat resources, rest, shopping and inventory. |
| Ongoing | Release safety and infrastructure | 06 / 05 | Preserve updater, saves and rollback; automate validation where feasible; investigate fixed root-updater and private-channel limitations separately. |

## Coordination
00 ChatGPT Project lead is primary coordinator; 01 UI/character, 02 SQL/rules, 03 campaign/world, 04 Gemini, 05 QA, 06 Git/build are workstreams, not mandatory chats. Codex is optional for complex implementation and execution. Follow AGENTS.md and HANDOFF.md; checkpoint to remote branches and reconcile before integration. Owner authorizes releases.

## Next gameplay GUI milestone
Owner requests actual game interface before full turn controller. P2-GUI: three-column workspace over campaign snapshots and persisted opening log, manual informational dice, real inventory and rules references; see design/GAME_GUI_SPEC.md. P3 authoritative turn controller remains separate. Target v0.0.24; no publication or runtime certification yet.

## Owner direction — optional cloud sync, separate from gameplay critical path
Owner agrees to investigate private GitHub-backed cross-PC sync, but directs that it not delay main DM/gameplay development. Deferred independent workstream; no implementation, repository creation, version commitment or release authorization. Proposed private 1NFINITY-DnD-Cloud repository, distinct from game updates and licensed references. Sync committed campaign snapshots (including logs, persistent world/map/NPC data), characters, portraits and editable Narrator/content rules/model preferences; keep API keys, GitHub tokens and device-specific settings local. Use consistent SQLite backups, authenticated least-privilege access, revision checks/conflict preservation, offline local play and validated staged restores; never sync open DB/WAL files or overwrite active saves. Consider version history/size limits and privacy before implementation. Godot/SQLite remain authoritative; cloud failure must not block turns or change mechanics. Continue v0.0.24 release review then typed turn controller/DM pipeline as planned; cloud may later be developed on a separate scoped branch with coordinated interfaces. Preserve this note when integrating the current GUI feature branch. Future specialists should read this handoff and account for cloud-ready persistence boundaries without adding sync code outside assigned scope.
