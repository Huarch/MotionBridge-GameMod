param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = "Stop"
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$files = @(
    "Install-Compatibility.ps1", "Install Compatibility.cmd", "README.txt",
    "compat7313_local_action.lua", "validation.json",
    "Signatures\StaticConstructObject.lua", "Signatures\GUObjectHashTables.lua", "Signatures\GNatives.lua",
    "Reference\hanime_detector-base.lua"
)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($OutputPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in $files) {
        $source = Join-Path $PSScriptRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Package file missing: $relative" }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, $relative.Replace('\','/'), [IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }
Write-Output ([IO.Path]::GetFullPath($OutputPath))
