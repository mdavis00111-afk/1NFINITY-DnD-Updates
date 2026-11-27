# Development reference readiness — 2026-11-27
The split handoff supplied five approved PNGs, seven runtime screenshots, the GUI audit and an expanded SQLite database. The public update repository tracks the GUI references under `design/`. Keep the database in authorized private storage, outside the public Git history and updater manifest.

## Verify a development handoff

Run `sha256sum --strict --check design/SHA256SUMS` from the repository root after placing the approved PNGs and baseline screenshots at their listed paths. The audit belongs at `design/GUI_FIDELITY_AUDIT.txt`. The checksum list covers the 12 PNGs and the audit. Keep the audit paired with its source handoff and review it before committing.

Retrieve the reference database through an authorized private storage binding. Keep the retrieved file outside the checkout and run `python3 design/tools/validate_private_reference.py /authorized/path/private_rules.db`. This checks the pinned SHA-256, SQLite integrity, foreign keys, catalogue and index counts, document metadata, physical page coverage, and a linked FTS5 query. Add `--source-pdfs /authorized/path/pdfs` when the original PDFs are available for an independent comparison with recorded source hashes. The public game catalogue and updater continue to use their existing assets. For the optional Windows Book Pages browser, the existing application path is `reference/private_rules.db` beside the engine executable.

A fresh development task must retrieve the database from the approved location and repeat the validation. An existing task's local copy establishes access for that task only. Record aggregate counts and coverage gaps without copying book text into Git or test logs.

## Current cloud handoff status

The five approved images and seven baseline screenshots were imported from the two GUI archives. Eleven PNGs matched the prior manifest. The Ability Scores PNG from the supplied approved archive yielded the full SHA-256, an exact match to the prior value after restoring one omitted `7c` byte. The audit had no prior manifest entry. Its digest was established from the supplied archive.

The supplied database matched the pinned SHA-256 `197734c2a4a58078e08894d9cb5d3392c4d4ba42ff02e351a10c55e3585a08b0`. The validator confirmed integrity and foreign keys, all 1,327 declared physical pages, 44 no-text and 11 sparse pages, 2,701 outline entries, 88 non-positive Player's Handbook outline destinations, and 50 linked FTS5 hits for the probe. The original PDFs were unavailable for separate hash comparison. The structured catalogue, spell-class associations and reference links match the packaged core and do not expand structured mechanics coverage.

The owner authorized the private GitHub repository `mdavis00111-afk/1NFINITY-DnD-References` and confirmed its private visibility. It stores `private_rules.db` at commit `c1e38e7cf13dcaec2eb2ed1e762c06e5f85908c1` on `main`. Two independent cloud clones made after upload retrieved and validated the pinned database. GitHub API access remained blocked in the cloud, so repository visibility was established by the owner's confirmation. The public repository and updater do not fetch this database.

From the public development checkout, authorized sessions can retrieve and validate the reference in a restricted directory:

```bash
umask 077
reference_dir=$(mktemp -d) || exit 1
git clone --quiet --single-branch --branch main \
  https://github.com/mdavis00111-afk/1NFINITY-DnD-References.git "$reference_dir/repo" || exit 1
git -C "$reference_dir/repo" checkout --quiet --detach c1e38e7cf13dcaec2eb2ed1e762c06e5f85908c1 || exit 1
python3 design/tools/validate_private_reference.py "$reference_dir/repo/private_rules.db"
```
