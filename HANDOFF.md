# Current development handoff
Updated 2026-11-27. Coordination record on godot; read PROJECT_BRAIN.md and AGENTS.md first.

## Current state
- Primary coordinator: ChatGPT Project 00 Lead Developer. Codex optional; no active Codex assignment confirmed. Do not assume it has stopped if an external task resumes; check status before overlapping edits.
- Live release: 0.0.21; release branch checkpoint before this documentation change: f31ada67209cafa86e36ce3c24dd7cf3bcf7cbf6; immutable game source 871746df1760f7b5b502688e6b327141682be1e2; 81 manifest entries. All manifest Git blob hashes matched pinned source tree in this setup check; version files matched.
- Last completed implementation: GUI candidate 5282facc58abee649ce941effa5ae56eaf564e14, published as 0.0.21. Reported Linux import/startup and test-only SQL transport tests in TESTING.md. Windows runtime and fidelity acceptance pending.
- Reference designs: design/approved/, design/baseline-v0.0.20/, design/GUI_SPEC.md, design/GUI_FIDELITY_AUDIT.txt and design/SHA256SUMS. Private reference access: see design/REFERENCE_SETUP.md. No private data in public release.
- Active code assignment: none. Next task: owner installs/tests 0.0.21, reports screenshots and issues; lead scopes next correction. P1 structured rules is queued after GUI acceptance or explicit owner reprioritization.
- Setup change: documentation only; no game, version, channel, updater or specialist profile changes. No runtime tests executed for this change.

## Task ownership and recovery
Before code work, replace active assignment fields below with actual values; update godot coordination record and branch-local handoff at checkpoints. No overlapping writes without coordination. Release authorization is separate from implementation.

| Field | Value |
|---|---|
| Task | Awaiting 0.0.21 feedback |
| Status | Waiting for owner test |
| Owner/environment | ChatGPT Project lead |
| Base | Latest godot at next task start |
| Feature branch | None |
| Write scope | None |
| Last remote implementation checkpoint | 871746df1760f7b5b502688e6b327141682be1e2 |
| Tests | See TESTING.md |
| Blockers | Windows validation; exact artwork fidelity |
| Next action | Collect feedback and scope change |

For each handoff record: task ID, plain-English requirement, acceptance criteria, owner, base SHA, remote branch/checkpoint SHA, changed files, completed/incomplete work, actual test commands and results, blockers, next action, release authorization status. Keep historical details in Git history/TESTING.md rather than relying on chat. Record unpushed work explicitly if known; it is not recoverable through Git. A new task must compare remote heads and resolve stale ownership before writing.
