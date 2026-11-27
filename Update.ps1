param(
    [string]$InstallRoot = $PSScriptRoot,
    [string]$ExpectedVersion = '',
    [int]$GamePid = 0,
    [switch]$LaunchOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = [IO.Path]::GetFullPath($InstallRoot)
Set-Location -LiteralPath $root
[Environment]::CurrentDirectory = $root
$base = 'https://raw.githubusercontent.com/mdavis00111-afk/1NFINITY-DnD-Updates'
$pointer = Join-Path $root 'active-game.txt'
$active = 'game'
if (Test-Path -LiteralPath $pointer) {
    $candidate = (Get-Content -LiteralPath $pointer -Raw).Trim()
    if ($candidate -match '^game-[0-9a-f]{32}
$engine = Join-Path $root 'Godot.exe'
$log = Join-Path $root 'update.log'
$id = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $root ('game-' + $id)
$pointerTemp = Join-Path $root ('active-' + $id + '.tmp')
$ready = Join-Path $root ('ready-' + $id)
$lock = $null
$started = $null
$success = $false
$mayRestart = $false
function Log([string]$message) {
    Write-Host $message
    Add-Content -LiteralPath $log -Value ("{0:u} {1}" -f (Get-Date), $message)
}
function Start-Game([string]$token = '') {
    $arguments = '--path "' + $game + '"'
    if ($token) { $arguments += ' -- ready=' + $token }
    Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $root -PassThru
}
function Git-BlobHash([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $prefix = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        [void]$sha.TransformBlock($prefix, 0, $prefix.Length, $prefix, 0)
        [void]$sha.TransformFinalBlock($bytes, 0, $bytes.Length)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
try {
    $lock = [IO.File]::Open((Join-Path $root '.update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Godot.exe is missing.' }
    if ($LaunchOnly -and (Test-Path -LiteralPath (Join-Path $game 'project.godot'))) {
        if (-not (Test-Path -LiteralPath (Join-Path $game '.godot'))) {
            $import = Start-Process -FilePath $engine -ArgumentList ('--headless --path "' + $game + '" --editor --import') -WorkingDirectory $root -PassThru
            if (-not $import.WaitForExit(120000)) { Stop-Process -Id $import.Id -Force -ErrorAction SilentlyContinue; throw 'Godot import timed out.' }
            if ($import.ExitCode -ne 0) { throw 'Godot import failed.' }
        }
        $null = Start-Game
        $success = $true
        return
    }
    if ($GamePid -gt 0) {
        $p = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
        if ($p) { Wait-Process -Id $GamePid -Timeout 30 -ErrorAction SilentlyContinue }
        if (Get-Process -Id $GamePid -ErrorAction SilentlyContinue) { throw 'Game did not close; no files changed.' }
        $mayRestart = $true
    }
    Log 'Checking Godot release channel...'
    $m = Invoke-RestMethod -Uri ($base + '/godot/channel.json?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -TimeoutSec 30 -Headers @{'Cache-Control'='no-cache'}
    if ($m.channel -ne 'godot' -or $m.version -notmatch '^\d+\.\d+\.\d+$' -or $m.source_commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid release manifest.' }
    if ($ExpectedVersion -and $ExpectedVersion -ne $m.version) { throw 'Release changed during update. Check again.' }
    $installed = Join-Path $game 'version.txt'
    if (Test-Path -LiteralPath $installed) {
        $current = (Get-Content -LiteralPath $installed -Raw).Trim()
        if ([version]$m.version -le [version]$current) { Log 'Already up to date.'; $null = Start-Game; $success = $true; return }
    }
    if (-not $m.files -or @($m.files).Count -gt 10000) { throw 'Invalid file list.' }
    New-Item -ItemType Directory -Path $stage | Out-Null
    $seen = @{}
    $i = 0
    foreach ($f in $m.files) {
        $path = [string]$f.path
        if ($path -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or ($path.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }) -or $f.blob -notmatch '^[0-9a-f]{40}$' -or $seen.ContainsKey($path)) { throw 'Invalid or duplicate file path/hash.' }
        $seen[$path] = $true
        $dest = [IO.Path]::GetFullPath((Join-Path $stage $path))
        if (-not $dest.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe release path.' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        $i++
        Log ("Downloading {0}/{1}: {2}" -f $i, @($m.files).Count, $path)
        Invoke-WebRequest -UseBasicParsing -Uri ($base + '/' + $m.source_commit + '/game/' + $path) -OutFile $dest -TimeoutSec 120
        if ((Git-BlobHash $dest) -ne $f.blob) { throw ('Integrity check failed: ' + $path) }
    }
    foreach ($required in @('project.godot','main.tscn','main.gd','version.txt')) { if (-not $seen.ContainsKey($required)) { throw ('Missing required file: ' + $required) } }
    if ((Get-Content -LiteralPath (Join-Path $stage 'version.txt') -Raw).Trim() -ne $m.version) { throw 'Release version mismatch.' }
    Log 'All files verified. Installing...'
    # Never rename or overwrite a previous project folder.
    $game = $stage
    # Source projects need an import pass before launching on a clean installation.
    $import = Start-Process -FilePath $engine -ArgumentList ('--headless --path "' + $game + '" --editor --import') -WorkingDirectory $root -PassThru
    if (-not $import.WaitForExit(120000)) { Stop-Process -Id $import.Id -Force -ErrorAction SilentlyContinue; throw 'Godot import timed out.' }
    if ($import.ExitCode -ne 0) { throw ('Godot import failed: ' + $import.ExitCode) }
    $started = Start-Game $id
    $readyConfirmed = $false
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $ready) {
            if ((Get-Content -LiteralPath $ready -Raw).Trim() -eq $m.version) { $readyConfirmed = $true; break }
        }
        if ($started.HasExited) { throw 'New game exited before startup completed.' }
        Start-Sleep -Milliseconds 400
        $started.Refresh()
    }
    if (-not $readyConfirmed) { throw 'New game failed to confirm startup.' }
    [IO.File]::WriteAllText($pointerTemp, ('game-' + $id))
    if ([IO.File]::Exists($pointer)) {
        [IO.File]::Replace($pointerTemp, $pointer, $null)
    } else {
        [IO.File]::Move($pointerTemp, $pointer)
    }
    $success = $true
    Log ('Installed v' + $m.version + ' successfully. Previous version retained.')
} catch {
    $message = $_.Exception.Message
    Log ('Update failed: ' + $message)
    if (-not $success -and $lock) {
        try {
            if ($started -and -not $started.HasExited) { Stop-Process -Id $started.Id -Force; $started.WaitForExit() }
            $game = $previousGame
            Log 'Previous version unchanged.'
            if ($mayRestart -and (Test-Path -LiteralPath (Join-Path $game 'project.godot'))) { $null = Start-Game }
        } catch { Log ('Rollback error: ' + $_.Exception.Message) }
    }
    try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($message + "`nSee update.log for details.", '1NFINITY D&D Updater') } catch { Write-Host $message }
    exit 1
} finally {
    if (-not $success -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $pointerTemp) { Remove-Item -LiteralPath $pointerTemp -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $ready) { Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue }
    if ($lock) { $lock.Dispose() }
}
 -and (Test-Path -LiteralPath (Join-Path (Join-Path $root $candidate) 'project.godot'))) { $active = $candidate }
}
$game = Join-Path $root $active
$previousGame = $game
$engine = Join-Path $root 'Godot.exe'
$log = Join-Path $root 'update.log'
$id = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $root ('.stage-' + $id)
$backup = Join-Path $root ('.previous-' + $id)
$ready = Join-Path $root ('ready-' + $id)
$lock = $null
$started = $null
$oldMoved = $false
$newMoved = $false
$success = $false
$mayRestart = $false
function Log([string]$message) {
    Write-Host $message
    Add-Content -LiteralPath $log -Value ("{0:u} {1}" -f (Get-Date), $message)
}
function Start-Game([string]$token = '') {
    $arguments = '--path "' + $game + '"'
    if ($token) { $arguments += ' -- ready=' + $token }
    Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $root -PassThru
}
function Git-BlobHash([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $prefix = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        [void]$sha.TransformBlock($prefix, 0, $prefix.Length, $prefix, 0)
        [void]$sha.TransformFinalBlock($bytes, 0, $bytes.Length)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
try {
    $lock = [IO.File]::Open((Join-Path $root '.update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Godot.exe is missing.' }
    if ($GamePid -gt 0) {
        $p = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
        if ($p) { Wait-Process -Id $GamePid -Timeout 30 -ErrorAction SilentlyContinue }
        if (Get-Process -Id $GamePid -ErrorAction SilentlyContinue) { throw 'Game did not close; no files changed.' }
        $mayRestart = $true
    }
    Log 'Checking Godot release channel...'
    $m = Invoke-RestMethod -Uri ($base + '/godot/channel.json?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -TimeoutSec 30 -Headers @{'Cache-Control'='no-cache'}
    if ($m.channel -ne 'godot' -or $m.version -notmatch '^\d+\.\d+\.\d+$' -or $m.source_commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid release manifest.' }
    if ($ExpectedVersion -and $ExpectedVersion -ne $m.version) { throw 'Release changed during update. Check again.' }
    $installed = Join-Path $game 'version.txt'
    if (Test-Path -LiteralPath $installed) {
        $current = (Get-Content -LiteralPath $installed -Raw).Trim()
        if ([version]$m.version -le [version]$current) { Log 'Already up to date.'; $null = Start-Game; $success = $true; return }
    }
    if (-not $m.files -or @($m.files).Count -gt 10000) { throw 'Invalid file list.' }
    New-Item -ItemType Directory -Path $stage | Out-Null
    $seen = @{}
    $i = 0
    foreach ($f in $m.files) {
        $path = [string]$f.path
        if ($path -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or ($path.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }) -or $f.blob -notmatch '^[0-9a-f]{40}$' -or $seen.ContainsKey($path)) { throw 'Invalid or duplicate file path/hash.' }
        $seen[$path] = $true
        $dest = [IO.Path]::GetFullPath((Join-Path $stage $path))
        if (-not $dest.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe release path.' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        $i++
        Log ("Downloading {0}/{1}: {2}" -f $i, @($m.files).Count, $path)
        Invoke-WebRequest -UseBasicParsing -Uri ($base + '/' + $m.source_commit + '/game/' + $path) -OutFile $dest -TimeoutSec 120
        if ((Git-BlobHash $dest) -ne $f.blob) { throw ('Integrity check failed: ' + $path) }
    }
    foreach ($required in @('project.godot','main.tscn','main.gd','version.txt')) { if (-not $seen.ContainsKey($required)) { throw ('Missing required file: ' + $required) } }
    if ((Get-Content -LiteralPath (Join-Path $stage 'version.txt') -Raw).Trim() -ne $m.version) { throw 'Release version mismatch.' }
    Log 'All files verified. Installing...'
    if (Test-Path -LiteralPath $game) { Move-Item -LiteralPath $game -Destination $backup; $oldMoved = $true }
    Move-Item -LiteralPath $stage -Destination $game
    $newMoved = $true
    # Source projects need an import pass before launching on a clean installation.
    $import = Start-Process -FilePath $engine -ArgumentList ('--headless --path "' + $game + '" --editor --import') -WorkingDirectory $root -PassThru
    if (-not $import.WaitForExit(120000)) { Stop-Process -Id $import.Id -Force -ErrorAction SilentlyContinue; throw 'Godot import timed out.' }
    if ($import.ExitCode -ne 0) { throw ('Godot import failed: ' + $import.ExitCode) }
    $started = Start-Game $id
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $ready) {
            if ((Get-Content -LiteralPath $ready -Raw).Trim() -eq $m.version) { $success = $true; break }
        }
        if ($started.HasExited) { throw 'New game exited before startup completed.' }
        Start-Sleep -Milliseconds 400
        $started.Refresh()
    }
    if (-not $success) { throw 'New game failed to confirm startup.' }
    Log ('Installed v' + $m.version + ' successfully.')
    if ($oldMoved) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
} catch {
    $message = $_.Exception.Message
    Log ('Update failed: ' + $message)
    if (-not $success -and $lock) {
        try {
            if ($started -and -not $started.HasExited) { Stop-Process -Id $started.Id -Force; $started.WaitForExit() }
            if ($newMoved -and (Test-Path -LiteralPath $game)) { Remove-Item -LiteralPath $game -Recurse -Force }
            if ($oldMoved) { Move-Item -LiteralPath $backup -Destination $game; Log 'Previous game restored.' }
            if ($mayRestart -and (Test-Path -LiteralPath (Join-Path $game 'project.godot'))) { $null = Start-Game }
        } catch { Log ('Rollback error: ' + $_.Exception.Message) }
    }
    try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($message + "`nSee update.log for details.", '1NFINITY D&D Updater') } catch { Write-Host $message }
    exit 1
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $ready) { Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue }
    if ($lock) { $lock.Dispose() }
}
