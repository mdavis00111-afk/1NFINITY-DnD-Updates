# 1NFINITY D&D — Changelog
Live channel: godot. Entries below are reconstructed from published Git commit messages, not evidence of runtime test success. Source commit and manifest commit prefixes are provided for traceability.

## 0.0.22 Windows playtest
- Fixed 70% centered sheet with left portrait roster and bottom-left controls; remove zoom controls.
- Simplified identity fields, lighter surfaces, default sample portrait, pre-roll cards, compact searchable dropdowns and bounded tips.
- AI fills six validated prose-only fields; existing Godot dice and save mechanics unchanged.
- Owner authorized playtest; runtime testing blocked by Windows-only engine in Linux. Existing updater gates retained. See TESTING.md; channel.json pins release source.

## 0.0.21 Windows playtest

This playtest covers the reconstructed creator and character sheet. Linux checks passed. Windows visual fidelity, the production SQLite adapter, upgrade and rollback remain open. The channel manifest records the immutable source commit.

- Reconstruct the four character creation stages and searchable choice dialog. Add a portrait sheet viewer with fit-width, zoom, reset, and two-axis scrolling. Normalize integral scores when resuming a JSON-backed draft so rolled characters can be finalized.
- Archive approved GUI references, document authorized private reference retrieval, and add reproducible Linux smoke checks for creator and sheet behavior.
- Establish ROADMAP.md, CHANGELOG.md and TESTING.md; update PROJECT_BRAIN.md. Documentation only; no game version change.

| Release | Source / manifest | Published scope |
|---|---|---|
| 0.0.20 | 58463c24 / 4270b376 | Automatic SQLite reference batch import; 18 NPC and 8 creature core-stat records. |
| 0.0.19 | 4973fc35 / 82ccea58 | Compact character layouts and local book page search. |
| 0.0.18 | b582b68b / 628ba141 | Full character sheet, creator polish, model discovery and local asset library. |
| 0.0.14 | f394630e / fd98d713 | SQLite character creator, Gemini descriptions, player migration and compressed rules DB. |
| 0.0.13 | 32669ee2 / 9c44f6b8 | Creator header and deferred fullscreen layout correction. |
| 0.0.12 | 38daec36 / aea38458 | Imported background texture fix. |
| 0.0.11 | dc450c6f / c25c3c2f | Four-stage creator, persistent records, rules pane and italic typography. |
| 0.0.10 | 7fbc5421 / cc2c4b66 | Recovery startup and edition-separated reference browser. |
| 0.0.9 | 51764f9b / 6bebd342 | Hall artwork, player navigation, rules lookup and draft sheet. |
| 0.0.8 | c1b9104e / 13c2de0a | Approved specimen bitmap font. |
| 0.0.7 | cb8002b3 / 042748cc | Menu typography and illuminated hover control. |
| 0.0.6 | abf09436 / c40804fe | Painted castle artwork and ornate logo. |
| 0.0.5 | a86c827c / 84617f76 | Menu layout correction. |
| 0.0.4 | f882c823 / 0b34dcb4 | Menu navigation, shared theme and separate screens. |
| 0.0.3 | 011d51c5 / f76c157e | Visual update test; subsequent root updater commits f1e58a61, c10b7905, ef7ecce5 addressed folder locks and active pointer. |
| 0.0.2 | e8f38e60 / f3bfef88 | One-page foundation and updater. |

Only releases visible in the inspected branch history are listed; skipped version numbers are not inferred. For future releases record version, source commit, scope, migrations, known limitations and verification evidence; link TESTING.md. Manifest publication follows complete source commit. Documentation-only changes do not increment version.

## 0.0.23 — Windows playtest
- Character management polish and one-click Random character creation in the normal creator, with bounded retries, Godot dice and validation; no automatic save.
- Campaign manager with six starting scenarios, isolated SQLite campaign records, roster thumbnails, log synopsis, resume and recoverable deletion.
- Three editable maturity profiles, adult confirmation, editable Storyteller brief, validated optional AI-generated opening scene and persistent local NPCs/facts. No gameplay turn controller.
- Scoped RAW/proficiency, stale-write, malformed AI response and profile compatibility fixes. QA SQL-level six-fixture tests passed; Godot/Windows/live API tests still outstanding. Owner-authorized playtest; updater gates retained.
