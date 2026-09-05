param(
    # Mod package version. The supported Playtest game version is documented
    # separately in README.md and README-ZH.md.
    [string]$Version = "0.17.6",
    [string]$UE4SSArchive = "",
    [string]$PatchedUE4SSDll = ""
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
& (Join-Path $PSScriptRoot "test_install_fallen_doll_tcode.ps1")
& (Join-Path $PSScriptRoot "test_runtime_module_layout.ps1")
& (Join-Path $PSScriptRoot "test_hanime_gate_contract.ps1")
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace "dist"))
$packageName = "MotionBridge-FallenDoll-Playtest-Mod-$Version"
$packageDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $packageName))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "$packageName.zip"))

$ue4ssAssetName = "zDEV-UE4SS_v3.0.1-1093-gba2efd55.zip"
$ue4ssExpectedSha256 = "F4E2CEF8A8D5885FF3ADCD017154C9062E3EE2C8AB4D3FFECFB11B8C1C4CB69C"
# Source: https://github.com/Huarch/RE-UE4SS/commit/4ff3595375a7f6949179b19d4aa7ea7031a4aa21
$patchedUE4SSExpectedSha256 = "18A406D9578CA11894F27908CC2A253087A711A83581A0C5A11DB65931FD798C"
if ([string]::IsNullOrWhiteSpace($UE4SSArchive)) {
    $UE4SSArchive = Join-Path $workspace ".deps/ue4ss-ba2efd55/$ue4ssAssetName"
}
if ([string]::IsNullOrWhiteSpace($PatchedUE4SSDll)) {
    $PatchedUE4SSDll = Join-Path $workspace ".artifacts/ue4ss-local-4ff35953/UE4SS.dll"
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
    "packaging/Install Mod.cmd",
    "packaging/README.txt",
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
    (Join-Path $officialUE4SSDir "LICENSE")
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
$probeRuntimeFiles = @(
    "Scripts/main.lua",
    "Scripts/fd_tcode/app.lua",
    "Scripts/fd_tcode/config.lua",
    "Scripts/fd_tcode/edition_local.lua",
    "Scripts/fd_tcode/core/generic_hanime_probe.lua",
    "Scripts/fd_tcode/core/hanime_component_registry.lua",
    "Scripts/fd_tcode/core/hanime_detector.lua",
    "Scripts/fd_tcode/core/hanime_hsystem_state.lua",
    "Scripts/fd_tcode/core/hanime_identity_catalog.lua",
    "Scripts/fd_tcode/core/hanime_identity_resolver.lua",
    "Scripts/fd_tcode/core/hanime_manager_event_probe.lua",
    "Scripts/fd_tcode/core/hanime_motion_contract.lua",
    "Scripts/fd_tcode/core/hanime_runtime.lua",
    "Scripts/fd_tcode/core/hscene.lua",
    "Scripts/fd_tcode/core/local_player_action_gate.lua",
    "Scripts/fd_tcode/core/log.lua",
    "Scripts/fd_tcode/core/profile_store.lua",
    "Scripts/fd_tcode/core/safe.lua",
    "Scripts/fd_tcode/core/skeleton_catalog.lua",
    "Scripts/fd_tcode/core/skeleton_stream.lua",
    "Scripts/fd_tcode/data/ada_hanime_identity_data.lua",
    "Scripts/fd_tcode/data/body_plane_catalog.lua",
    "Scripts/fd_tcode/data/female_female_direct_l0_profile_data.lua",
    "Scripts/fd_tcode/data/female_female_provisional_profile_data.lua",
    "Scripts/fd_tcode/data/hanime_identity_data.lua",
    "Scripts/fd_tcode/data/nonhuman_component_binding_data.lua",
    "Scripts/fd_tcode/data/nonhuman_direct_output_profile_data.lua",
    "Scripts/fd_tcode/data/nonhuman_static_formal_profile_data.lua",
    "Scripts/fd_tcode/data/playtest_anim_blueprint_class_data.lua",
    "Scripts/fd_tcode/data/playtest_ue57_playable_hanime_identity_data.lua",
    "Scripts/fd_tcode/data/profile_data.lua",
    "Scripts/fd_tcode/data/sylph_direct_l0_profile_data.lua",
    "Scripts/fd_tcode/data/target_frame_catalog.lua",
    "Scripts/fd_tcode/data/update_2026_08_28_hanime_identity_data.lua"
)
foreach ($relativePath in $probeRuntimeFiles) {
    $source = Join-Path $workspace "fd_tcode_probe/$relativePath"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required Playtest runtime file is missing: $source"
    }
    $destination = Join-Path $probeDir $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

$optionalReleaseModules = @("fd_tcode.core.precision_capture")
$missingReleaseModules = @()
$releaseRequirePattern = 'require\(\s*["''](fd_tcode\.[^"'']+)["'']\s*\)'
foreach ($source in Get-ChildItem -LiteralPath (Join-Path $probeDir "Scripts") -Recurse -File -Filter "*.lua") {
    $sourceText = Get-Content -Raw -LiteralPath $source.FullName
    foreach ($match in [regex]::Matches($sourceText, $releaseRequirePattern)) {
        $moduleName = $match.Groups[1].Value
        $relativeModule = ($moduleName -replace '\.', '\') + ".lua"
        $target = Join-Path (Join-Path $probeDir "Scripts") $relativeModule
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -and $moduleName -notin $optionalReleaseModules) {
            $missingReleaseModules += "$($source.FullName): $moduleName"
        }
    }
}
if ($missingReleaseModules.Count -gt 0) {
    throw "Unresolved modules in minimal release:`n$($missingReleaseModules -join "`n")"
}

$modsText = @'
fd_tcode_probe : 1
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.txt"), $modsText, $utf8NoBom)

$modsJson = @'
[
  {"mod_name":"fd_tcode_probe","mod_enabled":true}
]
'@
[System.IO.File]::WriteAllText((Join-Path $modsDir "mods.json"), $modsJson, $utf8NoBom)

Copy-Item -LiteralPath (Join-Path $workspace "README.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "README-ZH.md") -Destination (Join-Path $packageDir "README-ZH.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")
Copy-Item -LiteralPath (Join-Path $workspace "tools/Install-FallenDollTCode.ps1") -Destination (Join-Path $packageDir "Install-Mod.ps1")
Copy-Item -LiteralPath (Join-Path $workspace "packaging/Install Mod.cmd") -Destination (Join-Path $packageDir "Install Mod.cmd")
Copy-Item -LiteralPath (Join-Path $workspace "packaging/README.txt") -Destination (Join-Path $packageDir "README.txt")

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

$allowedModEntries = @("fd_tcode_probe", "mods.json", "mods.txt")
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
