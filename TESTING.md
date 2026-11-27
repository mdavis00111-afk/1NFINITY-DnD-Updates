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

- At `godot` commit `3f07db1`, the Linux Godot 4.7.2 baseline used isolated XDG directories and a temporary copy of the game. `godot --headless --path "$qa_tmp/game" --editor --import` and `godot --headless --path "$qa_tmp/game" --quit-after 12` both exited 0.
- On the same baseline, `timeout 20s godot --headless --path "$qa_tmp/game" --script res://tests/<suite>_smoke.gd` exited 0 for `layout` and 1 for `sqlite`, `character` and `assets`. The layout result covers existing minimum-size assertions. SQLite and character require the Windows SQLite adapter, and assets requires the optional local asset library.
- Independent QA checked both GUI ZIPs. Eleven supplied PNGs matched the prior checksum list. The supplied Ability Scores PNG gives the full digest after restoring one omitted byte in the recorded hash. The audit digest was established from the supplied archive. The corrected manifest checks all 13 files with `sha256sum --strict --check design/SHA256SUMS`.
- `python3 design/tools/validate_private_reference.py <restricted-temp-dir>/private_rules.db` passed against the supplied database. The validator checked SHA-256, SQLite integrity and foreign keys, aggregate schema counts, page coverage and FTS5. Original source PDFs were unavailable for file hash verification. After upload, the release specialist and lead independently cloned the authorized private repository at `c1e38e7` in clean directories and passed the same validator on the downloaded file. A future cloud task must retain its repository authorization.
## GUI reconstruction candidate

- Linux Godot 4.7.2 stock import and headless menu startup passed in an isolated project. The changed source preserves the production Windows adapter, rules files, update scripts, manifest and both version files.
- `python3 design/tools/run_linux_smoke.py` passed SQLite smoke, all 24 character cases and the expanded layout suite in a disposable Linux project with a test-only SQLite transport. Layout covers 1280×720 and 1920×1080, two character builds, searchable choices, navigation, draft and final saves, portrait retention and archive, and finished sheet fit, zoom and scrolling. AI completion handling was exercised with stub replies.
- Captured all four creator stages and the finished sheet using Linux OpenGL software rendering at both resolutions. The rebuild uses existing runtime art and live controls. Exact visual fidelity and Windows windowed, maximized and fullscreen behavior still need acceptance.
- The `0.0.21` source pins the gameplay candidate from `5282fac` and synchronizes both game version files. The existing Linux results apply to that candidate. The release specialist verified all 81 live manifest paths and blob hashes against the pinned `0.0.20` source. Windows production SQLite and optional asset smoke, updater staging, windowed handshake, rollback and save preservation through upgrade still require Windows validation.

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

## Shared development setup — 2026-11-27
Repository-only check at f31ada67209cafa86e36ce3c24dd7cf3bcf7cbf6: channel 0.0.21, version.txt and project.godot match; all 81 manifest path/blob entries match the immutable source tree 871746df1760f7b5b502688e6b327141682be1e2. Documentation-only coordination update; no new runtime tests executed. Prior cloud test evidence remains as recorded. Windows playtest acceptance pending.

## P0-02 Windows feedback feature checkpoint
Source inspection: character_rules.gd roll_scores calls Godot randi_range(1,6) four times per score, six scores, drops lowest; no AI call. Owner screenshots demonstrate v0.0.21 Windows creator and sheet opened, description populated; selector exceeds viewport and long tooltips overflow. New layout smoke covers in-bounds dropdown, selection/cancel, six-field JSON success/invalid atomicity, pre-roll placeholders, four d6 per score and recorded totals, left portrait roster, fixed 70% sheet and scroll. NOT RUN: Godot executable absent in current container. Production SQLite, actual Gemini response, import/parse and visual acceptance remain outstanding. No release authorized.

## 0.0.22 pre-publication check
`file /mnt/data/Godot.exe` identified PE32+ Windows x64. Copied to /tmp, chmod +x, executed `--version`: failed with Exec format error. `command -v godot`, `godot4`, `wine` found none; curl to GitHub release endpoint failed DNS. No engine import, parser or smoke tests executed. User requested upload; publish Windows playtest with existing updater gates, not verified final release. Candidate literal preload paths/duplicate top-level functions checked; release hashes verified separately against pinned tree. No schema changes.

## P0-03 management polish
Owner screenshot shows v0.0.22 manager opens with portrait roster and centered sheet; owner approves composition subject to polish. Source changes are limited to action labels, opacity and ability abbreviation wrapping; regression assertion added. No engine tests executed.

## P2-01 campaign manager feature
Added tests/campaign_smoke.gd; NOT RUN (Linux container has no native Godot or Wine; Windows executable cannot execute). Test requires explicit matching INFINITY_TEST_USER_ROOT and empty disposable user directory. Exercises six openings, profile validation/live edits, invalid selection, isolated campaign actor/inventory/log, SQLite foreign keys, thumbnail whitelist, soft-delete recovery and unchanged master player. Existing production bridge unchanged. User maturity definitions and Windows visual acceptance pending; no release authorized. Source review is not engine parse or runtime evidence.
