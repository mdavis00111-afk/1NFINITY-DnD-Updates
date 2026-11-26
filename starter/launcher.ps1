param(
    [ValidateSet('Launch','Update','Rollback')][string]$Mode = 'Launch',
    [string]$ExpectedVersion = '',
    [int]$GamePid = 0
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
$game = Join-Path $root 'game'
$backup = Join-Path $root 'game.previous'
$engine = Join-Path $root 'Godot.exe'
$stage = Join-Path $root ('stage-' + [Guid]::NewGuid().ToString('N'))
$repo = 'mdavis00111-afk/1NFINITY-DnD-Updates'
$branch = 'hybrid4-godot'
$headers = @{'User-Agent'='1NFINITY-Hybrid4-Updater';'Accept'='application/vnd.github+json'}
$lock = $null
function Manifest($folder) {
    Get-Content -LiteralPath (Join-Path $folder 'version.json') -Raw | ConvertFrom-Json
}
function Download-Game {
    Write-Host 'Resolving Godot update channel...'
    $commit = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repo/commits/$branch" -TimeoutSec 45
    $sha = [string]$commit.sha
    if ($sha -notmatch '^[0-9a-f]{40}$') { throw 'Invalid commit ID.' }
    $tree = Invoke-RestMethod -Headers $headers -Uri ("https://api.github.com/repos/$repo/git/trees/" + $commit.commit.tree.sha + '?recursive=1') -TimeoutSec 45
    if ($tree.truncated) { throw 'Repository tree is truncated.' }
    $files = @($tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path.StartsWith('game/') })
    if ($files.Count -lt 3) { throw 'Incomplete game payload.' }
    New-Item -ItemType Directory -Path $stage | Out-Null
    $n = 0
    foreach ($f in $files) {
        $relative = $f.path.Substring(5)
        if ($f.mode -ne '100644' -and $f.mode -ne '100755') { throw 'Unsupported file type.' }
        if ($relative -match '(^|/)\.\.?(/|$)|[\\:]|(^|/)\.godot(/|$)' -or [string]::IsNullOrWhiteSpace($relative)) { throw 'Unsafe file path.' }
        $dest = [IO.Path]::GetFullPath((Join-Path $stage $relative))
        if (-not $dest.StartsWith($stage + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe destination.' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        $escaped = (($f.path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        $n++
        Write-Host "Downloading $n/$($files.Count): $relative"
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/$repo/$sha/$escaped" -OutFile $dest -TimeoutSec 120
        $bytes = [IO.File]::ReadAllBytes($dest)
        $prefix = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)" + [char]0)
        $hash = [Security.Cryptography.SHA1]::Create()
        try { $actual = [BitConverter]::ToString($hash.ComputeHash([byte[]]($prefix + $bytes))).Replace('-','').ToLowerInvariant() } finally { $hash.Dispose() }
        if ($actual -ne $f.sha) { throw "Git blob verification failed: $relative" }
    }
    foreach ($required in @('project.godot','main.tscn','main.gd','version.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $required) -PathType Leaf)) { throw "Missing $required" }
    }
    $new = Manifest $stage
    if ($new.channel -ne $branch -or $new.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid version manifest.' }
    if ($ExpectedVersion -and $new.version -ne $ExpectedVersion) { throw 'Version changed since the check. Please check again.' }
    if ((Test-Path -LiteralPath $game) -and ([version]$new.version -le [version](Manifest $game).version)) { throw 'Update is not newer than the installed game.' }
    Write-Host "Installing v$($new.version)..."
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
    if (Test-Path -LiteralPath $game) { Move-Item -LiteralPath $game -Destination $backup }
    try { Move-Item -LiteralPath $stage -Destination $game } catch {
        if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $game)) { Move-Item -LiteralPath $backup -Destination $game }
        throw
    }
}
function Start-Game {
    Write-Host "Starting 1NFINITY D&D v$((Manifest $game).version)..."
    Start-Process -FilePath $engine -ArgumentList @('--path', ('"' + $game + '"')) -WorkingDirectory $root
}
try {
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Godot.exe is missing.' }
    $lock = [IO.File]::Open((Join-Path $root 'launcher.lock'),'OpenOrCreate','ReadWrite','None')
    if ($GamePid -gt 0) {
        $p = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
        if ($p) { Wait-Process -Id $GamePid -Timeout 30 -ErrorAction Stop }
    }
    # Never replace a payload while an instance of this engine is still running.
    $running = @(Get-Process -Name 'Godot' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $engine })
    if ($running.Count -gt 0) { throw 'Close the existing game before continuing.' }
    if ($Mode -eq 'Rollback') {
        if (-not (Test-Path -LiteralPath $backup)) { throw 'No previous version is available.' }
        if (Test-Path -LiteralPath $game) { Move-Item -LiteralPath $game -Destination $stage }
        try { Move-Item -LiteralPath $backup -Destination $game } catch {
            if (Test-Path -LiteralPath $stage) { Move-Item -LiteralPath $stage -Destination $game }; throw
        }
        if (Test-Path -LiteralPath $stage) { Move-Item -LiteralPath $stage -Destination $backup }
    } elseif ($Mode -eq 'Update' -or -not (Test-Path -LiteralPath $game)) {
        Download-Game
    }
    Start-Game
} catch {
    $message = $_.Exception.Message
    Write-Host "Launcher failed: $message" -ForegroundColor Red
    Add-Content -LiteralPath (Join-Path $root 'launcher.log') -Value "$(Get-Date -Format o) $Mode $message" -ErrorAction SilentlyContinue
    if ($Mode -eq 'Update' -and (Test-Path -LiteralPath (Join-Path $game 'project.godot'))) {
        try { Start-Game } catch { Write-Host $_.Exception.Message }
    }
    exit 1
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ($lock) { $lock.Dispose() }
}
