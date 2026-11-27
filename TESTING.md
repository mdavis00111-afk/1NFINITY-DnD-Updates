# 1NFINITY D&D — Testing register
Baseline: v0.0.20, 2026-11-27. Status definitions: PASS = executed with recorded evidence; REPORTED PASS = user-reported evidence, not independently rerun; INSPECTED = source/data examination only; NOT RUN = no execution evidence; BLOCKED = dependency unavailable.

| ID | Test | Status / evidence |
|---|---|---|
| U01 | Update install and visible startup | REPORTED PASS: user screenshot in Project setup conversation showed "Installed and confirmed v0.0.20". Exact logs not collected; one PC only. |
| U02 | Manifest version, source pin and count | INSPECTED: live channel v0.0.20, source 58463c24175c814c6c985c83d178033d42e67ab5, 81 entries. |
| U03 | Rollback, interruption, lock and second PC | NOT RUN; confirm prior version and user data preserved. |
| S01 | sqlite_smoke.gd | NOT RUN independently this session; updater is designed to execute it. Obtain log for explicit result. |
| S02 | Core DB and reference batches | INSPECTED in prior audit: 1968 core entries, 26 batch records; actions incomplete. Runtime import/dedup and queries require evidence. |
| C01 | character_smoke.gd | NOT RUN; verify legal options, scores, proficiency, HP, AC, spells, equipment. |
| C02 | Create/edit/archive/reload and portraits | NOT RUN; preserve saved records across updates. |
| L01 | layout_smoke.gd | NOT RUN; compare all four creator screens and full sheet to approved sources, 1280x720 and fullscreen, no creator page scroll or clipping. Full sheet scroll/zoom as approved. |
| A01 | assets_smoke.gd | NOT RUN; verify optional local asset absence is handled gracefully. |
| G01 | Gemini model discovery and description | NOT RUN; test valid/invalid key, unavailable model, quota and network errors without exposing secrets. |
| W01 | Campaign persistence and gameplay | BLOCKED: runtime not implemented. |
| G02 | Rules-Check / Narration and invalid JSON | BLOCKED: gameplay pipeline not implemented. |

## Codex development team checks

| Check | Result |
|---|---|
| Cloud lead-to-specialist delegation | PASS, 2026-11-27. The lead delegated a read-only check to a Git and release subagent, which inspected `channel.json`, `game/version.txt` and `game/project.godot` at `fc45466` and reported directly to the lead. It confirmed version `0.0.20`, source pin `58463c2`, 81 manifest entries and matching project versions. |
| Six specialist profile definitions | PASS. Python `tomllib` parsed `.codex/config.toml` and every referenced profile, and all six names and descriptions matched. This is a static check. |
| Managed-cloud CLI profile activation | BLOCKED. `codex app-server` could not open its default state database in the read-only home directory. Retrying with a writable SQLite state directory still reported project-trust and read-only filesystem errors. No CLI-profile delegation run was completed. |

## Development reference and GUI baseline

- At `godot` commit `3f07db1`, the cloud executor rejected the combined upload because it exceeded the 32 MiB transfer limit. GUI checksum verification, expanded database verification and independent retrieval from private storage remain blocked.
- Linux Godot 4.7.2, isolated XDG directories and a temporary copy of the game. `godot --headless --path "$qa_tmp/game" --editor --import` and `godot --headless --path "$qa_tmp/game" --quit-after 12` both exited 0.
- With the same Godot binary and project, `timeout 20s godot --headless --path "$qa_tmp/game" --script res://tests/<suite>_smoke.gd` exited 0 for `layout` and 1 for `sqlite`, `character` and `assets`. The layout result covers the existing minimum-size assertions. The SQLite and character suites require the Windows SQLite adapter, and the assets suite requires the optional local asset library.
- `sha256sum --strict --check design/SHA256SUMS` reported 11 missing files and one malformed digest. The listed Ability Scores PNG checksum contains 62 hexadecimal characters.
- `python3 design/tools/validate_private_reference.py /tmp/infinity-no-reference/private_rules.db` exited 1 with a missing-file diagnostic. Independent QA exercised the validator on a temporary synthetic FTS5 database and verified source hashes, linked hits, missing and sparse pages, unchanged database bytes and absence of sidecars. The supplied database remains untested here.
- GUI implementation and visual acceptance remain pending the approved images and audit. Windows bridge, updater and visual checks were not run.

## Release procedure
Run applicable Godot headless tests and Windows manual checks; preserve logs (redact credentials and personal saves). Confirm version.txt/project.godot and manifest match; validate every Git blob hash against immutable source; test updater staging, smoke gates and rollback. Record scope, actual commands, date, version, environment, result and evidence. A successful updater handshake is not full gameplay acceptance. No CI workflow exists in audited branch.

## New bug template
ID / version / PC environment / reproduction / expected / actual / screenshot or log / severity / owner / fix commit / retest evidence. Do not mark fixed until relevant tests pass. No new runtime tests were executed by the assistant during documentation setup.

## Codex cloud onboarding — 2026-11-27
Evidence: user-pasted Codex report, baseline branch 4ea43b7 / live 0.0.20; not independently rerun in this chat.
- REPORTED PASS: Linux x86-64 Godot 4.7.2 headless engine startup with writable XDG directories under /tmp. No game suite executed.
- REPORTED PASS: Python SQLite 3.53.1 opened packaged DB in memory, PRAGMA integrity_check returned ok, 1,968 catalogue rows counted, FTS5 test table created. Standalone sqlite3 CLI absent. This does not validate Godot SQL integration.
- BLOCKED in cloud: production Windows powershell.exe, .NET Framework C# and winsqlite3.dll bridge; stock database-backed smoke tests; Windows launcher/updater integration. Optional local reference assets required by assets smoke. Windows manual testing remains outstanding.
- Codex reported no game files changed, committed, pushed or published. Exact command logs not supplied.

## Reference readiness — 2026-11-27
Executed local Python SQLite checks on supplied expanded rules_private.db: integrity_check ok, foreign_key_check empty, FTS MATCH fireball 50 hits, all four source PDF SHA256 matches; 1327 page records (44 no text, 11 sparse), 1968 catalogue rows, 2701 outline entries. All 12 GUI image SHA256 values matched. Combined ZIP CRC verification passed. No Godot runtime tests executed; private Codex access and Windows book browser integration remain unverified.
