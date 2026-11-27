param([Parameter(Mandatory=$true)][string]$RequestFile,[Parameter(Mandatory=$true)][string]$ResponseFile)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
try {
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'sqlite_bridge.cs'))
 Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Web.Extensions.dll','System.dll','System.Core.dll' -Language CSharp
 $response=[InfinitySqlite]::Run([IO.File]::ReadAllText($RequestFile))
 [IO.File]::WriteAllText($ResponseFile,$response,$utf8)
} catch {
 $response=@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json -Compress
 [IO.File]::WriteAllText($ResponseFile,$response,$utf8)
 exit 1
}
