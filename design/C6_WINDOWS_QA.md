# C6 integrated Windows acceptance — internal only

Use only a dedicated Windows test account or disposable VM. Never copy personal saves, API settings or portraits. No release/update command, no publication and no production gameplay mount. The native runner is the actual headless acceptance path; the manual harness below is development-only and is NOT in game/. Lead authorizes any provider use. The optional assets smoke requires the separately authorized local private asset pack; do not acquire/distribute it for QA.

## 1. Exact pinned bytes and all native suites

Install Git, Python 3.10+ (development only), native Windows Godot 4.7.2 (prefer console executable), Windows PowerShell 5.1/.NET Framework/winsqlite3.dll. Confirm engine version and SHA-256. Fetch only the feature branch and check out the C6 QA handoff checkpoint shown in HANDOFF.md. Use its FULL SHA, not a moving branch or live version. In PowerShell:

```powershell
git fetch origin feature/complete-gameplay
$ref = (git rev-parse origin/feature/complete-gameplay).Trim()
git checkout --detach $ref
$engine = 'C:\QA\Godot.exe' # replace with approved native console-capable 4.7.2
& $engine --version
Get-FileHash -Algorithm SHA256 $engine
$logs = Join-Path $env:TEMP ('1NFINITY-C6-' + [guid]::NewGuid().ToString('N'))
py -3 design/tools/run_native_qa.py --repo . --ref $ref --logs "$logs-byte" --audit-only
if ($LASTEXITCODE -ne 0) { throw 'Byte audit failed' }
py -3 design/tools/run_native_qa.py --repo . --ref $ref --logs "$logs-native" --godot $engine
if ($LASTEXITCODE -ne 0) { throw 'Native QA failed; preserve logs' }
Get-Content "$logs-native\report.json"
```

Verify the resolved SHA equals the Lead-approved C6 checkpoint BEFORE running; if branch moves, explicitly set $ref to the approved full SHA and checkout that commit. Runner stages raw Git blobs, verifies hashes, isolates each user:// using unique names and probes, runs import and all 14 default suites (sqlite, character, layout, campaign, ai_profile, gameplay, world, coordinator, cartography_assets, cartography_renderer, persistence, noncombat, complete_gameplay, semantic_integration). The layout suite must execute draft/final save, reopen, portrait and archive checks on Windows, not silently skip. Explicit zero-failure completion markers required. Native default suite duration is bounded to 600s; preserve timeouts/failures as failures. Do not relax guards or alter production bridge to obtain a green report. If the private asset pack is already available and authorized in the isolated VM, run separately with --suites assets --logs "$logs-assets"; otherwise record OPTIONAL NOT RUN. No secret or personal content in logs.

## 2. Windowed C6 test copy (separate from headless profile)

Do not run Launch.cmd, Update.ps1 or the installed game for this. Starting at the checked-out, pinned repository, make a NEW folder and stage the game from Git. The harness is copied only to that test folder; it refuses the normal user directory. These commands do not change the repository or live installation:

```powershell
$manual = Join-Path $env:TEMP ('1NFINITY-C6-manual-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $manual | Out-Null
git archive --format=zip --output="$manual\candidate.zip" $ref game
if ($LASTEXITCODE -ne 0) { throw 'Git archive failed' }
Expand-Archive "$manual\candidate.zip" "$manual\source"
$project = "$manual\source\game"
Copy-Item design/tools/c6_manual_harness.gd "$project\c6_manual_harness.gd"
$name = '1NFINITY_C6_' + [guid]::NewGuid().ToString('N')
$configPath = "$project\project.godot"
$configText = [IO.File]::ReadAllText($configPath)
if (($configText -split "config/custom_user_dir_name=").Count -ne 2 -or $configText -notmatch 'config/use_custom_user_dir=true') { throw 'Unexpected config' }
$configText = [regex]::Replace($configText, '(?m)^config/custom_user_dir_name="[^"\r\n]+"', ('config/custom_user_dir_name="' + $name + '"'))
[IO.File]::WriteAllText($configPath,$configText,[Text.UTF8Encoding]::new($false))
$env:APPDATA = "$manual\roaming"
$env:LOCALAPPDATA = "$manual\local"
@'
extends SceneTree
func _initialize():
	print("QA_USER_ROOT="+ProjectSettings.globalize_path("user://"))
	quit(0)
'@ | Set-Content -Encoding ascii "$project\c6_probe.gd"
& $engine --headless --path $project --log-file "$manual\probe.log" --script res://c6_probe.gd
if ($LASTEXITCODE -ne 0) { throw 'Profile probe failed' }
$lines = @(Get-Content "$manual\probe.log" | Where-Object { $_ -like 'QA_USER_ROOT=*' })
if ($lines.Count -ne 1) { throw 'Ambiguous user root' }
$userRoot = $lines[0].Substring(13).Trim().TrimEnd('\','/')
if ((Split-Path $userRoot -Leaf) -ne $name) { throw 'Wrong user profile' }
if ((Test-Path $userRoot) -and @(Get-ChildItem -Force $userRoot).Count -ne 0) { throw 'Profile already contains data; inspect, do not reuse' }
New-Item -ItemType Directory -Force -Path $userRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $userRoot '.c6-test-profile'),$name,[Text.UTF8Encoding]::new($false))
Remove-Item "$project\c6_probe.gd"
$env:INFINITY_TEST_USER_ROOT = $userRoot
$env:INFINITY_C6_MANUAL = 'YES'
$env:INFINITY_C6_PROVIDER = 'NO'
$env:INFINITY_C6_MODE = 'setup'
& $engine --headless --path $project --editor --import --log-file "$manual\import.log"
if ($LASTEXITCODE -ne 0 -or (Select-String -Path "$manual\import.log" -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) { throw 'Import failed' }
& $engine --path $project --resolution 1280x720 --log-file "$manual\setup.log" --script res://c6_manual_harness.gd -- recovery-windowed
```

In setup, create a **test** fighter and cleric/wizard using original character creator; save draft, reload, add test portrait from approved test art, finalize; create two new campaigns, e.g. C6 Manual A/B. Do not open Update from GitHub or use personal data. Offline opening generation is optional; if authorized live Gemini is needed, save owner-approved test key/model using Settings on this disposable profile only, explicitly opt in, then generate opening in normal setup UI. Exit fully. Run the harness in play mode:

```powershell
$env:INFINITY_C6_MODE = 'play'
$env:INFINITY_C6_PROVIDER = 'NO' # deliberate offline failure testing; YES only with explicit authorization
& $engine --path $project --resolution 1280x720 --log-file "$manual\play-720.log" --script res://c6_manual_harness.gd -- recovery-windowed
& $engine --path $project --resolution 1920x1080 --log-file "$manual\play-1080.log" --script res://c6_manual_harness.gd -- recovery-windowed
```

Select the same test campaign; actual semantic_controller binds only in this harness. Offline transport intentionally returns failure without network; it verifies interaction/retry/queue and read-only GUI, not semantic acceptance. For live test only, explicitly set provider YES, use local authorized key/model; do not include key or settings.cfg in evidence. Campaign/Save & Exit returns to harness selector and closes controller; Settings opens standard setup menu with exact saved state; exit process and restart play to resume. Native mock semantic_integration suite is the deterministic non-network integration proof. Harness logs timing samples only at workspace close; distinguish mock, offline, live and restarted jobs. If user directory guard fails, stop; do not disable guard.

## 3. Acceptance record (manual, actual observations required)

| Area | Action and expected evidence |
|---|---|
| Character creation | At both target resolutions exercise four pages, random and array, long name, portrait, skill/spell selection, draft/reload/finalize/archive; inspect actual screenshot and persisted record. |
| Campaign and migration | Create A and B from same fixture master, open A via harness, verify .pre-world- and .pre-gameplay- backup integrity, no master/sibling changes; retry same migration no duplicate rows. Never restore while running. |
| Inventory/equipment/resources | Equip shield, swap legal weapon, inspect AC and weight; use supported healing potion, second wind or self-healing spell, short/long rest as eligible; verify quantity/HP/slot/resources before/after/reopen and no duplicate event. |
| Natural intent/RAW | Ask an innkeeper a simple question (no roll); attempt a supported contextual ability/skill check, assert actual selected d20, modifier, difficulty/DC and recorded outcome; ambiguous or unsupported requests clarify instead of inventing effect. |
| Creative DM/interpretation | Ask about an ordinary local event, revisit same NPC; confirm rich natural dialogue not grammar-only, stable identity and public history. Introduce an unsupported effect request and verify correction/block; mock suite injects omitted contradiction and inconsistent review. |
| Ownership/rewards | In mock suite use funded NPC, offer/decline then accept exact GP/quantity; inspect both owners and transfer rows. Newly disclosed loot is not auto-collected. For live test, use an established eligible offer/owned item; do not demand fabricated rewards. |
| Persistent story | Accept a real quest offer, inspect quest log, update supported objective, return/reopen, ensure one stable identity and recorded history; private facts absent from public read model. |
| Map | Explore existing known locations, fog and zoom/pan/measure/legend/layers; compare route geometry and red actual travel; unknown coordinates stay journal-only. No local/tactical geometry beyond contract. |
| Async/recovery | While provider pending, inspect Inventory/Map/Character and queue ONE next natural input; second queue rejected. Record draft, Save & Exit, reopen, retry/cancel; queue only after settled prerequisite with fresh revision. Close process during pending narration and again after transfer commit; no duplicate effect/roll, original text retained. |
| Prompt workflow | Settings > Edit AI Prompts: edit/save/reset Narrator on fixture profile, compare original default, export prompt only with explicit consent, import shared bundle with changed base/ancestry and keep-local; stale preview rejects, settings/API/model untouched. Never share real key. |
| Visual/responsiveness | Capture 1280×720 and 1920×1080 character, gameplay, inventory and atlas; check scroll, hitboxes, text wrapping, fonts, ratios, artwork, controls. Record submission-to-preview, queue wait, provider stage time, preview-to-terminal, actual freezes and timing sample count. No claim of live performance from mock. |

Record exact commit, engine/DLL environment, test mode, log filename, reproduction steps, expected/actual, screenshots, DB read-only before/after counts and PASS/FAIL/BLOCKED for each. Retain protected offline fixture backups separately; never replace a DB with one open. Before sending evidence, redact paths, local prompts, keys, private data; do not send raw settings.cfg, real save DBs, licensed packs or engine files. No distribution/publishing. Lead accepts or assigns fixes; 06 waits.
