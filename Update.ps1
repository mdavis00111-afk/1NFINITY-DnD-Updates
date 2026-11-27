param([string]$InstallRoot=$PSScriptRoot,[string]$ExpectedVersion='', [int]$GamePid=0,[switch]$LaunchOnly,[switch]$Repair)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$root=[IO.Path]::GetFullPath($InstallRoot)
Set-Location -LiteralPath $root
[Environment]::CurrentDirectory=$root
$engine=Join-Path $root 'Godot.exe'
$base='https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates'
$pointer=Join-Path $root 'active-game.txt'
$log=Join-Path $root 'update.log'
$id=[Guid]::NewGuid().ToString('N')
$stage=Join-Path $root ('game-'+$id)
$lock=$null; $started=$null; $committed=$false; $restart=$false; $previous=$null
function Log([string]$s) { Write-Host $s; Add-Content -LiteralPath $log -Value ('{0:u} {1}' -f (Get-Date),$s) }
function ActiveGame {
 if(Test-Path -LiteralPath $pointer){
  $n=(Get-Content -LiteralPath $pointer -Raw).Trim()
  if($n -match '^game-[0-9a-f]{32}$'){
   $p=Join-Path $root $n
   if(Test-Path -LiteralPath (Join-Path $p 'project.godot')){return $p}
  }
 }
 $p=Join-Path $root 'game';if(Test-Path -LiteralPath (Join-Path $p 'project.godot')){return $p}
 return $null
}
function Blob([string]$p){
 $b=[IO.File]::ReadAllBytes($p);$prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$sha=[Security.Cryptography.SHA1]::Create()
 try{[void]$sha.TransformBlock($prefix,0,$prefix.Length,$prefix,0);[void]$sha.TransformFinalBlock($b,0,$b.Length);return ([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function StartGodot([string]$game,[string]$extra,[string]$name){
 $output=Join-Path $root ($name+'.log')
 $args='--path "'+$game+'" --log-file "'+$output+'" '+$extra
 Start-Process -FilePath $engine -ArgumentList $args -WorkingDirectory $root -PassThru
}
function WaitBounded($process,[int]$seconds,[string]$label){
 if(-not $process.WaitForExit($seconds*1000)){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;throw ($label+' timed out; see logs.')}
 if($process.ExitCode -ne 0){throw ($label+' exited '+$process.ExitCode+'; see logs.')}
}
function ImportGame([string]$game){
 Log 'Importing project assets (see import.log)...'
 $p=StartGodot $game '--headless --editor --import' 'import'
 WaitBounded $p 180 'Godot import'
}
function Smoke([string]$game,[string]$version){
 $token=[Guid]::NewGuid().ToString('N');$marker=Join-Path $root ('ready-'+$token)
 try{
  if(Test-Path -LiteralPath (Join-Path $game 'tests/sqlite_smoke.gd')){
   Log 'Checking SQLite catalogue and transaction support (see sqlite-smoke.log)...'
   $q=StartGodot $game '--headless --script res://tests/sqlite_smoke.gd' 'sqlite-smoke'
   WaitBounded $q 120 'SQLite startup check'
  }
  Log 'Checking that the main menu starts headlessly (see smoke.log)...' 
  $p=StartGodot $game ('--headless --quit-after 20 -- recovery-windowed ready='+$token) 'smoke'
  WaitBounded $p 60 'Godot startup check'
  if(-not(Test-Path -LiteralPath $marker)){throw 'Main menu did not confirm startup. See smoke.log.'}
  if((Get-Content -LiteralPath $marker -Raw).Trim() -ne $version){throw 'Startup check reported incorrect version.'}
 }finally{Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue}
}
function LaunchGame([string]$game,[string]$version){
 $token=[Guid]::NewGuid().ToString('N');$marker=Join-Path $root ('ready-'+$token)
 try{
  Log 'Opening game in windowed recovery mode (see game.log)...'
  $script:started=StartGodot $game ('--windowed -- recovery-windowed ready='+$token) 'game'
  $deadline=(Get-Date).AddSeconds(75)
  while((Get-Date) -lt $deadline){
   if(Test-Path -LiteralPath $marker){if((Get-Content -LiteralPath $marker -Raw).Trim() -eq $version){return}}
   $script:started.Refresh();if($script:started.HasExited){throw 'Game exited before confirming startup. See game.log.'}
   Start-Sleep -Milliseconds 400
  }
  throw 'Game did not confirm startup within 75 seconds. See game.log.'
 }finally{Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue}
}
try{
 $lock=[IO.File]::Open((Join-Path $root '.update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if(-not(Test-Path -LiteralPath $engine)){throw 'Godot.exe is missing.'}
 $previous=ActiveGame
 if($GamePid -gt 0){
  Log 'Waiting for the previous game process to close...'
  $p=Get-Process -Id $GamePid -ErrorAction SilentlyContinue
  if($p){Wait-Process -Id $GamePid -Timeout 30 -ErrorAction SilentlyContinue}
  if(Get-Process -Id $GamePid -ErrorAction SilentlyContinue){throw 'Previous game did not close; no files changed.'}
  $restart=$true
 }
 if($LaunchOnly -and $previous -and -not $Repair){
  $v=(Get-Content -LiteralPath (Join-Path $previous 'version.txt') -Raw).Trim()
  if(-not(Test-Path -LiteralPath (Join-Path $previous '.godot/imported'))){ImportGame $previous;Smoke $previous $v}
  LaunchGame $previous $v;$committed=$true;Log ('Running v'+$v);return
 }
 if(-not $previous -and (Test-Path -LiteralPath (Join-Path $root 'initial-release.json'))){
  Log 'Installing pinned recovery release v0.0.10 from GitHub.'
  $m=Get-Content -LiteralPath (Join-Path $root 'initial-release.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 }else{
  Log 'Checking live update channel...'
  $m=Invoke-RestMethod -Uri ($base+'/godot/channel.json?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -TimeoutSec 30
 }
 if($m.channel -ne 'godot' -or $m.version -notmatch '^\d+\.\d+\.\d+$' -or $m.source_commit -notmatch '^[0-9a-f]{40}$' -or -not $m.files -or @($m.files).Count -gt 10000){throw 'Invalid release manifest.'}
 if($ExpectedVersion -and $ExpectedVersion -ne $m.version){throw 'Release changed; check for updates again.'}
 if($previous -and -not $Repair){
  $v=(Get-Content -LiteralPath (Join-Path $previous 'version.txt') -Raw).Trim()
  if([version]$m.version -le [version]$v){Log 'Already up to date.';LaunchGame $previous $v;$committed=$true;return}
 }
 New-Item -ItemType Directory -Path $stage | Out-Null
 $seen=@{};$i=0
 foreach($f in $m.files){
  $path=[string]$f.path
  if($path -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or ($path.Split('/')|Where-Object{$_ -eq '.' -or $_ -eq '..'}) -or $seen.ContainsKey($path) -or $f.blob -notmatch '^[0-9a-f]{40}$'){throw 'Unsafe release path or hash.'}
  $seen[$path]=$true;$dest=[IO.Path]::GetFullPath((Join-Path $stage $path));if(-not $dest.StartsWith($stage+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe destination.'}
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)|Out-Null
  $seed=Join-Path (Join-Path $root 'seed') $path;$cached=$false
  foreach($candidate in @($seed, $(if($previous){Join-Path $previous $path}))){
   if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and (Blob $candidate) -eq $f.blob){Copy-Item -LiteralPath $candidate -Destination $dest;$cached=$true;break}
  }
  $i++;Log ('{0}/{1}: {2} {3}' -f $i,@($m.files).Count,$(if($cached){'Cached'}else{'Downloading'}),$path)
  if(-not $cached){Invoke-WebRequest -UseBasicParsing -Uri ($base+'/'+$m.source_commit+'/game/'+$path) -OutFile $dest -TimeoutSec 90}
  if((Blob $dest) -ne $f.blob){throw ('File integrity check failed: '+$path)}
 }
 foreach($name in @('project.godot','main.tscn','main.gd','version.txt')){if(-not $seen.ContainsKey($name)){throw ('Missing required file: '+$name)}}
 if((Get-Content -LiteralPath (Join-Path $stage 'version.txt') -Raw).Trim() -ne $m.version){throw 'Version mismatch.'}
 ImportGame $stage;Smoke $stage $m.version;LaunchGame $stage $m.version
 $tmp=Join-Path $root ('active-'+$id+'.tmp');[IO.File]::WriteAllText($tmp,('game-'+$id))
 if([IO.File]::Exists($pointer)){[IO.File]::Replace($tmp,$pointer,($pointer+'.previous'))}else{[IO.File]::Move($tmp,$pointer)}
 $committed=$true;Log ('Installed and confirmed v'+$m.version+'. Previous folder retained.')
}catch{
 Log ('FAILED: '+$_.Exception.Message)
 if(-not $committed -and $started -and -not $started.HasExited){Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue}
 if($restart -and $previous -and -not $committed){try{Log 'Reopening previous game.';$null=StartGodot $previous '--windowed -- recovery-windowed' 'rollback'}catch{Log ('Restart failed: '+$_.Exception.Message)}}
 Log 'No active version pointer was changed before startup verification. Keep update.log, import.log, smoke.log and game.log.'
 exit 1
}finally{
 if($lock){$lock.Dispose()}
}
