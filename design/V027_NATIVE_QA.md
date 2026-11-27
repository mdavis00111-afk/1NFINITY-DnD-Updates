# v0.0.27 integrated validation — unreleased candidate

**Do not publish or update personal installations.** Exact source/QA checkpoint `7527a6505a470abf88eb41d82a911d0113c2dfb7`, tested via [native rerun](https://github.com/mdavis00111-afk/1NFINITY-DnD-Updates/actions/runs/46084904289). Initial evidence [run 46084737740](https://github.com/mdavis00111-afk/1NFINITY-DnD-Updates/actions/runs/46084737740), both OS artifacts. Later documentation-only commits need not change the game bytes. A failed suite or missing completion marker is a stop, not a waiver.

## Native Windows
Use a dedicated Windows test account or VM, Git, Python 3.10+ (QA only), official Godot 4.7.2 console-capable executable, Windows PowerShell 5.1 and winsqlite3. Run in a separate clone:

```powershell
git fetch origin godot
$ref = '7527a6505a470abf88eb41d82a911d0113c2dfb7'
git checkout --detach $ref
if ((git rev-parse HEAD).Trim() -ne $ref) { throw 'Wrong checkpoint' }
$engine = 'C:\QA\Godot.exe' # replace with actual verified 4.7.2 console executable
& $engine --version
Get-FileHash -Algorithm SHA256 $engine
$logs = Join-Path $env:TEMP ('1NFINITY-v027-' + [guid]::NewGuid().ToString('N'))
py -3 design/tools/run_native_qa.py --repo . --ref $ref --logs "$logs-byte" --audit-only
if ($LASTEXITCODE -ne 0) { throw 'Byte audit failed' }
py -3 design/tools/run_native_qa.py --repo . --ref $ref --logs "$logs-native" --godot $engine
Get-Content "$logs-native\report.json"
```

Use the official [Windows archive](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip), SHA256 731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953. The byte audit stages Git blobs and verifies their hashes; every native suite uses a fresh authorized profile. Preserve logs; do not loosen guards. Linux CI uses an isolated test bridge, not production SQLite. The runtime does not require Python.

## Manual gate (after all native failures corrected)
Follow design/C6_WINDOWS_QA.md section 2 onward with $ref set to the exact reviewed v0.0.27 source checkpoint, NOT historical feature branch. Its profile probe must use the engine's exact path spelling (Windows short path possible). Separate test characters/campaigns only. Validate 1280x720 and 1920x1080 GUI, opening/reopen/settings navigation, inventory and equipment, spell/resource spend and recovery, NPC identity, location/routes, item discovery vs ownership, duplicate-response replay, last ten moves and persistent recap. Use one authorized local Gemini key only in disposable test settings (never in logs or CI). Confirm ordinary valid conversational turns instrumented interpretation + narration only; deterministic GUI actions zero calls; interruption does not replay mechanics; multi-step actions count independently. Record actual request counts and latency (SQL bridge calls/time, context cache hits, GUI rebuild counts). Test updater/rollback on isolated installed copy, preserve settings, portraits, characters and campaigns. Do not use live channel for candidate installation. Release manifest/version/hash checks and explicit authorization remain required after acceptance.

## Current gates
### v0.0.27 integrated validation — RELEASE BLOCKED (2026-11-28 AEDT)
Source checkpoints 3–5 implemented; do not restart historical C1–C6. Native CI run 46084737740 pinned 62dc547008bd03c1992a9d32f7de6ed2b53b206a: both official 4.7.2 downloads and imports passed, both pinned byte audits 397/397, art 250/250 no pending clearance. Windows production bridge 3/14 pass, 9 safety-guard path spelling failures, 2 parse failures; Linux isolated QA transport 6/14 pass (sqlite, character, layout, ai_profile, coordinator, cartography_assets), 8 fail. Linux failures: campaign 8 (opening/log refresh, duplicate/lost opening, wrong campaign on settings return; negative JSON emits parse errors); gameplay 8 (1280x720 clipping and sparse/long inventory panel); world/persistence parse redeclarations; cartography_renderer travel with conditions/exhaustion/unknown speed rejected; noncombat 19 (existing derived equipment stats require review; later equipment, healing, resource/rest, object/check/conversation/wait/spell failures); complete_gameplay 1 (loot transaction acknowledged but settlement readback unavailable); semantic_integration 1 (canonical disposable NPC upgrade). None of downstream recovery/recap/two-call fixture assertions are certified from that early exit. Test infrastructure correction 7527a6505a470abf88eb41d82a911d0113c2dfb7; rerun 46084904289 in progress at observation. Do not assume remaining failures are resolved by harness fixes. Inspect exact suite logs, diagnose and correct actual defects, repeat all suites until pass; no scope expansion. Independent memory SQL 8/8 pass, not engine validation. Actual latency and live Gemini, visual/manual acceptance, updater install/rollback and save preservation across update still required. Current channel remains 0.0.26; no release or version stamp. Native testing instructions design/V027_NATIVE_QA.md.
