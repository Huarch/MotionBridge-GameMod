$ErrorActionPreference = "Stop"

$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$scriptsRoot = Join-Path $workspace "fd_tcode_probe\Scripts"
$moduleRoot = Join-Path $scriptsRoot "fd_tcode"
$expectedRootModules = @("app.lua", "config.lua", "edition_local.lua")
$actualRootModules = @(
    Get-ChildItem -LiteralPath $moduleRoot -File -Filter "*.lua" |
        Select-Object -ExpandProperty Name |
        Sort-Object
)

if (($actualRootModules -join "|") -ne (($expectedRootModules | Sort-Object) -join "|")) {
    throw "Unexpected root module layout: $($actualRootModules -join ', ')"
}
foreach ($layer in @("core", "data")) {
    $layerPath = Join-Path $moduleRoot $layer
    if (-not (Test-Path -LiteralPath $layerPath -PathType Container)) {
        throw "Missing runtime module layer: $layerPath"
    }
    if (@(Get-ChildItem -LiteralPath $layerPath -File -Filter "*.lua").Count -eq 0) {
        throw "Empty runtime module layer: $layerPath"
    }
}

$missing = @()
$pattern = '(?:require|optional_table)\(\s*["''](fd_tcode\.[^"'']+)["'']\s*\)'
foreach ($source in Get-ChildItem -LiteralPath $scriptsRoot -Recurse -File -Filter "*.lua") {
    $text = Get-Content -Raw -LiteralPath $source.FullName
    foreach ($match in [regex]::Matches($text, $pattern)) {
        $relative = ($match.Groups[1].Value -replace '\.', '\') + ".lua"
        $target = Join-Path $scriptsRoot $relative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $missing += "$($source.FullName): $($match.Groups[1].Value)"
        }
    }
}
if ($missing.Count -gt 0) {
    throw "Unresolved internal modules:`n$($missing -join "`n")"
}

$profileStore = Get-Content -Raw -LiteralPath (Join-Path $moduleRoot "core\profile_store.lua")
if ($profileStore -notmatch [regex]::Escape('directory .. "../data/"')) {
    throw "profile_store.lua does not resolve generated rules from data/"
}

Write-Output "Runtime module layout verified: entry=3 core/data resolved"
