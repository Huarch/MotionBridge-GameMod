[CmdletBinding()]
param(
    [switch]$CoreOnly,
    [switch]$Portable,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$QtPrefix = $env:QT_PREFIX
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$buildRelative = if ($CoreOnly) { "companion\out\core" } else { "companion\out\app-qt-mingw" }
$buildDirectory = Join-Path $workspace $buildRelative
$configure = @("-S", (Join-Path $workspace "companion"), "-B", $buildDirectory, "-DMOTION_BRIDGE_BUILD_GUI=$(-not $CoreOnly)")
if (-not $CoreOnly) {
    if ([string]::IsNullOrWhiteSpace($QtPrefix)) {
        $candidate = Join-Path $workspace ".toolchain\qt\6.8.3\mingw_64"
        if (Test-Path -LiteralPath $candidate) { $QtPrefix = $candidate }
        else { throw "QtPrefix is required for the GUI build. Run Install-CompanionToolchain.ps1 first, then pass -QtPrefix <Qt kit>." }
    }
    $configure += "-DCMAKE_PREFIX_PATH=$QtPrefix"
    $compiler = Join-Path $workspace ".toolchain\qt-tools\Tools\mingw1310_64\bin\g++.exe"
    if (Test-Path -LiteralPath $compiler) {
        $compilerBin = Split-Path -Parent $compiler
        $env:PATH = "$compilerBin;$env:PATH"
        $configure += "-G"
        $configure += "MinGW Makefiles"
        $configure += "-DCMAKE_CXX_COMPILER=$compiler"
        $resourceCompiler = Join-Path $compilerBin "windres.exe"
        if (Test-Path -LiteralPath $resourceCompiler) {
            # windres crashes while launching its preprocessor when its own
            # executable path contains spaces. Preserve support for ordinary
            # Windows checkout paths by giving CMake the equivalent 8.3 path.
            $shortResourceCompiler = (& $env:ComSpec /d /c "for %I in (`"$resourceCompiler`") do @echo %~sI").Trim()
            if (-not [string]::IsNullOrWhiteSpace($shortResourceCompiler)) {
                $shortResourceCompiler = $shortResourceCompiler.Replace("\", "/")
                $configure += "-DCMAKE_RC_COMPILER=$shortResourceCompiler"
            }
        }
    }
}

cmake @configure
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $buildDirectory --config $Configuration
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
ctest --test-dir $buildDirectory -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Portable -and -not $CoreOnly) {
    $deploy = Join-Path $QtPrefix "bin\windeployqt.exe"
    if (-not (Test-Path -LiteralPath $deploy)) { throw "windeployqt was not found in $QtPrefix" }
    $portableDir = Join-Path $workspace "dist\MotionBridge-portable"
    $legacyPortableDir = Join-Path $workspace "dist\FallenDollTCodeCompanion-portable"
    New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
    $portableConfig = Join-Path $portableDir "config"
    $legacyPortableConfig = Join-Path $legacyPortableDir "config"
    if (-not (Test-Path -LiteralPath $portableConfig) -and (Test-Path -LiteralPath $legacyPortableConfig)) {
        Copy-Item -LiteralPath $legacyPortableConfig -Destination $portableConfig -Recurse
    }
    Copy-Item (Join-Path $buildDirectory "MotionBridge.exe") (Join-Path $portableDir "MotionBridge.exe") -Force
    Copy-Item (Join-Path $workspace "companion\portable.mode") (Join-Path $portableDir "portable.mode") -Force
    Copy-Item (Join-Path $workspace "THIRD_PARTY_NOTICES.md") (Join-Path $portableDir "THIRD_PARTY_NOTICES.md") -Force
    Copy-Item (Join-Path $workspace "companion\assets\models\sr6\LICENSE-osr-emu.txt") (Join-Path $portableDir "LICENSE-osr-emu.txt") -Force
    & $deploy --qmldir (Join-Path $workspace "companion\qml") --dir $portableDir (Join-Path $portableDir "MotionBridge.exe")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    # Keep the user's portable config beside the application, but never leak it
    # into a distributable ZIP. Each extracted copy creates/migrates its own INI.
    $packagePaths = Get-ChildItem -LiteralPath $portableDir |
        Where-Object { $_.Name -ne "config" } |
        ForEach-Object { $_.FullName }
    Compress-Archive -Path $packagePaths -DestinationPath (Join-Path $workspace "dist\MotionBridge-portable.zip") -Force
}
