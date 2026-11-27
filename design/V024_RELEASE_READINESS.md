# v0.0.24 — Task 06 release readiness
2026-11-27. Specialist 06, ChatGPT Project. Reviewed source e52b8f22a82b7cbc4eece7c293c25dd9a7ee3f57 on feature/p3-game-gui. Live baseline 65b4c0090fa7469443742d24ee15ca80e4aff7d7; published v0.0.23, source 40bfa2ca1ba975bd5ff4cf02f214e042f24ce11d.
**Static review COMPLETE; release acceptance BLOCKED. No publication.** Lead 00/task 07 owns integration and authorization.

## Manifest and versions
Read live and feature Brain, HANDOFF, TESTING, AGENTS and feature GAME_GUI_SPEC/V024_TASKS directly from GitHub. Non-truncated recursive Git trees compared at pinned refs. Live manifest: 90 unique paths; 90/90 blob IDs match pinned live source, no omissions. Git metadata comparison, not independent downloaded-byte hashing. Candidate: 101 regular game files, 11 added, 10 modified, zero removed; 31 changed paths overall. No unsafe path syntax or case-insensitive collisions. Required main.gd/main.tscn/project.godot/version.txt present. Channel, version.txt and project config/version still 0.0.23 intentionally. Companion V024_RELEASE_INVENTORY.json contains actual source paths/blob IDs/sizes/modes, NOT a deployable manifest.
At authorized release: synchronize both game version fields to 0.0.24, update Brain, create immutable source commit, generate full game-relative inventory from final tree (101 entries if no further changes). Actual manifest fields channel=godot, version=0.0.24, source_commit=40 hex, notes, files=[{path,blob}]. Git blob SHA-1 is hash of ASCII blob header with byte length and NUL followed by exact file bytes, not plain SHA-1. Include all managed files, art, tests and provenance. Verify final versions, path safety/uniqueness, completeness and downloaded bytes against blob IDs; do not reuse pre-bump version-file hashes. Publish channel separately only on authorization and after gates pass.

## Assets and dependencies
All six graphics exist as regular Git blobs and are directly preloaded by game_workspace.gd:
| Asset | Bytes | Git blob |
|---|---:|---|
| gameplay/paper_doll.svg | 1741 | f299060978d4e94707bfe0ff8da570c4e030e430 |
| gameplay/reference_backpack.png | 567 | 1cfbd796950e04e86e3c2c27e956c4cb7631fed8 |
| gameplay/reference_compass.png | 957 | addbea81ea0e5ccc56495b50a843a0e510d6d50a |
| gameplay/reference_party.png | 516 | 1e0fbf35f4d0ac22fd42229660afb0a2cfb15f1d |
| gameplay/reference_shortsword.png | 387 | 9125833f84ec3957a35be23b0ce16de845443350 |
| gameplay/reference_slots.png | 2504 | 18e20ff53b5b150496b07e52048da084f0e5fa1d |
95 literal res:// occurrences (45 unique) across 14 changed/new GDScripts resolve. Dynamic resolution and compilation not proven. SVG text reviewed: 340x614 viewBox, internal gradients, decorative outline, no external references visible. Five PNGs could not be retrieved: Git blob endpoint rejects non-UTF-8; direct raw curl failed DNS (exit 6). No binary decoding, dimension/alpha/atlas/crop check, independent byte hash or pixel fidelity verification. Preload makes binary integrity a release gate. ART_PROVENANCE.md documents owner reference crops, trace, ten slot pictograms, matching IDs, no new external art. Existing scenery paths resolve, market crop bounds/fallback present. Provenance documented, not independent pixel/legal certification. No new personal save, secret file, commercial PDF or .godot cache apparent from changed paths; no full secret scan.

## Updater compatibility and rollback
Launch.cmd, Update.ps1, channel.json, game/project.godot, game/version.txt, main.tscn, production SQLite adapter/bridges, campaign schema, master store, character rules and rules DB unchanged. main.gd function comparison: only show_screen/open_game_settings/navigate/content_rules_screen differ. Startup, install_root, check_updates, version_parts, on_response and install_update unchanged; live URL/version marker preserved. Source compatible with existing updater, no new runtime dependency. Installed root updater versions on individual PCs not independently checked.
Updater source: exclusive lock, wait old PID, GUID staging, verified seed/cache/download, required paths and version.txt, import, SQLite smoke, headless and windowed version handshakes, atomic active pointer replacement, previous folder retained and pointer backup. Failure stops staged process and attempts old-game restart if restart flag set. Not full data rollback: failed stage may remain, restart best effort, failure before restart flag need not reopen old game. No independent manifest signature. Startup gates do not test full gameplay UI. Shared user:// is not snapshotted/restored; existing startup Narrator seeding may write settings before pointer activation. Back up user data; do not claim byte-identical rollback. No real updater, failure injection, Windows locks or cross-PC deployment executed.

## Save protection
Same custom user dir 1NFINITY_DnD_Godot; same user://campaigns/v1, schema 1, master store and schema unchanged. Read-only gameplay projection with BEGIN/COMMIT. Store function comparison: opening_eligible, prepare_opening, actor_record, gameplay_view, display_shape_valid changed; creation/delete/commit_opening unchanged. No new migration or game runtime dependency. Existing settings/portraits/master/campaign DBs outside managed files. Task 05 reported disposable SQLite isolation, rollback, replay and integrity passes; not newly executed here or Windows bridge proof. Existing opening can intentionally commit narration; manual dice informational; turn controller absent. No personal saves accessed.

## Required release gates
Executed: pinned tree/manifest metadata comparison, path/mode/collision checks, changed script literal resource checks, function comparison, SVG text/provenance review. Native Godot/Godot4/Wine/PowerShell/gdparse unavailable; raw GitHub DNS failed. No Godot import/parse/smoke, Windows bridge, actual GUI, live Gemini, personal-save or updater rollback run. Prior SQL evidence remains in TESTING.md.
1. Retrieve/decode/hash all new art; validate atlas dimensions/crops, actual Godot 4.7.2 import.
2. Run all seven isolated smoke suites: sqlite, assets, character, layout, ai_profile, campaign, gameplay.
3. Windows GUI acceptance at 1280x720 and 1920x1080; populated/empty/noncaster/caster, long names/log/inventory, missing art, offline opening, pending/fail/retry, Settings return, exit/resume/delete, disabled composer; authorized live Gemini structured response.
4. Disposable Windows updater test with known old pointer and backed-up representative saves; success plus bad hash, missing file, failed import/handshake, interrupted download and locks. Verify old pointer/folder and reopening old version, before/after save/portrait/settings/campaign data. Repeat representative PCs; isolated harness/pinned fixture, never modify live channel to test.
5. Owner authorization, version bump, immutable final commit and full manifest byte validation, then separate publication. No unexecuted gate marked passed.

**Decision: ready for lead review only, not release-certified.** No game code, version, updater or channel change.
