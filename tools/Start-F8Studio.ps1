[CmdletBinding()]
param(
    [string]$F8StudioRoot = (Join-Path $PSScriptRoot "..\.deps\f8studio-pr")
)

$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath($F8StudioRoot)
$python = Join-Path $root ".pixi\envs\default\python.exe"
$localPixi = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.toolchain\pixi\pixi.exe"))

if (-not (Test-Path -LiteralPath (Join-Path $root "pixi.toml") -PathType Leaf)) {
    throw "F8Studio source checkout not found: $root"
}
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "F8Studio default environment is missing. Install it with Pixi first: $python"
}

if (-not (Get-Command pixi -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $localPixi)) {
    $env:PATH = "$(Split-Path -Parent $localPixi);$env:PATH"
}

$connectionFile = Join-Path $env:USERPROFILE ".f8\studio\automation\connection.json"
Set-Location -LiteralPath $root
& $python -m f8pystudio.main --automation --automation-port-file $connectionFile
