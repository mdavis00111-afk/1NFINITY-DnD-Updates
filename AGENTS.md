# 1NFINITY D&D — Repository agent instructions

## Start every task
- Verify repository mdavis00111-afk/1NFINITY-DnD-Updates and fetch the current godot branch. Never develop against legacy main. For implementation, use a scoped feature branch based on the latest godot tip.
- Read root PROJECT_BRAIN.md before proposing or writing code. Read ROADMAP.md, TESTING.md and CHANGELOG.md as relevant. Inspect only the source files needed for the assigned task. Live code, schema and manifest take precedence over stale descriptions.
- Confirm current published version, task scope and relevant existing behavior. Stop and report conflicting requirements or missing authoritative rules rather than guessing.

## Team delegation
- The main Codex agent leads development and is the user's point of contact. For each feature or gameplay issue, it scopes the work, delegates to the relevant specialists, collects their findings, resolves conflicts, integrates changes, runs applicable checks and prepares release evidence.
- Use the role definitions in `.codex/agents/` when the trusted Codex CLI project loads them. In cloud sessions without active CLI profiles, use native subagents and pass the matching role instructions and exact task scope. Specialists report directly to the lead.
- Assign disjoint write ownership. Use read-only assignments for overlapping files and shared contracts until the lead resolves them. The lead reviews changes and reconciles shared files before integration. Specialists do not independently merge, push or publish.
- See PROJECT_BRAIN.md for role ownership and TESTING.md for verification evidence. Explicit user authorization is required to publish a release.

## Architecture and preservation
- Godot 4.7.2 owns authoritative state, deterministic mechanics, dice, UI and transactions. SQLite stores structured rules and persistence. Gemini Rules-Check proposes structured action interpretations; Godot validates/resolves/commits; Gemini Narration describes verified results. Do not implement a second authority or let AI invent mechanical results.
- Original 2014 D&D 5e RAW supplemented by 2018 Basic Rules; do not mix 2024 rules or invent missing rules. Preserve approved GUI designs, existing behavior, user saves, portraits, settings and campaigns.
- No Python runtime dependency. Development-only Python checks are permitted; distinguish them from actual game integration tests.
- Preserve resource paths, scene IDs, imports, SQL parameter binding, stable catalogue IDs and transactional migrations. Never publish secrets, personal saves, unauthorized commercial reference content or generated .godot caches.

## Testing and release control
- Run relevant tests in the available environment; record exact commands, results and blockers. Do not describe source inspection, engine startup or Python database checks as passing Godot gameplay tests.
- Cloud Linux has reported headless Godot 4.7.2 and Python SQLite support; Windows powershell.exe / .NET Framework / winsqlite3.dll bridge and Windows updater are not validated by Linux. Do not replace production components merely to pass cloud tests. Windows tests remain required where applicable.
- Update PROJECT_BRAIN.md in the same commit as every code, SQL, scene, config or asset change. Keep TESTING.md, ROADMAP.md and CHANGELOG.md accurate as applicable.
- Codex prepares scoped changes and test evidence for lead-developer review. Do not independently merge to godot, change channel.json, bump release version or publish a live update without explicit release authorization. Prefer a reviewable feature branch or draft PR; recheck the live head before integration. Never force-push.
- Preserve the live updater contract: pinned immutable source commit, correct Git blob hashes, synchronized game version files, staging, handshakes, rollback and user:// preservation. Root launcher/updater files do not automatically reach existing PCs. Documentation-only changes do not bump version.
- End tasks with changed files, tests executed, failures, limitations, and commit/PR status. Do not claim a release that was not published.
