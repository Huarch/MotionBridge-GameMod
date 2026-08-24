param(
    [string]$Version = "0.17.0",
    [string]$UE4SSArchive = ""
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace "dist"))
$packageName = "FallenDollTCode-$Version"
$packageDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $packageName))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "$packageName.zip"))

$ue4ssAssetName = "UE4SS_v3.0.1-1028-gd7e7826d.zip"
$ue4ssAssetUrl = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/$ue4ssAssetName"
$ue4ssExpectedSha256 = "342D893C3F64CB36B88AC4D58CEFC1DD8571B9E37B03F86B793F63955CCC2C0B"
if ([string]::IsNullOrWhiteSpace($UE4SSArchive)) {
    $UE4SSArchive = Join-Path $workspace ".deps/ue4ss-d7e7826/$ue4ssAssetName"
}
$ue4ssArchivePath = [System.IO.Path]::GetFullPath($UE4SSArchive)

if (-not $packageDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Package directory escaped the output root: $packageDir"
}
if (-not $archivePath.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive path escaped the output root: $archivePath"
}

$required = @(
    "fd_tcode_probe",
    "fd_tcode_reloader",
    "f8studio/fallen-doll-skeleton-preview-v17.json",
    "f8studio/0001-feat-add-Fallen-Doll-skeleton-source-service.patch",
    "f8studio/0001-feat-pyengine-add-multi-bone-contact-axes.patch",
    "f8studio/0002-fix-sdk-use-generated-state-field-alias.patch",
    "f8studio/0003-feat-tcode-expose-all-SR6-graph-inputs.patch",
    "f8studio/0004-fix-sdk-support-generated-wire-field-aliases.patch",
    "f8studio/0005-refactor-pyengine-isolate-and-cache-contact-geometry.patch",
    "f8studio/0006-fix-fallen-doll-apply-target-specific-hand-basis.patch",
    "f8studio/0007-perf-sr6-route-axes-as-atomic-frames.patch",
    "f8studio/0008-fix-sr6-stabilize-functional-contact-targets.patch",
    "f8studio/0009-feat-studio-add-compact-range-slider-controls.patch",
    "f8studio/0010-fix-fallen-doll-calibrate-relative-twist-and-foot-co.patch",
    "tools/Install-FallenDollTCode.ps1",
    "docs/user-guide-zh.md",
    "docs/user-guide-en.md",
    "docs/startup-and-troubleshooting-zh.md",
    "docs/startup-and-troubleshooting-en.md",
    "docs/release-notes-v0.17.0.md",
    "THIRD_PARTY_NOTICES.md"
)
foreach ($relativePath in $required) {
    $source = Join-Path $workspace $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required release input is missing: $source"
    }
}

if (-not (Test-Path -LiteralPath $ue4ssArchivePath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ue4ssArchivePath) | Out-Null
    Invoke-WebRequest -Uri $ue4ssAssetUrl -OutFile $ue4ssArchivePath
}
$ue4ssActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ue4ssArchivePath).Hash
if ($ue4ssActualSha256 -ne $ue4ssExpectedSha256) {
    throw "Unexpected UE4SS archive SHA-256: $ue4ssActualSha256"
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
$studioDir = Join-Path $packageDir "F8Studio"
$patchDir = Join-Path $studioDir "Patches"
New-Item -ItemType Directory -Path $gameDir | Out-Null
New-Item -ItemType Directory -Path $studioDir | Out-Null
New-Item -ItemType Directory -Path $patchDir | Out-Null

Expand-Archive -LiteralPath $ue4ssArchivePath -DestinationPath $gameDir
$ue4ssDir = Join-Path $gameDir "ue4ss"
$modsDir = Join-Path $ue4ssDir "Mods"
$ue4ssSettingsPath = Join-Path $ue4ssDir "UE4SS-settings.ini"
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

# Keep UE4SS file logging available, but do not open either debug console for
# players on every game launch.
$ue4ssSettings = Get-Content -Raw -LiteralPath $ue4ssSettingsPath
$ue4ssSettings = $ue4ssSettings -replace '(?m)^ConsoleEnabled\s*=.*$', 'ConsoleEnabled = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^GuiConsoleEnabled\s*=.*$', 'GuiConsoleEnabled = 0'
$ue4ssSettings = $ue4ssSettings -replace '(?m)^GuiConsoleVisible\s*=.*$', 'GuiConsoleVisible = 0'
[System.IO.File]::WriteAllText($ue4ssSettingsPath, $ue4ssSettings, $utf8NoBom)

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
fd_tcode_reloader : 1
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
  {"mod_name":"fd_tcode_reloader","mod_enabled":true},
  {"mod_name":"fd_tcode_probe","mod_enabled":true},
  {"mod_name":"Keybinds","mod_enabled":true}
]
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.json"), $modsJson, $utf8NoBom)

Copy-Item -LiteralPath (Join-Path $workspace "f8studio/fallen-doll-skeleton-preview-v17.json") -Destination (Join-Path $studioDir "fallen-doll-skeleton-preview-v17.json")
$studioPatches = @(
    "0001-feat-add-Fallen-Doll-skeleton-source-service.patch",
    "0001-feat-pyengine-add-multi-bone-contact-axes.patch",
    "0002-fix-sdk-use-generated-state-field-alias.patch",
    "0003-feat-tcode-expose-all-SR6-graph-inputs.patch",
    "0004-fix-sdk-support-generated-wire-field-aliases.patch",
    "0005-refactor-pyengine-isolate-and-cache-contact-geometry.patch",
    "0006-fix-fallen-doll-apply-target-specific-hand-basis.patch",
    "0007-perf-sr6-route-axes-as-atomic-frames.patch",
    "0008-fix-sr6-stabilize-functional-contact-targets.patch",
    "0009-feat-studio-add-compact-range-slider-controls.patch",
    "0010-fix-fallen-doll-calibrate-relative-twist-and-foot-co.patch"
)
foreach ($patch in $studioPatches) {
    Copy-Item -LiteralPath (Join-Path $workspace "f8studio/$patch") -Destination (Join-Path $patchDir $patch)
}
Copy-Item -LiteralPath (Join-Path $workspace "docs/user-guide-zh.md") -Destination (Join-Path $packageDir "README-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "docs/user-guide-en.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "docs/startup-and-troubleshooting-zh.md") -Destination (Join-Path $packageDir "Startup-and-Troubleshooting-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "docs/startup-and-troubleshooting-en.md") -Destination (Join-Path $packageDir "Startup-and-Troubleshooting-English.md")
Copy-Item -LiteralPath (Join-Path $workspace "docs/release-notes-v0.17.0.md") -Destination (Join-Path $packageDir "RELEASE-NOTES.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")
Copy-Item -LiteralPath (Join-Path $workspace "tools/Install-FallenDollTCode.ps1") -Destination (Join-Path $packageDir "Install-Mod.ps1")

Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output $archivePath
