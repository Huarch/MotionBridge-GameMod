param(
    [string]$Version = "0.17.0",
    [string]$UE4SSArchive = "",
    [string]$PatchedUE4SSDll = "",
    [string]$PatchedUE4SSPdb = ""
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
$patchedUE4SSPdbExpectedSha256 = "0E0B99965A12CEF7389EC3721721941FC1D9EEEFAEE8EE5F0602962E5D3F454F"
if ([string]::IsNullOrWhiteSpace($UE4SSArchive)) {
    $UE4SSArchive = Join-Path $workspace ".deps/ue4ss-ba2efd55/$ue4ssAssetName"
}
if ([string]::IsNullOrWhiteSpace($PatchedUE4SSDll)) {
    $PatchedUE4SSDll = Join-Path $workspace ".artifacts/ue4ss-local-d4534c7/UE4SS.dll"
}
if ([string]::IsNullOrWhiteSpace($PatchedUE4SSPdb)) {
    $PatchedUE4SSPdb = Join-Path $workspace ".artifacts/ue4ss-local-d4534c7/UE4SS.pdb"
}
$ue4ssArchivePath = [System.IO.Path]::GetFullPath($UE4SSArchive)
$patchedUE4SSDllPath = [System.IO.Path]::GetFullPath($PatchedUE4SSDll)
$patchedUE4SSPdbPath = [System.IO.Path]::GetFullPath($PatchedUE4SSPdb)

if (-not $packageDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Package directory escaped the output root: $packageDir"
}
if (-not $archivePath.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive path escaped the output root: $archivePath"
}

$required = @(
    "fd_tcode_probe",
    "fd_tcode_reloader",
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
if (-not (Test-Path -LiteralPath $patchedUE4SSPdbPath)) {
    throw "The matching Playtest UE4SS PDB is required: $patchedUE4SSPdbPath"
}
$patchedUE4SSPdbActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchedUE4SSPdbPath).Hash
if ($patchedUE4SSPdbActualSha256 -ne $patchedUE4SSPdbExpectedSha256) {
    throw "Unexpected patched UE4SS PDB SHA-256: $patchedUE4SSPdbActualSha256"
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

Expand-Archive -LiteralPath $ue4ssArchivePath -DestinationPath $gameDir
$ue4ssDir = Join-Path $gameDir "ue4ss"
$modsDir = Join-Path $ue4ssDir "Mods"
$ue4ssSettingsPath = Join-Path $ue4ssDir "UE4SS-settings.ini"
$ue4ssSignaturesDir = Join-Path $ue4ssDir "UE4SS_Signatures"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ue4ssRequired = @(
    (Join-Path $gameDir "dwmapi.dll"),
    (Join-Path $ue4ssDir "UE4SS.dll"),
    (Join-Path $ue4ssDir "UE4SS-settings.ini"),
    (Join-Path $ue4ssDir "LICENSE"),
    $modsDir
)
foreach ($path in $ue4ssRequired) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Official UE4SS package is missing: $path"
    }
}

# Replace the experimental baseline with the locally built UE 5.7 safety fix.
Copy-Item -LiteralPath $patchedUE4SSDllPath -Destination (Join-Path $ue4ssDir "UE4SS.dll") -Force
Copy-Item -LiteralPath $patchedUE4SSPdbPath -Destination (Join-Path $ue4ssDir "UE4SS.pdb") -Force

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

Copy-Item -LiteralPath (Join-Path $workspace "fd_tcode_probe") -Destination (Join-Path $modsDir "fd_tcode_probe") -Recurse
Copy-Item -LiteralPath (Join-Path $workspace "fd_tcode_reloader") -Destination (Join-Path $modsDir "fd_tcode_reloader") -Recurse

$modsText = @'
CheatManagerEnablerMod : 0
ConsoleCommandsMod : 0
ConsoleEnablerMod : 0
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 0
BPModLoaderMod : 0
fd_tcode_reloader : 0
fd_tcode_probe : 1

; Built-in keybinds, do not move up!
Keybinds : 1
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.txt"), $modsText, $utf8NoBom)

$modsJson = @'
[
  {"mod_name":"CheatManagerEnablerMod","mod_enabled":false},
  {"mod_name":"ConsoleCommandsMod","mod_enabled":false},
  {"mod_name":"ConsoleEnablerMod","mod_enabled":false},
  {"mod_name":"SplitScreenMod","mod_enabled":false},
  {"mod_name":"LineTraceMod","mod_enabled":false},
  {"mod_name":"BPML_GenericFunctions","mod_enabled":false},
  {"mod_name":"BPModLoaderMod","mod_enabled":false},
  {"mod_name":"fd_tcode_reloader","mod_enabled":false},
  {"mod_name":"fd_tcode_probe","mod_enabled":true},
  {"mod_name":"Keybinds","mod_enabled":true}
]
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.json"), $modsJson, $utf8NoBom)

Copy-Item -LiteralPath (Join-Path $workspace "README.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "README-ZH.md") -Destination (Join-Path $packageDir "README-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")
Copy-Item -LiteralPath (Join-Path $workspace "tools/Install-FallenDollTCode.ps1") -Destination (Join-Path $packageDir "Install-Mod.ps1")

Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output $archivePath
