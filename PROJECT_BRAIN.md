# PROJECT_BRAIN.md

## 1. SYSTEM ARCHITECTURE & PIPELINE
- Audited live development branch `godot`, v0.0.20, head `4270b376821184c21bbcd8cfb7c9823700ed99a5`; release source `58463c24175c814c6c985c83d178033d42e67ab5`. Repository: `mdavis00111-afk/1NFINITY-DnD-Updates`. Do not develop on legacy `main`.
- Windows x64 source-project distribution, Godot 4.7.2 (README / supplied engine). Root installation contains `Godot.exe`, `Launch.cmd`, `Update.ps1`, game project and optional local references. No export presets, standalone game export or CI build workflow in audited branch. Engine/updater are fixed outside the update-managed game directory.
- **Implemented:** native Godot UI → character_rules.gd → catalog.gd → SQLite read/cache → validated level-one record → character_store.gd → players.db. Gemini is optional descriptive prose only. Game logic and dice are Godot-owned.
- **Target, not implemented:** player intent → Gemini Rules-Check/Interpreter proposes structured action → Godot looks up rules and world state in SQL, validates, rolls, resolves and commits transaction → Gemini Narration receives committed facts → UI displays narration. Gemini must not invent roll outcomes or directly write authoritative state. No turn controller, gameplay agents, campaign runtime or structured action schema exists yet.
- SQL transport: systems/sqlite.gd `stmt(sql,values)`, `run(database,statements,readonly=false)`; synchronous PowerShell subprocess per batch, request/response files under user://sql_transport, cleaned after response. sqlite_bridge.ps1 compiles sqlite_bridge.cs; C# P/Invokes Windows winsqlite3.dll (not a native Godot extension). Input {database,readonly,statements:[{sql,params}]}; output {ok,results:[rows per statement]} or {ok:false,error}. Parameters bound as text/null; result values strings/null; convert numerical fields explicitly. Foreign keys ON, busy timeout 5s, writable batches BEGIN IMMEDIATE/COMMIT or ROLLBACK.
- Update flow: main.gd checks raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates/godot/channel.json with cache-busting timestamp; semantic version compare; confirmation launches external Update.ps1 with InstallRoot, ExpectedVersion, GamePid and quits. Launch.cmd uses -LaunchOnly.
- Manifest {channel:"godot",version,source_commit,notes,files:[{path,blob}]} lists 81 game-relative files in v0.0.20. Hash is Git blob SHA-1 (header "blob <length>\\0" + bytes), not plain SHA-1. Download from immutable source commit /game/path; reuse verified seed or previous files. Reject unsafe paths, duplicate entries and invalid hashes. Lock .update.lock, wait old PID, stage game-<32hex>, import headless, run sqlite_smoke.gd, headless menu handshake, launch windowed handshake (ready-<token> containing version), atomically replace active-game.txt only after success. Keep previous folder/pointer, reopen old game on failure. Logs update.log/import.log/sqlite-smoke.log/smoke.log/game.log. Recovery initial-release.json optional. No authenticated fetch; private repository breaks existing updater. HTTPS trust, no independent manifest signature.

## 2. SQL DATABASE SCHEMA
Notation: PK primary key; FK foreign key; composite keys in parentheses. JSON payloads hold nested records; identifiers stable lowercase hyphenated catalogue IDs. Databases separated by responsibility.

**Core immutable catalogue** — `res://data/rules.db.gz` transport; raw rules.db or checksum-addressed user://rules_cache/srd51-2018-r2-<hash16>.db. Verified against packaged v0.0.18 DB and current loader checksum c4ce8012056b69d4f14c6a48b0a330408ed68562221ad3925d480100920ddb00, uncompressed 3,534,848 bytes. Ruleset 5e-2014-2018, revision srd51-2018-r2. JSON source INDEX still says r1.
- metadata(key PK,value).
- catalog(category,id,name,payload; PK(category,id)): 1,968 entries.
- spell_classes(spell_id,class_id,level; PK(spell_id,class_id)): 778 associations, logical catalogue links.
- references_map(category,id,relation,target_category,target_id; PK(all five); FK(category,id)→catalog): 4,903 edges; target link logical.
- catalog.gd reads metadata and all catalogue rows, caches dictionaries/arrays by category/id; rows/get_record/filtered/spell_rows/describe/summary APIs. Spell filter uses payload references, not SQL joins. Categories: races, subraces, classes, subclasses, backgrounds, skills, spells, equipment, equipment-categories, features, levels, languages, proficiencies, traits, ability-scores, magic-items, conditions, feats, weapon-properties, rule-sections, monsters.

**Reference batches** — user://reference_batches.db, batch_catalog.gd. catalog(category,id,name,payload; PK(category,id)). Each initialization rebuilds this cache in one transaction from PACKS JSON files, verifies returned count. Batch 001 has 26 records (18 NPC, 8 creature), all category monsters, core numeric stats only. catalog.gd merges only absent IDs; optional local monster records override matching IDs. No player/world data in this cache.

**Player persistence** — user://players.db, character_store.gd, schema 1.
- meta(key PK,value): schema, legacy_migration.
- players(id PK,name,status,race_id,class_id,level,ruleset,revision,updated_at,payload); index players_name (NOCASE). IDs 32 hex; catalogue refs logical.
- player_values(player_id,category,key,value; PK(player_id,category,key); FK player_id→players ON DELETE CASCADE): ability_scores, skills, saving_throws, coins, combat, equipment, resources.
- player_refs(player_id,category,ref_id; PK(all); FK player_id→players CASCADE): proficiencies, expertise, languages, traits, class features, cantrip/known/prepared spell IDs.
- inventory(player_id,item_id,quantity>0,equipped,payload; PK(player_id,item_id); FK player_id→players CASCADE).
- archived_players(id PK,payload,archived_at).
- ensure creates schema/migrates valid user://players/v1/*.json once, retains originals; save_record replaces parent and rebuilds child rows in transaction; list/load read full JSON payload; archive copies then deletes parent; campaign_template clones ready record with new ID and master_character_id. Draft/review records not campaign-ready. No cross-PC save sync.

**Campaign schema only** — systems/campaign_schema.sql; no live database path/controller yet.
- meta(key PK,value).
- actors(id PK,master_character_id,kind CHECK player/npc/enemy,catalog_id,location_id,payload); index actor_location. Master/catalog/location IDs logical, no FK on these columns.
- locations(id PK,parent_id FK→locations.id,kind,name,x REAL,y REAL,payload).
- inventory(actor_id FK→actors.id CASCADE,item_id,quantity>0,payload; PK(actor_id,item_id)).
- events(id INTEGER PK,turn,game_time,kind,payload); index event_turn.
- relationships(actor_a FK→actors.id,actor_b FK→actors.id,payload; PK(actor_a,actor_b)).
- quests(id PK,status,payload); encounters(id PK,status,payload).
- No Godot writes/queries wired. Define campaign creation, migrations and transaction ownership before adding gameplay.

**Optional local assets** — <engine dir>/reference/assets/assets.db; inspected supplied v0.0.18 ZIP, not public Git assets.
- metadata(key PK,value).
- tokens(id PK,name,artwork_edition,collection,category,source_path,relative_path UNIQUE,width,height,has_alpha,sha256,creature_id,link_status CHECK exact-name/art-only): 81 rows; creature link logical.
- sheet_templates(id PK,name,edition,source_path,relative_path UNIQUE,pages,widget_count,sha256,role): 7 rows.
- sheet_fields(template_id FK→sheet_templates.id,page,ordinal,field_name,field_type,rect_json,field_flags,choices_json,record_path,mapping_status; PK(template_id,page,ordinal)): 1,494 rows.
- asset_library.gd reads tokens/templates into caches and queries fields by template_id; no writes.

**Optional book references** — <engine dir>/reference/private_rules.db. Original ZIP contains only catalog(category,id,name,payload; PK(category,id)), 169 records. Expanded supplied database rules_private.db is NOT in live manifest; local file has same four core tables above (including metadata), 1,968 catalogue rows, plus:
- reference_documents(id PK,title,edition,filename,sha256,page_count,distribution): 4.
- reference_pages(id INTEGER PK,document_id FK→reference_documents.id,pdf_page,page_label,body,layout_json,width,height,quality; UNIQUE(document_id,pdf_page)): 1,327.
- reference_outline(document_id FK→reference_documents.id,sequence,depth,title,pdf_page; PK(document_id,sequence)): 2,701.
- reference_search FTS5(body, external content reference_pages, content_rowid=id); internal tables reference_search_data(id,block), reference_search_idx(segid,term,pgno; PK(segid,term)), reference_search_docsize(id,sz), reference_search_config(k,v). Do not edit shadow tables directly.
- catalog_browser.gd Book Pages performs parameterized substring join of pages/documents, max 100, not FTS MATCH. Original private DB lacks page tables; search reports error. Expanded DB adds pages, not validated monster actions. Staged branch reference-pack-integration contains loader for reference.db.gz; not merged/live. Preserve separation of licensed public data and authorised private references.

## 3. GODOT STRUCTURE
`game/project.godot`: config_version=5; run/main_scene=res://main.tscn; viewport 1280×720, canvas_items stretch; GL compatibility desktop/mobile; custom user dir 1NFINITY_DnD_Godot. No [autoload], no global signal bus. Only one tracked .tscn; all other screens constructed dynamically. Local callbacks and signals:
```
game/
  main.tscn → main.gd (MainMenu: Control)
    backdrop TextureRect + dynamic screen Control
    Main / Settings / Player Manager / Campaign Manager
    Create New / Generate Character / Edit Character
      players/character_creator.gd (Control)
        Identity → Abilities → Skills & Spells → Loadout & Review
        rules/character_rules.gd + players/character_store.gd
        systems/gemini.gd (child Node, optional description)
    Manage Players / Delete Players
      players/character_manager.gd (Control)
        ScrollContainer → players/full_character_sheet.gd (VBoxContainer)
    Rules Catalogue
      rules/catalog_browser.gd (Control)
        rules/catalog.gd → rules/batch_catalog.gd → systems/sqlite.gd
        systems/asset_library.gd
    Rules Library → rules/library.gd
    Master Reference → rules/master_reference.gd
    Settings API → systems/gemini.gd (child Node)
    Edit AI Prompts / Update from GitHub (main.gd)
  players/character_sheet.gd (legacy VBoxContainer)
  rules/mechanics.gd (legacy draft/dice helpers)
  themes/menu_button.gd (Button helper)
  themes/master_theme.tres
  tests/{sqlite,character,layout,assets}_smoke.gd (SceneTree scripts)
```
The published v0.0.21 P0 GUI uses a fixed creator frame, shared navigation, independent list/reference scrolling, searchable picker and zoomable manager. P0-02 playtest supersedes that presentation contract as detailed below: compact dropdown, in-field prompts, fixed centered 70% sheet with left portrait roster and bottom actions. Character creation uses existing Godot rules/store. Begin Adventure remains unavailable until campaign runtime.

main.gd show_screen removes old screen, creates new anchored Control; creator/manager/browser early return routes supersede stale legacy branches. Creator configure(quick,on_exit,on_finish,saved), manager configure(edit,exit,browse), sheet configure(record,on_reference), browser configure(on_exit). Signals: Gemini completed(bool,String), models_completed(bool,Array,String); HTTPRequest.request_completed; ordinary UI pressed/item_selected/text_changed/confirmed/file_selected etc connected locally. No global custom signals. Character rules fresh/roll_scores/points_used/groups/validate_step/full_record own calculations, not Gemini. Level 1 only; stored draft includes answers and roll history; full_record includes stats, combat, attacks, resources, inventory, spellcasting, review_required. No gameplay scene.

## 4. GEMINI PROMPTS & API INTEGRATION
- systems/gemini.gd: Node owns threaded HTTPRequest (45s, 4 MiB body cap, no redirects, one active operation). BASE https://generativelanguage.googleapis.com/v1beta/. Header x-goog-api-key. Settings user://settings.cfg [gemini] api_key/model (plaintext local); default gemini-3.5-flash-lite is configured identifier, availability unverified. Validate key nonempty/no CR LF, model regex ^[A-Za-z0-9._-]+$, strip models/.
- list_models GET models?pageSize=1000[&pageToken=...]; max 20 pages; filter generateContent-capable gemini text candidates, exclude image/audio/tts/live/robotics, deduplicate/sort. main.gd discovery preferences default, gemini-3.5-flash, gemini-3.6-flash, then selected model. No automatic generation fallback/retry.
- generate(prompt,key_override="",model_override="") POST models/<model>:generateContent; JSON {contents:[{role:"user",parts:[{text:prompt}]}],generationConfig:{temperature:0.8,maxOutputTokens:2048}}. Read first candidate content.parts text, ignore thought=true; join newline, strip, cap 4000 chars. No responseMimeType/responseSchema, tool calls, conversation history or structured game response.
- Exact active prompts: main.gd api_screen: "Reply with exactly: Connection OK"; any nonempty successful text currently accepted. v0.0.21 character_creator.gd generate_description returns description only. P0-02 feature checkpoint requests a JSON object with six prose keys (description/personality/ideal/bond/flaw/backstory), validates all six before changing the draft, and ignores unrelated keys. API transport unchanged; actual request untested.
- main.gd prompt_screen stores editable [prompts] Scene, Interpreter, Brief, Narrator, Write-back, NPC; default empty; runtime integration pending. No Rules-Check/Narration templates or agent JSON contract yet.
- Error handling: immediate request-start failure, timeout/network failure, non-200, invalid JSON, empty text. 400 request/model; 401/403 key/permissions; 404 model unavailable; 429 quota; 503 unavailable. Redact key from returned error detail (420 char cap); clear active/key/model state. User chooses another model manually. Never send key to repo or logs.

## 5. ASSETS & ART PIPELINE
- GUI reference handoff: the five approved designs, seven baseline screenshots and audit are present under `design/`, outside the updater manifest. Use `design/GUI_SPEC.md` and check the files against `design/SHA256SUMS`.
- Private reference handoff: the expanded SQLite database was verified from a restricted local copy. All declared physical pages are present, with extraction and outline gaps documented in `design/REFERENCE_SETUP.md`. The structured catalogue tables match the packaged core. Authorized developers can retrieve `private_rules.db` from the private repository `mdavis00111-afk/1NFINITY-DnD-References` at `c1e38e7cf13dcaec2eb2ed1e762c06e5f85908c1`. Independent cloud clones retrieved and validated the pinned database. Keep commercial book data outside the public repository and release artifacts.
- game/art/: castle.jpg/.svg (main), hall.jpg (settings/player), valley.svg (campaign), forest.svg (hall fallback), arcane.svg, sheet_reference.jpg, sheet_title.png. main.gd tries res://art/<name>.png then .jpg, then user://art same names; ResourceLoader for packaged, Image.load_from_file→ImageTexture for user images; SVG fallback. Backdrop aspect-covered. No procedural world map, map renderer or AI art generator.
- game/themes/: master_theme.tres EB Garamond Italic default 23, gold/ivory controls; fonts/ EBGaramond.ttf, EBGaramond-Italic.ttf, arcane.fnt/arcane_atlas.png, italic.fnt/italic_atlas.png, OFL.txt. parts/ panel_gold.png, panel_active.png, frame.png, corner.png, portrait_empty.png, icons.png + icons.json atlas rectangles; gold_flourish.svg. Creator/sheet build StyleBoxTexture frames and atlas icons at runtime; no baked interactive fields. Preserve approved 4 landscape layouts and full portrait sheet.
- Portraits: creator file picker → local image preview → character_store.save_portrait validates ID, resizes longest side to max 1024, saves user://players/v1/portraits/<32hex>.png, persists path. Full sheet loads saved image/placeholder. No network portrait service.
- Local reference/assets relative paths validated against traversal/absolute paths; tokens mapped by exact creature ID only; art-only remains unlinked; ImageTexture previews, sheet PDFs open via OS.shell_open. Assets are not game-update-managed. rules/library.gd imports validated 2018 JSON sections into user://rules/2018; master_reference.gd reads engine-dir reference/master_index.json and edition/category JSON (2018/2024 separate). Neither is executable mechanics.

## 6. CURRENT STATE & NEXT TASKS
- Development coordination (2026-11-27): root ROADMAP.md tracks milestones and workstreams, CHANGELOG.md records published versions, TESTING.md records evidence and open checks. Read relevant documents as needed; keep Brain authoritative for architecture. User screenshot reports installed and confirmed v0.0.20 on one Windows PC; no independent runtime rerun or full gameplay validation. One publisher at a time; recheck branch head before push. Documentation-only changes do not modify the game channel.
- Previous verified release: v0.0.21, source 871746df1760f7b5b502688e6b327141682be1e2, 81 files; 0.0.22 playtest source prepared under owner authorization. Consult channel.json for actual published state. core SQLite schema and supplied local DBs inspected directly. Menu, creator/quick generation/edit, full sheet, archive, catalogue, model discovery/settings and update implementation present in source. No claim of Windows runtime success for v0.0.19/.20; user testing required. Updater runs SQLite and main startup smoke only, not full character/layout/assets tests.
- Known gaps: v0.0.21 GUI reconstruction has reported expanded Linux layout checks; Windows acceptance and exact approved artwork fidelity remain open. Campaign menu and content rules are shells. Level advancement, complete non-SRD options, ranger variants, custom backgrounds, shopping and full creature effects incomplete. Batch 001 is partial; full book reference not shipped. Optional assets/private DB absent on fresh public install; API key and saves not synchronized. Previous docs contain stale claims; trust code/schema/manifest. No auto CI/export, private-channel authentication or automatic binary delivery.
- Exact next three tasks (proposed order):
  1. Validate v0.0.22 on Windows; run sqlite/character/layout smoke and manual five-screen comparison at 1280×720 and fullscreen; fix GUI proportions and any import/startup regressions; preserve updater rollback.
  2. Expand and validate structured reference batches (creatures/actions, missing legal character options, encounters/treasure/traps); use stable IDs, source/page provenance, deduplication and tests; keep licensed distribution separate from private book-page pack.
  3. Implement campaign persistence and turn controller using campaign_schema.sql with migrations/transactions; then wire typed Gemini Rules-Check proposal → deterministic Godot resolution → committed state → Narrator; add invalid-response and replay tests.

- Codex onboarding report (2026-11-27, user supplied): remote godot at 4ea43b7, clean existing checkout, Linux x86-64 Godot 4.7.2 headless startup and Python SQLite 3.53.1 integrity/FTS5 checks successful; stock Windows bridge and updater blocked, no game smoke suites executed. Root AGENTS.md defines scoped Codex development and review-before-release. See TESTING.md for evidence limits.

## Development team and integration

The ChatGPT Project lead coordinates and performs development. Codex is an optional engineering and independent testing resource. Both share GitHub, AGENTS.md, HANDOFF.md and the subsystem notes in docs/. No direct chat-to-chat dispatch is assumed. Use selective specialist delegation where available, remote checkpoint commits and cooperative task ownership; recover from the last pushed checkpoint, not chat history. Owner authorizes releases.

| Specialist | Responsibility |
|---|---|
| `godot_ui` | Godot scenes, themes, menus, character creation and character sheets. |
| `sqlite_rules` | SQLite schemas and catalogue, transactional data access, and sourced 2014/2018 rules validation. |
| `campaign_world` | Campaign persistence, world state and deterministic turn resolution. |
| `gemini_integration` | Model discovery, prompts and typed responses. Godot retains mechanical and state authority. |
| `qa_testing` | Independent regression checks, exact test evidence and platform-specific blockers. |
| `git_release` | Branch and manifest checks, updater staging and rollback, and release readiness. |

The lead assigns disjoint write scopes and uses read-only investigations for overlapping work before integrating changes to shared files or contracts. Specialists report findings, changes, checks and blockers to the lead. The lead resolves disagreements against the repository's architecture and available evidence, and preserves the automatic updater, player data and release gates.

`.codex/config.toml` registers six reusable profiles for a trusted Codex CLI project. Where profile activation is unavailable, the lead delegates through cloud collaboration tools using the corresponding role instructions. The cloud test confirmed that a release specialist can return read-only findings directly to the lead. CLI profile activation remains unverified in the managed cloud environment. See TESTING.md for details.

## 0.0.21 Windows playtest

The playtest packages the creator and sheet reconstruction from `5282fac`. Godot and the production Windows SQLite bridge, updater, and save storage keep their existing contracts. Linux import, startup, smoke checks with a test-only SQLite transport, and two-resolution captures are recorded in TESTING.md. Windows visual acceptance, the stock SQLite adapter, updater staging and rollback, and save preservation through upgrade remain open. The live channel is authoritative for the published version.

## P0-02 Windows GUI follow-up — 0.0.22 playtest
- Creator in-field labels and centered single-line fields; lighter translucent surfaces, thin outlined low-opacity score tiles, stacked personal fields, pre-roll placeholders; bounded embedded searchable picker and wrapped button tips. Generate with AI requests and validates six editable prose-only fields atomically, no mechanical values. Existing roll_scores uses Godot randi_range(1,6) 24 times per six-score generation, drops lowest per roll and records dice. This is engine PRNG, not Gemini; no change to mechanical code. New portrait_art.gd crops existing approved sheet image as a display-only fallback, never overwrites custom portraits. Manager uses left-side saved-character portrait roster, bottom-left actions, a centered fixed 70% sheet (automatically shrinks only if required), vertical scrolling, and no zoom controls. Full sheet uses shared sample portrait fallback. Layout smoke revised for embedded dropdown selection and bounds, all six AI fields and invalid-response preservation, pre-roll cards and real dice history, portrait roster and fixed sheet; not executed. Visual comparison still required. No Godot runtime available in this environment.

## Shared coordination
- HANDOFF.md records current ownership, checkpoint and next action. docs/UI.md, docs/RULES.md, docs/WORLD.md and docs/AI.md index live subsystem contracts and outstanding work. Follow AGENTS.md shared development policy. No automatic chat dispatch or guaranteed recovery of unpushed work.

## 7. STRICT RULES FOR AI UPDATES
- Never break the in-game Git auto-updater. Only publish a release manifest after source commit is complete; ensure every managed game file has correct blob hash and immutable source_commit, synchronize project.godot/version.txt, preserve safe staging, handshakes, rollback and user://. Do not assume changes to root launcher/updater reach existing PCs.
- Never corrupt .tscn UIDs/sub-resources when editing via Git. Preserve resource IDs, ext_resource/sub_resource references, load_steps and paths; import/smoke-test before release. Do not commit generated .godot cache.
- Always update PROJECT_BRAIN.md in the same Git commit whenever schemas, scripts, scenes, or architecture change. Record changed contracts, migrations, limitations and verification status; distinguish target architecture from implemented code. Documentation-only commits do not bump game version or mutate channel.json.
- Never let Gemini write arbitrary SQL or directly decide dice/mechanical outcomes. Bind SQL parameters, validate IDs and edition, preserve transactional saves and migrations; do not fabricate missing rules. Never commit API keys, personal saves or unauthorised commercial reference content. Keep 2014/2018 mechanics distinct from 2024. Do not mark unexecuted tests as passed.

Audit scope: recursive live godot tree, core source and SQL definitions, supplied v0.0.18 packaged SQLite files, expanded local reference DB. Legacy main and staged feature branch not exhaustive audits; no Windows execution performed.

## 0.0.22 release verification
Owner authorized Windows playtest publication. Supplied Godot.exe is PE32+ Windows x64; execution in Linux failed with Exec format error, no Wine or native Godot installed, attempted GitHub download DNS failed. No import, GDScript parser, layout, actual Gemini or Windows runtime checks executed here. Existing updater stages verified files and runs import, SQLite smoke and startup handshakes before switching active pointer. Those gates are not a substitute for full GUI testing. Preserve previous version on installation failure. No changes to mechanics, SQL schema, save storage, updater, or private reference data.

## P0-03 management final polish (feature checkpoint)
Owner Windows screenshot confirms v0.0.22 management layout/portrait roster displayed. Owner accepts composition subject to removing Rules Catalogue action, changing Archive to Delete (existing recovery transaction retained), slight transparency increase in manager backing and slight opacity increase in creator surfaces. CON/CHA ability abbreviations now nonwrapping. No save/mechanics changes; engine tests not run here.

## P2-01 campaign persistence checkpoint (feature branch, unpublished)
New campaign_starts.gd has six fixed opening circumstances and whitelist of bundled scene-art IDs. maturity_profiles.gd stores owner-defined profiles in user://settings.cfg [campaign_maturity] profiles (array of {id,name,instructions}); no invented policy presets; new campaign requires valid profile and future runtime resolves current profile by stable ID. campaign_store.gd uses isolated user://campaigns/v1/<32hex>.db; existing campaign_schema.sql unchanged. Schema meta row and campaign JSON metadata, cloned ready character actor/master_character_id, start location, normalized inventory and campaign_created log entry written in one SQLite transaction. Deleted campaigns retain DB and log, status=deleted excludes roster. Thumbnail changes only whitelisted art metadata. Synopsis reads committed campaign_created/narration/synopsis events, preferring latest synopsis plus subsequent entries. No AI gameplay or arbitrary SQL. UI, tests and settings wiring next; no runtime checks yet.

P2-01 UI checkpoint: main Campaign Manager has New Campaign / Existing Campaigns + Exit. New campaign selects ready player, title, maturity profile and one of six openings; persists first, then optional Gemini picks one whitelisted bundled artwork ID without blocking opening workspace. Existing library left illustrated roster/right synopsis, bottom-left Exit/Resume/Delete. Workspace displays saved opening log and campaign-local actor only; gameplay pending. Settings Edit Content Rules edits validated JSON profile definitions, reloads shared config after save. No default policy assumed; creation gated until owner definitions entered. Existing art is a provisional library, not six distinct painted scenes. No runtime validation.

P2-01 final source checkpoint: campaign wallpaper defaults to cropped approved castle scenery when no valley image is present; bundled provisional thumbnail library uses hall/forest/valley/castle art (some shared across openings). Campaign smoke added with strict empty disposable user directory guard, six starts, invalid selections, actor/inventory isolation, log synopsis, artwork whitelist, live profile resolution, delete/recovery and unchanged master. No Godot runtime available in current Linux container; tests not run. Owner maturity policy pending, gameplay turn controller pending. No live release authorization.

## v0.0.23 integration handoff
Owner provided legacy content_control.py and prompts.py. Port three audience profiles and Storyteller principles per design/V023_INTEGRATION.md; preserve provider safeguards, editable defaults and Godot authority. Assignment only; maturity defaults and Narrator integration not yet implemented. Existing campaign checkpoint and GUI polish retained. Codex optional lead plus one QA, no publication authorization.

## ChatGPT-only specialist handoff
Owner explicitly declined Codex. Sequential Project chats use design/V023_TASKS.md and shared feature branch; 00 coordinates and owner opens each specialist. 04 first, no overlapping writers. No release authorization.

## V023 task 04 — Gemini audience and Narrator helpers (unpublished)
Implemented three built-in maturity profiles and local editable guidance, retaining legacy valid records and unrelated settings. Stable canonical IDs family/standard/mature; Standard default; strict resolve for creation, safe Standard fallback for unknown narration IDs; legacy custom IDs retained but not offered for new campaigns, Standard audience floor for legacy. No provider safety override. New narrator_prompt.gd exposes editable default, seed/reset/save/load and build(maturity_id, context, response_schema); mandatory authority and audience baseline are independent of editable text. No API calls or gameplay wiring. Task 01 must wire UI and explicit adult confirmation; task 03 may use builder only with validated engine context and proposals. New isolated ai_profile_smoke.gd authored, not executed (no native Godot/Godot4/Wine in Linux container). No release/version/manifest change.

## V023 task 01 — UI integration checkpoint
Implemented profile selector/edit/save/reset using Task 04 helpers; Narrator default seeding and edit/reset; Standard default and explicit adult confirmation; campaign creation opens honest persisted workspace; existing final character polish retained. Random in normal unsaved creator header replaces separate Player Manager generation route; uses catalogue choices, existing auto_fill, Godot rolls, all stage validations and review_required gate, 40 attempts, restores prior draft on failure, no auto-save or AI dependency. Existing edit and saved drafts protected. No runtime or Windows tests executed in connector environment. No publication. Further regression test source and review pending.
