[CmdletBinding()]
param(
    [string]$GameRoot = "",
    [string]$RestoreBackup = "",
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$names = @("StaticConstructObject.lua", "GUObjectHashTables.lua", "GNatives.lua")
$coreRelative = "Mods\fd_tcode_probe\Scripts\fd_tcode\core"
$relativeFiles = @($names | ForEach-Object { "UE4SS_Signatures\$_" })
$relativeFiles += "$coreRelative\compat7313_local_action.lua"
$relativeFiles += "$coreRelative\hanime_detector.lua"

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    if (-not $Interactive) { throw "Specify -GameRoot (the folder containing Paralogue)." }
    $GameRoot = (Read-Host "Game root (folder containing Paralogue)").Trim().Trim('"')
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$exe = Join-Path $GameRoot "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe"
$ue4ss = Join-Path (Split-Path -Parent $exe) "ue4ss"
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Game executable not found: $exe" }
foreach ($process in @(Get-Process -Name "Paralogue-Win64-Shipping" -ErrorAction SilentlyContinue)) {
    if ($process.Path -eq $exe) { throw "Close this game before installing or restoring." }
}
$backupRoot = Join-Path $ue4ss "MotionBridge-7313-backups"

if (-not [string]::IsNullOrWhiteSpace($RestoreBackup)) {
    $restorePath = [IO.Path]::GetFullPath($RestoreBackup)
    $prefix = [IO.Path]::GetFullPath($backupRoot).TrimEnd('\') + '\'
    if (-not $restorePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup must be inside this game's MotionBridge-7313-backups directory."
    }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $restorePath "manifest.json") | ConvertFrom-Json
    if ($manifest.gameRoot -ne $GameRoot -or @($manifest.files).Count -ne $relativeFiles.Count) {
        throw "Backup manifest does not match this game."
    }
    $seen = @{}
    foreach ($entry in $manifest.files) {
        if ($entry.path -notin $relativeFiles -or $seen.ContainsKey($entry.path)) { throw "Invalid backup file list." }
        $seen[$entry.path] = $true
        if ($entry.existed -and -not (Test-Path -LiteralPath (Join-Path $restorePath $entry.path) -PathType Leaf)) {
            throw "Backup file is missing: $($entry.path)"
        }
    }
    foreach ($entry in $manifest.files) {
        $destination = Join-Path $ue4ss $entry.path
        if ($entry.existed) {
            Copy-Item -LiteralPath (Join-Path $restorePath $entry.path) -Destination $destination -Force
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    Write-Output "Restored compatibility files from: $restorePath"
    exit 0
}

foreach ($required in @("UE4SS.dll", "$coreRelative\hanime_detector.lua", "Mods\fd_tcode_probe\Scripts\fd_tcode\config.lua")) {
    if (-not (Test-Path -LiteralPath (Join-Path $ue4ss $required) -PathType Leaf)) {
        throw "Install your original Playtest Mod 0.18.1 package first. Missing: $required"
    }
}
$config = [IO.File]::ReadAllText((Join-Path $ue4ss "Mods\fd_tcode_probe\Scripts\fd_tcode\config.lua"))
if ($config -notmatch 'version\s*=\s*"0\.18\.1"') { throw "This community add-on requires Mod 0.18.1." }

# Check the tested executable's code at three independent locations. No digest
# or executable modification is performed. Other layouts are refused.
$checks = @(
    @{ Offset = 0x15F6F10; File = "StaticConstructObject.lua" },
    @{ Offset = 0x15EE20F; File = "GUObjectHashTables.lua" },
    @{ Offset = 0x15C5CFB; File = "GNatives.lua" }
)
$stream = [IO.File]::OpenRead($exe)
try {
    if ($stream.Length -ne 191914496) { throw "This executable is not the tested 0.9.0b-7313 layout." }
    foreach ($check in $checks) {
        $signatureText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ("Signatures\" + $check.File)))
        $match = [regex]::Match($signatureText, 'return "([0-9A-F? ]+)"')
        if (-not $match.Success) { throw "Invalid signature payload." }
        $tokens = $match.Groups[1].Value.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        [void]$stream.Seek($check.Offset, [IO.SeekOrigin]::Begin)
        foreach ($token in $tokens) {
            $actual = $stream.ReadByte()
            if ($actual -lt 0 -or ($token -ne "??" -and $actual -ne [Convert]::ToInt32($token, 16))) {
                throw "Executable code does not match the tested build: $($check.File)"
            }
        }
    }
} finally { $stream.Dispose() }

function Normalize-Newlines([string]$Text) { return $Text.Replace("`r`n", "`n") }
$detectorPath = Join-Path $ue4ss "$coreRelative\hanime_detector.lua"
$original = Normalize-Newlines ([IO.File]::ReadAllText((Join-Path $PSScriptRoot "Reference\hanime_detector-base.lua")))
$patched = $original.Replace('local HAnimeDetector = {', "local Compat7313LocalAction = require(`"fd_tcode.core.compat7313_local_action`")`n`nlocal HAnimeDetector = {")
$patched = $patched.Replace('function HAnimeDetector.sample()', "function HAnimeDetector.sample()`n    Compat7313LocalAction.refresh(HAnimeDetector)")
$patched = $patched.Replace('function HAnimeDetector.queue_actor_components(actor)', "function HAnimeDetector.queue_actor_components(actor)`n    Compat7313LocalAction.observe_actor(actor)")
$current = Normalize-Newlines ([IO.File]::ReadAllText($detectorPath))
if ($current -cne $original -and $current -cne $patched) {
    throw "Installed detector differs from the tested 0.18.1 version. No files were changed."
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "compat7313_local_action.lua") -PathType Leaf)) {
    throw "Local state adapter payload is missing."
}

$backup = Join-Path $backupRoot (Get-Date -Format "yyyyMMdd-HHmmss-fffffff")
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$entries = @()
foreach ($relative in $relativeFiles) {
    $destination = Join-Path $ue4ss $relative
    $existed = Test-Path -LiteralPath $destination -PathType Leaf
    if ($existed) {
        $backupFile = Join-Path $backup $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupFile) -Force | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backupFile
    }
    $entries += [pscustomobject]@{ path=$relative; existed=$existed }
}
$manifest = [pscustomobject]@{ gameRoot=$GameRoot; files=$entries }
[IO.File]::WriteAllText((Join-Path $backup "manifest.json"), ($manifest | ConvertTo-Json -Depth 5), $utf8)
try {
    New-Item -ItemType Directory -Path (Join-Path $ue4ss "UE4SS_Signatures") -Force | Out-Null
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Signatures\$name") -Destination (Join-Path $ue4ss "UE4SS_Signatures\$name") -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "compat7313_local_action.lua") -Destination (Join-Path $ue4ss "$coreRelative\compat7313_local_action.lua") -Force
    [IO.File]::WriteAllText($detectorPath, $patched, $utf8)
} catch {
    foreach ($entry in $entries) {
        $destination = Join-Path $ue4ss $entry.path
        if ($entry.existed) {
            Copy-Item -LiteralPath (Join-Path $backup $entry.path) -Destination $destination -Force
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    throw
}
Write-Output "Installed Community 0.9.0b compatibility v0.18.1 (tested build 7313, desktop single room)."
Write-Output "Your UE4SS DLL, settings and local configuration were preserved."
Write-Output "Backup: $backup"
Write-Output "Restore with this script's -GameRoot and -RestoreBackup parameters."
