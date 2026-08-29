param(
    [string]$Version = "0.17.2",
    [string]$UE4SSArchive = "",
    [string]$PatchedUE4SSDll = ""
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
& (Join-Path $PSScriptRoot "test_runtime_module_layout.ps1")
& (Join-Path $PSScriptRoot "test_hanime_gate_contract.ps1")
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace "dist"))
$packageName = "MotionBridge-FallenDoll-Playtest-Mod-$Version"
$packageDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $packageName))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "$packageName.zip"))

$ue4ssAssetName = "zDEV-UE4SS_v3.0.1-1093-gba2efd55.zip"
$ue4ssExpectedSha256 = "F4E2CEF8A8D5885FF3ADCD017154C9062E3EE2C8AB4D3FFECFB11B8C1C4CB69C"
$patchedUE4SSExpectedSha256 = "8D97EFB5C57671DA817BD5DF8D39FFB91F14C8071285C7A829B0C167A96E16EB"
if ([string]::IsNullOrWhiteSpace($UE4SSArchive)) {
    $UE4SSArchive = Join-Path $workspace ".deps/ue4ss-ba2efd55/$ue4ssAssetName"
}
if ([string]::IsNullOrWhiteSpace($PatchedUE4SSDll)) {
    $PatchedUE4SSDll = Join-Path $workspace ".artifacts/ue4ss-local-d4534c7/UE4SS.dll"
}
$ue4ssArchivePath = [System.IO.Path]::GetFullPath($UE4SSArchive)
$patchedUE4SSDllPath = [System.IO.Path]::GetFullPath($PatchedUE4SSDll)

if (-not $packageDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Package directory escaped the output root: $packageDir"
}
if (-not $archivePath.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive path escaped the output root: $archivePath"
}

$required = @(
    "fd_tcode_probe",
    "tools/Install-FallenDollTCode.ps1",
    "README.md",
    "README-ZH.md",
    "THIRD_PARTY_NOTICES.md",
    "packaging/ue4ss/FName_Constructor.lua"
)
foreach ($relativePath in $required) {
    $source = Join-Path $workspace $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required release input is missing: $source"
    }
}

if (-not (Test-Path -LiteralPath $ue4ssArchivePath)) {
    throw "UE4SS archive is required to build a release. Provide -UE4SSArchive with the verified $ue4ssAssetName file."
}
$ue4ssActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ue4ssArchivePath).Hash
if ($ue4ssActualSha256 -ne $ue4ssExpectedSha256) {
    throw "Unexpected UE4SS archive SHA-256: $ue4ssActualSha256"
}
if (-not (Test-Path -LiteralPath $patchedUE4SSDllPath)) {
    throw "The locally built Playtest UE4SS DLL is required: $patchedUE4SSDllPath"
}
$patchedUE4SSActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchedUE4SSDllPath).Hash
if ($patchedUE4SSActualSha256 -ne $patchedUE4SSExpectedSha256) {
    throw "Unexpected patched UE4SS DLL SHA-256: $patchedUE4SSActualSha256"
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

New-Item -ItemType Directory -Path $packageDir | Out-Null
$gameDir = Join-Path $packageDir "Game"
New-Item -ItemType Directory -Path $gameDir | Out-Null

$officialExtractDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot ".ue4ss-official-$Version"))
if (-not $officialExtractDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "UE4SS extraction directory escaped the output root: $officialExtractDir"
}
if (Test-Path -LiteralPath $officialExtractDir) {
    Remove-Item -LiteralPath $officialExtractDir -Recurse -Force
}
New-Item -ItemType Directory -Path $officialExtractDir | Out-Null
Expand-Archive -LiteralPath $ue4ssArchivePath -DestinationPath $officialExtractDir

$officialGameDir = $officialExtractDir
$officialUE4SSDir = Join-Path $officialGameDir "ue4ss"
$ue4ssDir = Join-Path $gameDir "ue4ss"
$modsDir = Join-Path $ue4ssDir "Mods"
$ue4ssSettingsPath = Join-Path $ue4ssDir "UE4SS-settings.ini"
$ue4ssSignaturesDir = Join-Path $ue4ssDir "UE4SS_Signatures"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ue4ssRequired = @(
    (Join-Path $officialGameDir "dwmapi.dll"),
    (Join-Path $officialUE4SSDir "UE4SS-settings.ini"),
    (Join-Path $officialUE4SSDir "LICENSE"),
    (Join-Path $officialUE4SSDir "Mods/Keybinds"),
    (Join-Path $officialUE4SSDir "Mods/shared")
)
foreach ($path in $ue4ssRequired) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Official UE4SS package is missing: $path"
    }
}

# Build from an explicit runtime allowlist. The official archive also contains
# documentation, debugger Mods, PDBs, map-generation assets, and templates that
# are useful for UE4SS development but are not part of the player package.
New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
New-Item -ItemType Directory -Path $ue4ssSignaturesDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $officialGameDir "dwmapi.dll") -Destination $gameDir
Copy-Item -LiteralPath (Join-Path $officialUE4SSDir "UE4SS-settings.ini") -Destination $ue4ssDir
Copy-Item -LiteralPath (Join-Path $officialUE4SSDir "LICENSE") -Destination $ue4ssDir
Copy-Item -LiteralPath (Join-Path $officialUE4SSDir "Mods/Keybinds") -Destination $modsDir -Recurse
Copy-Item -LiteralPath (Join-Path $officialUE4SSDir "Mods/shared") -Destination $modsDir -Recurse

# Replace the experimental baseline with the locally built UE 5.7 safety fix.
# Debug symbols stay in the build artifacts and are intentionally not shipped.
Copy-Item -LiteralPath $patchedUE4SSDllPath -Destination (Join-Path $ue4ssDir "UE4SS.dll")

# Configure the current Playtest engine and keep file logging without opening a
# debug console.
$ue4ssSettings = Get-Content -Raw -LiteralPath $ue4ssSettingsPath
$ue4ssSettings = $ue4ssSettings -replace '(?m)^EnableHotReloadSystem\s*=.*$', 'EnableHotReloadSystem = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^MajorVersion\s*=.*$', 'MajorVersion = 5'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^MinorVersion\s*=.*$', 'MinorVersion = 7'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^ConsoleEnabled\s*=.*$', 'ConsoleEnabled = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^GuiConsoleEnabled\s*=.*$', 'GuiConsoleEnabled = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^GuiConsoleVisible\s*=.*$', 'GuiConsoleVisible = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^EnableDumping\s*=.*$', 'EnableDumping = 0'
[System.IO.File]::WriteAllText($ue4ssSettingsPath, $ue4ssSettings, $utf8NoBom)
Copy-Item -LiteralPath (Join-Path $workspace "packaging/ue4ss/FName_Constructor.lua") -Destination (Join-Path $ue4ssSignaturesDir "FName_Constructor.lua") -Force

$probeDir = Join-Path $modsDir "fd_tcode_probe"
New-Item -ItemType Directory -Path $probeDir | Out-Null
Copy-Item -LiteralPath (Join-Path $workspace "fd_tcode_probe/Scripts") -Destination $probeDir -Recurse

$modsText = @'
fd_tcode_probe : 1

; Built-in keybinds, do not move up!
Keybinds : 1
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.txt"), $modsText, $utf8NoBom)

$modsJson = @'
[
  {"mod_name":"fd_tcode_probe","mod_enabled":true},
  {"mod_name":"Keybinds","mod_enabled":true}
]
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.json"), $modsJson, $utf8NoBom)

Copy-Item -LiteralPath (Join-Path $workspace "README.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "README-ZH.md") -Destination (Join-Path $packageDir "README-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")
Copy-Item -LiteralPath (Join-Path $workspace "tools/Install-FallenDollTCode.ps1") -Destination (Join-Path $packageDir "Install-Mod.ps1")

$allowedUE4SSEntries = @(
    "LICENSE",
    "Mods",
    "UE4SS-settings.ini",
    "UE4SS.dll",
    "UE4SS_Signatures"
)
$unexpectedUE4SSEntries = @(
    Get-ChildItem -LiteralPath $ue4ssDir -Force |
        Where-Object { $_.Name -notin $allowedUE4SSEntries } |
        Select-Object -ExpandProperty Name
)
if ($unexpectedUE4SSEntries.Count -gt 0) {
    throw "Unexpected UE4SS release entries: $($unexpectedUE4SSEntries -join ', ')"
}

$allowedModEntries = @("fd_tcode_probe", "Keybinds", "shared", "mods.json", "mods.txt")
$unexpectedModEntries = @(
    Get-ChildItem -LiteralPath $modsDir -Force |
        Where-Object { $_.Name -notin $allowedModEntries } |
        Select-Object -ExpandProperty Name
)
if ($unexpectedModEntries.Count -gt 0) {
    throw "Unexpected UE4SS Mod release entries: $($unexpectedModEntries -join ', ')"
}

Remove-Item -LiteralPath $officialExtractDir -Recurse -Force

Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output $archivePath
