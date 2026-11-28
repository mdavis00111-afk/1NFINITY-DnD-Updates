# v0.0.27 consolidated release-candidate validation

Status: prepared, NOT accepted or published. Candidate game source at 3a28bef99e35c6e7a0846748e5a6146d275c3189; use the exact final QA branch commit including this document for both platform runs. Published v0.0.26 remains unchanged.

## Automated evidence
Run existing design/tools/run_native_qa.py with --repo, --ref (immutable SHA), --godot (Godot 4.7.2), --logs (new directory), default suites on Windows and Linux. Retain inventory.json, report.json, import and all suite logs, persistence-restart.log. Require matching SHA, import PASS, all fourteen named suites PASS, no engine errors, no pending art clearance. Windows production bridge mandatory; Linux disposable Python test transport is not production certification. Audit-only or subset PASS is insufficient.

## Live acceptance
Use isolated disposable campaign, never personal saves. Verify ordinary conversation and supported mechanical action each use two provider calls, rejected action one, supported direct GUI action zero. Check exact dice and inventory before/after, interrupted narration and reopening, repeated NPC/location identity, disclosed loot and quest records, ten completed moves and recap. Check approved GUI at 1280x720 and normal desktop resolution, inventory scrolling, map, equipment and spell panels. Record actual observations and call counts, not inferred passes.

## Updater and data safety
Follow design/C6_RELEASE_WINDOWS.md and design/C6_RELEASE_READINESS.md. Existing design/tools/release_safety.py provides offline snapshot and restore-copy verification; use only disposable profile copies for acceptance. Close all game/database processes before snapshot. Check candidate manifest covers exact immutable game tree, sizes and SHA256, Windows path preflight, corrupted download rejection, failed import/startup rollback, successful installation from v0.0.26, unchanged profile files for install-only, supported migration on copied saves, and second-PC automatic update. Verify backup restore to separate directory. Version rollback alone does not restore profile data. Do not publish credentials or profile backups. Python helpers are development-only.

## Gate
Latest actual native evidence 99a71aa: 10/14 each OS. No newer run verified. Do not merge/publish until all gates evidenced. If any failure, retain logs and correct scoped cause; rerun on new immutable SHA. No manual intermediate QA required. Connector cannot dispatch workflows or enumerate push runs; exact run link may be needed at consolidated validation. No release hash generated before final source acceptance.
