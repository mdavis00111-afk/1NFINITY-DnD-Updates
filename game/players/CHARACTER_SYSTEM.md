# Character system — v0.0.14

The four approved landscape creator layouts drive actual native controls, not a baked interface image. The title, gold frames, portrait placeholder, reference column, stage navigation, score cards and selection panels use the existing artwork and newly constructed gold UI textures. Select an option to read its reference, then confirm. Descriptions remain free form; the optional Gemini call only writes descriptive prose.

## Storage
- `data/rules.db`: immutable SQLite catalogue, indexed by category and stable ID; includes class-spell relationships and reference edges. Existing source JSON files are retained for catalogue authoring, not read by gameplay lookup. The Godot catalogue caches a SQL query for responsive menus.
- `user://players.db`: transactional player records, indexed metadata, normalized references, inventory and per-category values, plus versioned complete JSON payload for nested state. Legacy JSON records imported without deleting originals. `players/v1/portraits` remains local.
- `reference/private_rules.db`: personal-use creature reference, outside the update-managed folder. Original personal PDFs are not part of public source.
- `systems/campaign_schema.sql`: schema for future separate campaign database. No campaign gameplay engine is claimed.
- `systems/sqlite_bridge.cs` and `.ps1`: parameterized Windows system SQLite bridge. The app uses SQL, not a JSON save-file fallback. Requires supported Windows and PowerShell; no Python installed at runtime. Calls are batched, but process startup adds latency. This is not yet a native GDExtension.
- `user://settings.cfg`: Gemini key and editable model, saved locally in plaintext; do not distribute.

## Validation and limits
2018 Basic Rules, with SRD 5.1 as original-2014 gap filler. The full 2014 PHB was not supplied. SRD subclass/feat/spell coverage is incomplete; no missing content has been fabricated. Character creation is level one; progression data is present but level advancement is not implemented. Known unsupported choices include Ranger humanoid pairs/language checks, optional variants, custom backgrounds, starting wealth shopping and exhaustive equipment handling. The database contains extracted creature reference text separately, not verified executable enemy logic. `needs_review` characters are not returned as campaign templates.

`tests/sqlite_smoke.gd` checks SQL read/write, bound Unicode parameters, transaction and core ability calculations; `tests/character_smoke.gd` and `tests/layout_smoke.gd` run the supported character choices and layout checks. They are supplied for Windows execution, not claimed to have run in the authoring environment. SQLite integrity, foreign-key checks and SQL schema transactions were tested independently.
