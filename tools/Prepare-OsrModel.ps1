[CmdletBinding()]
param(
    [string]$OsrEmuRoot = "",
    [string]$QtPrefix = ""
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($OsrEmuRoot)) {
    $OsrEmuRoot = Join-Path $workspace ".deps\osr-emu"
}
if ([string]::IsNullOrWhiteSpace($QtPrefix)) {
    $QtPrefix = Join-Path $workspace ".toolchain\qt\6.8.3\mingw_64"
}

$sourceRoot = Join-Path $OsrEmuRoot "lib\models"
$outputRoot = Join-Path $workspace "companion\assets\models\sr6"

if (-not (Test-Path -LiteralPath (Join-Path $OsrEmuRoot "LICENSE"))) {
    throw "osr-emu source was not found at $OsrEmuRoot"
}
$geometry = [ordered]@{
    "base" = "sr6\geometry\base.js"
    "lid" = "sr6\geometry\lid.js"
    "receiver" = "sr6\geometry\receiver.js"
    "arm" = "sr6\geometry\arm.js"
    "bearing-arm" = "sr6\geometry\bearing-arm.js"
    "left-pitcher" = "sr6\geometry\left-pitcher.js"
    "right-pitcher" = "sr6\geometry\right-pitcher.js"
    "main-arm-servos" = "sr6\geometry\main-arm-servos.js"
    "case" = "common\case.js"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

foreach ($item in $geometry.GetEnumerator()) {
    $javascriptPath = Join-Path $sourceRoot $item.Value
    $javascript = Get-Content -LiteralPath $javascriptPath -Raw
    $match = [regex]::Match($javascript, '(?s)export default `(?<obj>.*)`;\s*$')
    if (-not $match.Success) {
        throw "Could not extract OBJ text from $javascriptPath"
    }

    $objPath = Join-Path $outputRoot ($item.Key + ".obj")
    [System.IO.File]::WriteAllText($objPath, $match.Groups["obj"].Value.TrimStart(), [System.Text.UTF8Encoding]::new($false))
}

Copy-Item -LiteralPath (Join-Path $OsrEmuRoot "LICENSE") -Destination (Join-Path $outputRoot "LICENSE-osr-emu.txt") -Force
Write-Output "Prepared SR6 model assets in $outputRoot"
