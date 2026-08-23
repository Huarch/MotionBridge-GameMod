param(
    [string]$Version = "0.15.0-l0-preview"
)

$ErrorActionPreference = "Stop"
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace "dist"))
$packageName = "FallenDollTCode-$Version"
$packageDir = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $packageName))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "$packageName.zip"))

if (-not $packageDir.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Package directory escaped the output root: $packageDir"
}
if (-not $archivePath.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive path escaped the output root: $archivePath"
}

$required = @(
    "fd_tcode_probe",
    "fd_tcode_reloader",
    "f8studio/fallen-doll-skeleton-preview-v15.json",
    "f8studio/0001-feat-add-Fallen-Doll-skeleton-source-service.patch",
    "docs/玩家发布说明.md",
    "README.md",
    "THIRD_PARTY_NOTICES.md"
)
foreach ($relativePath in $required) {
    $source = Join-Path $workspace $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required release input is missing: $source"
    }
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

New-Item -ItemType Directory -Path $packageDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $packageDir "UE4SS-Mods") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $packageDir "F8Studio") | Out-Null

Copy-Item -LiteralPath (Join-Path $workspace "fd_tcode_probe") -Destination (Join-Path $packageDir "UE4SS-Mods/fd_tcode_probe") -Recurse
Copy-Item -LiteralPath (Join-Path $workspace "fd_tcode_reloader") -Destination (Join-Path $packageDir "UE4SS-Mods/fd_tcode_reloader") -Recurse
Copy-Item -LiteralPath (Join-Path $workspace "f8studio/fallen-doll-skeleton-preview-v15.json") -Destination (Join-Path $packageDir "F8Studio/fallen-doll-skeleton-preview-v15.json")
Copy-Item -LiteralPath (Join-Path $workspace "f8studio/0001-feat-add-Fallen-Doll-skeleton-source-service.patch") -Destination (Join-Path $packageDir "F8Studio/f8studio-fallen-doll-source.patch")
Copy-Item -LiteralPath (Join-Path $workspace "docs/玩家发布说明.md") -Destination (Join-Path $packageDir "使用说明.md")
Copy-Item -LiteralPath (Join-Path $workspace "README.md") -Destination (Join-Path $packageDir "README.md")
Copy-Item -LiteralPath (Join-Path $workspace "THIRD_PARTY_NOTICES.md") -Destination (Join-Path $packageDir "THIRD_PARTY_NOTICES.md")

Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output $archivePath
