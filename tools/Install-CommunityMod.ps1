[CmdletBinding()]
param([string]$GameRoot = "", [switch]$Interactive)
$ErrorActionPreference = "Stop"
try {
    if ([string]::IsNullOrWhiteSpace($GameRoot)) {
        if (-not $Interactive) { throw "Specify -GameRoot." }
        $GameRoot = (Read-Host "Community 0.9.0b game root (contains Paralogue)").Trim().Trim('"')
    }
    $GameRoot = [IO.Path]::GetFullPath($GameRoot)
    $payload = Join-Path $PSScriptRoot "Game"
    $compat = Join-Path $PSScriptRoot "CommunityCompatibility/Install-Compatibility.ps1"
    $base = Join-Path $PSScriptRoot "Internal/Install-Base.ps1"
    foreach ($path in @($payload, $compat, $base)) { if (-not (Test-Path -LiteralPath $path)) { throw "Extract the entire ZIP first. Missing: $path" } }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compat -GameRoot $GameRoot -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw "Unsupported community executable; no files installed." }
    $target = Join-Path $GameRoot "Paralogue/Binaries/Win64"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fffffff"
    $backup = Join-Path $target ("ue4ss/CommunityMod-backups/" + $stamp)
    $existing = @()
    foreach ($item in Get-ChildItem -LiteralPath $payload -Recurse -File) {
        $relative = $item.FullName.Substring($payload.Length).TrimStart('\','/')
        $destination = Join-Path $target $relative
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $saved = Join-Path $backup $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
            Copy-Item -LiteralPath $destination -Destination $saved
            $existing += $relative
        }
    }
    if ($existing.Count) { $existing | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup "files.json") -Encoding UTF8 }
    & $base -GameRoot $GameRoot -Edition Playtest -PayloadRoot $payload | ForEach-Object { if ($_ -notmatch "^Configured local runtime edition:") { "$_".Replace("Playtest", "Community 0.9.0b") } }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compat -GameRoot $GameRoot
    if ($LASTEXITCODE -ne 0) { throw "Community setup failed; backup retained at $backup" }
    foreach ($relative in @("ue4ss/UE4SS-settings.ini", "ue4ss/Mods/fd_tcode_probe/Scripts/fd_tcode/config.lua")) {
        $saved = Join-Path $backup $relative
        if (Test-Path -LiteralPath $saved) {
            if ($relative.EndsWith("config.lua")) {
                $text = [IO.File]::ReadAllText($saved) -replace 'version\s*=\s*"[^"\r\n]+"', 'version = "0.18.1"'
                [IO.File]::WriteAllText((Join-Path $target $relative), $text, (New-Object Text.UTF8Encoding($false)))
            } else { Copy-Item -LiteralPath $saved -Destination (Join-Path $target $relative) -Force }
        }
    }
    Write-Output "Community 0.9.0b Mod 0.18.1 installed (Desktop / VR)."
    if ($existing.Count) { Write-Output "Previous files: $backup" }
} catch { Write-Error $_; exit 1 }
