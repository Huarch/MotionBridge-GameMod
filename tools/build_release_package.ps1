param(
    # Mod package version. Supported Fallen Doll game versions are documented
    # separately in README.md and README-ZH.md.
    [string]$Version = "0.17.3",
    [string]$UE4SSArchive = ""
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
& (Join-Path $PSScriptRoot "test_install_fallen_doll_tcode.ps1")
& (Join-Path $PSScriptRoot "test_runtime_module_layout.ps1")
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace "dist"))
$packageName = "MotionBridge-FallenDoll-Demo-Mod-$Version"
$packageDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $packageName))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "$packageName.zip"))

$ue4ssAssetName = "UE4SS_v3.0.1-1028-gd7e7826d.zip"
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
    "packaging/Install Mod.cmd",
    "packaging/README.txt",
    "tools/Install-FallenDollTCode.ps1",
    "README.md",
    "README-ZH.md",
    "THIRD_PARTY_NOTICES.md"
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

Copy-Item -LiteralPath (Join-Path $workspace "README.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "README-ZH.md") -Destination (Join-Path $packageDir "README-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")
Copy-Item -LiteralPath (Join-Path $workspace "tools/Install-FallenDollTCode.ps1") -Destination (Join-Path $packageDir "Install-Mod.ps1")
$launcherSource = Join-Path $workspace "packaging/Install Mod.cmd"
$launcherDestination = Join-Path $packageDir "Install Mod.cmd"
$launcherText = [System.IO.File]::ReadAllText($launcherSource)
$launcherText = $launcherText -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($launcherDestination, $launcherText, [System.Text.Encoding]::ASCII)
$launcherBytes = [System.IO.File]::ReadAllBytes($launcherDestination)
if ($launcherBytes | Where-Object { $_ -gt 127 }) {
    throw "Install Mod.cmd must contain ASCII bytes only."
}
for ($index = 0; $index -lt $launcherBytes.Length; ++$index) {
    if ($launcherBytes[$index] -eq 10 -and ($index -eq 0 -or $launcherBytes[$index - 1] -ne 13)) {
        throw "Install Mod.cmd contains a bare LF; CRLF is required for cmd.exe."
    }
}
Copy-Item -LiteralPath (Join-Path $workspace "packaging/README.txt") -Destination (Join-Path $packageDir "README.txt")

Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output $archivePath
