# 1NFINITY D&D — Roadmap
Baseline: live godot v0.0.21, 2026-11-27. Proposed priorities; not delivery promises. PROJECT_BRAIN.md defines current architecture; TESTING.md defines evidence; CHANGELOG.md records releases.

| Priority | Workstream | Workstream | Status / acceptance gate |
|---|---|---|---|
| P0 | Windows baseline and GUI fidelity | 01 / 05 | GUI reconstruction published as 0.0.21 playtest. Windows visual acceptance, production SQLite and updater validation pending. |
| P1 | Structured 2014 rules coverage | 02 | Partial: batch 001 core stats only. Add verified actions, traits, character options, encounters, treasure and traps with provenance and deduplication; distinguish licensed public data from private references. |
| P2 | Campaign persistence | 03 | Schema only. Implement creation/load/archive, migrations, actor/location/inventory/event transactions and isolation from master characters. |
| P3 | Turn resolution | 02 / 03 | Not implemented. Typed action contract, Godot deterministic checks/dice/state, reproducible tests; no AI write authority. |
| P4 | Gemini gameplay pipeline | 04 | API prose only today. Rules-Check proposes validated action; Godot commits outcome; Narration reads committed facts. Reject invalid responses; test retries without duplicate actions. |
| P5 | Persistent living world and gameplay | 03 / 04 | Not implemented. Populate settlements, persist NPCs, maps, travel/time, encounters and consequences; support sandbox play without forced plot escalation. |
| P6 | Advancement and deeper mechanics | 02 / 03 | Incomplete. Level progression, full applicable class features, spell effects, combat resources, rest, shopping and inventory. |
| Ongoing | Release safety and infrastructure | 06 / 05 | Preserve updater, saves and rollback; automate validation where feasible; investigate fixed root-updater and private-channel limitations separately. |

## Coordination
00 ChatGPT Project lead is primary coordinator; 01 UI/character, 02 SQL/rules, 03 campaign/world, 04 Gemini, 05 QA, 06 Git/build are workstreams, not mandatory chats. Codex is optional for complex implementation and execution. Follow AGENTS.md and HANDOFF.md; checkpoint to remote branches and reconcile before integration. Owner authorizes releases.
