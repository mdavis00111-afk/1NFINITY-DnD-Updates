# Development reference readiness — 2026-11-27
One-time handoff: 1NFINITY_Development_References.zip replaces GUI-only ZIP; contains design references and private-reference/private_rules.db. Archive is supplied to owner, not committed. Import design/ only into public repository, verify against design/SHA256SUMS. Store commercial reference data in an authorized private repository or approved private environment storage, outside public game repository and manifest. Verify Codex can retrieve it in a fresh task before calling setup complete. Never change public updater repo visibility without authenticated updater migration.
Database SHA256: 197734c2a4a58078e08894d9cb5d3392c4d4ba42ff02e351a10c55e3585a08b0. 1327 page rows (1272 text present, 44 no_text, 11 sparse_text), 2701 outline entries, 1968 core catalogue entries, 778 spell-class links, 4903 reference links. All four original PDF SHA256 values match reference_documents. Integrity_check ok, foreign_key_check empty, FTS MATCH fireball 50 hits. No runtime integration test. Page index is not complete structured rules coverage. Retain public licensed structured catalogue and reference batches separately. Local optional book browser expects engine-dir/reference/private_rules.db. Validate read-only access and missing-reference behavior; do not replace core catalogue or alter saves. Report missing data explicitly. Codex access to private archive not yet verified.

## Verify a development handoff

Run `sha256sum --strict --check design/SHA256SUMS` from the repository root after placing the approved PNGs and baseline screenshots at their listed paths. The audit belongs at `design/GUI_FIDELITY_AUDIT.txt`. The checksum list covers the 12 PNGs. Keep the audit paired with its source handoff and review it before committing.

Retrieve the reference database through an authorized private storage binding. Keep the retrieved file outside the checkout and run `python3 design/tools/validate_private_reference.py /authorized/path/private_rules.db`. This checks the pinned SHA-256, SQLite integrity, foreign keys, catalogue and index counts, document metadata, physical page coverage, and a linked FTS5 query. Add `--source-pdfs /authorized/path/pdfs` when the original PDFs are available for an independent comparison with recorded source hashes. The public game catalogue and updater continue to use their existing assets. For the optional Windows Book Pages browser, the existing application path is `reference/private_rules.db` beside the engine executable.

A fresh development task must retrieve the database from the approved location and repeat the validation. An existing task's local copy establishes access for that task only. Record aggregate counts and coverage gaps without copying book text into Git or test logs.

## Current cloud handoff status

The combined upload exceeded the cloud executor's 32 MiB per-file transfer limit. The approved PNGs, audit and expanded database remain unverified in this environment. No authorized private backing location was available in the environment configuration. GUI reconstruction is gated on checksum verification of the approved images and access to the audit.

The listed digest for `design/approved/02_ability_scores.png` contains 62 hexadecimal characters. Obtain the full independently supplied SHA-256 before accepting that image against the manifest.
