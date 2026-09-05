[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$GameRoot = "",

    [ValidateSet("Auto", "Playtest", "Legacy049", "DemoDesktop", "DemoVR")]
    [string]$Edition = "Auto",

    [string]$PayloadRoot = "",

    [switch]$Interactive,

    # Test/development hook. Release users do not need this parameter.
    [string[]]$SearchRoots = @()
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot) -and $MyInvocation.MyCommand.Path) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ($Interactive -and -not [string]::IsNullOrWhiteSpace($scriptRoot)) {
    try {
        Start-Transcript -Path (Join-Path $scriptRoot "Install-Mod.log") -Force | Out-Null
    } catch {
        Write-Warning "Could not create Install-Mod.log: $($_.Exception.Message)"
    }
}
if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        throw "Could not locate the installer folder. Run Install-Mod.ps1 as a script file instead of pasting its contents into PowerShell ISE."
    }
    $PayloadRoot = Join-Path $scriptRoot "Game"
}
$resolvedPayloadRoot = [System.IO.Path]::GetFullPath($PayloadRoot)

function Test-GameLayout {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RequestedEdition
    )

    $checks = [ordered]@{
        Legacy049 = "Paralogue\Binaries\Win64\KiritoMod049.exe"
        Playtest = "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe"
        DemoDesktop = "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe"
        DemoVR = "VR\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe"
    }
    foreach ($item in $checks.GetEnumerator()) {
        if ($RequestedEdition -ne "Auto" -and $RequestedEdition -ne $item.Key) {
            continue
        }
        if (Test-Path -LiteralPath (Join-Path $Root $item.Value) -PathType Leaf) {
            return $item.Key
        }
    }
    return $null
}

function Get-SteamLibraryRoots {
    $libraries = [System.Collections.Generic.List[string]]::new()
    $steamPaths = @(
        (Get-ItemPropertyValue -LiteralPath "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue),
        (Get-ItemPropertyValue -LiteralPath "HKLM:\Software\WOW6432Node\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue),
        (Get-ItemPropertyValue -LiteralPath "HKLM:\Software\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($steamPath in $steamPaths) {
        $libraries.Add([System.IO.Path]::GetFullPath($steamPath))
        $libraryFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }
        foreach ($line in Get-Content -LiteralPath $libraryFile -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*"path"\s*"([^"]+)"') {
                $libraries.Add([System.IO.Path]::GetFullPath(($Matches[1] -replace '\\\\', '\')))
            }
        }
    }
    return @($libraries | Select-Object -Unique)
}

function Find-GameInstalls {
    param([Parameter(Mandatory = $true)][string]$RequestedEdition)

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $SearchRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $roots.Add([System.IO.Path]::GetFullPath($root))
        }
    }
    if ($SearchRoots.Count -eq 0) {
        foreach ($library in Get-SteamLibraryRoots) {
            $common = Join-Path $library "steamapps\common"
            if (-not (Test-Path -LiteralPath $common -PathType Container)) {
                continue
            }
            foreach ($directory in Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue) {
                $roots.Add($directory.FullName)
            }
        }
    }

    $results = @()
    foreach ($root in $roots | Select-Object -Unique) {
        $detectedEdition = Test-GameLayout -Root $root -RequestedEdition $RequestedEdition
        if ($detectedEdition) {
            $results += [pscustomobject]@{ Root = $root; Edition = $detectedEdition }
        }
    }
    return @($results)
}

function Select-GameRoot {
    param([Parameter(Mandatory = $true)][string]$RequestedEdition)

    $installs = @(Find-GameInstalls -RequestedEdition $RequestedEdition)
    if ($installs.Count -eq 1) {
        # Keep status text out of the success pipeline.  This function's only
        # return value must be the selected path, otherwise assigning its
        # output to $GameRoot produces an Object[] and GetFullPath() fails.
        Write-Host "Detected $($installs[0].Edition): $($installs[0].Root)"
        return $installs[0].Root
    }
    if ($installs.Count -gt 1) {
        Write-Host "Multiple compatible installations were found:"
        for ($index = 0; $index -lt $installs.Count; ++$index) {
            Write-Host "  $($index + 1). [$($installs[$index].Edition)] $($installs[$index].Root)"
        }
        $selection = Read-Host "Choose a number"
        $selectedIndex = 0
        if ([int]::TryParse($selection, [ref]$selectedIndex) -and $selectedIndex -ge 1 -and $selectedIndex -le $installs.Count) {
            return $installs[$selectedIndex - 1].Root
        }
        throw "No valid installation was selected."
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = "Select the Fallen Doll top-level game folder"
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } catch {
        Write-Warning "Folder picker unavailable: $($_.Exception.Message)"
    }
    throw "No compatible Steam installation was detected and no folder was selected."
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Select-GameRoot -RequestedEdition $Edition
} elseif (Test-Path -LiteralPath $GameRoot -PathType Leaf) {
    $GameRoot = Split-Path -Parent $GameRoot
}
$resolvedGameRoot = [System.IO.Path]::GetFullPath($GameRoot)

if (-not (Test-Path -LiteralPath $resolvedGameRoot -PathType Container)) {
    throw "Game root not found: $resolvedGameRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedPayloadRoot "dwmapi.dll") -PathType Leaf)) {
    throw "Mod payload not found. Expected Game/dwmapi.dll beside this installer: $resolvedPayloadRoot"
}

if ($Edition -eq "Auto") {
    $Edition = Test-GameLayout -Root $resolvedGameRoot -RequestedEdition "Auto"
    if (-not $Edition) {
        throw "Could not recognize a Playtest, legacy 0.49, or Demo layout under: $resolvedGameRoot"
    }
} elseif (-not (Test-GameLayout -Root $resolvedGameRoot -RequestedEdition $Edition)) {
    throw "The selected folder is not a compatible $Edition installation: $resolvedGameRoot"
}

$relativeTarget = switch ($Edition) {
    "Playtest" { "Paralogue\Binaries\Win64" }
    "Legacy049" { "Paralogue\Binaries\Win64" }
    "DemoDesktop" { "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64" }
    "DemoVR" { "VR\WindowsNoEditor\Paralogue\Binaries\Win64" }
}
$target = [System.IO.Path]::GetFullPath((Join-Path $resolvedGameRoot $relativeTarget))
$expectedExecutableName = if ($Edition -eq "Legacy049") {
    "KiritoMod049.exe"
} else {
    "Paralogue-Win64-Shipping.exe"
}
$expectedExecutable = Join-Path $target $expectedExecutableName
if (-not (Test-Path -LiteralPath $expectedExecutable -PathType Leaf)) {
    throw "Selected edition is not installed at: $target"
}

$running = Get-Process -Name @(
    "FallenDollLauncher",
    "Paralogue-Win64-Shipping",
    "KiritoMod049"
) -ErrorAction SilentlyContinue | Where-Object {
    try {
        $_.Path -and $_.Path.StartsWith(
            $resolvedGameRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        $false
    }
}
if ($running) {
    $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ", "
    throw "Close Operation Lovecraft: Fallen Doll before installing. Running: $names"
}

if ($Interactive) {
    Write-Host ""
    Write-Host "Detected edition: $Edition"
    Write-Host "Install destination: $target"
    $confirmation = Read-Host "Install now? Type Y to continue"
    if ($confirmation -notmatch '^(?i:y|yes)$') {
        throw "Installation canceled by the user."
    }
}

$runtimeEdition = switch ($Edition) {
    "Playtest" { "playtest-ue5" }
    "DemoDesktop" { "demo-ue4.25" }
    "DemoVR" { "demo-ue4.25" }
    # Legacy 0.49 is neither the UE4.25 Demo export set nor the UE5
    # Playtest.  Keep static sidecars refused until it receives its own proof.
    "Legacy049" { "" }
}
$editionSource = if ([string]::IsNullOrWhiteSpace($runtimeEdition)) {
    "installer:Legacy049-sidecars-refused"
} else {
    "installer:$Edition"
}
$editionLocalRelative = "ue4ss\Mods\fd_tcode_probe\Scripts\fd_tcode\edition_local.lua"
$editionLocalPath = Join-Path $target $editionLocalRelative
$editionLocalText = @"
-- Generated by Install-FallenDollTCode.ps1 for the validated target. Do not copy across editions.
return {
    schema_version = 1,
    edition = "$runtimeEdition",
    source = "$editionSource",
}
"@

function Test-RuntimeWriteAccess {
    $runtimeRoot = $env:FD_TCODE_RUNTIME_DIR
    if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
        $gamesRoot = $env:F8STUDIO_GAMES_DIR
        if ([string]::IsNullOrWhiteSpace($gamesRoot)) {
            if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
                throw "USERPROFILE is unavailable; the Mod runtime directory cannot be resolved."
            }
            $gamesRoot = Join-Path $env:USERPROFILE ".f8\studio\games"
        }
        $runtimeRoot = Join-Path $gamesRoot "fallen-doll\runtime"
    }
    $runtimeRoot = [System.IO.Path]::GetFullPath($runtimeRoot)
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    $probe = Join-Path $runtimeRoot (".motionbridge-write-test-" + [guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($probe, "ok", [System.Text.UTF8Encoding]::new($false))
    } finally {
        if (Test-Path -LiteralPath $probe -PathType Leaf) {
            Remove-Item -LiteralPath $probe -Force
        }
    }
    return $runtimeRoot
}

if ($PSCmdlet.ShouldProcess($target, "Install Fallen Doll TCode Mod for $Edition")) {
    $runtimeRoot = Test-RuntimeWriteAccess
    Get-ChildItem -LiteralPath $resolvedPayloadRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $editionLocalPath) -PathType Container)) {
        throw "Installed payload is missing the Mod edition-local directory: $editionLocalPath"
    }
    [System.IO.File]::WriteAllText($editionLocalPath, $editionLocalText, [System.Text.UTF8Encoding]::new($false))
    $requiredInstalledFiles = @(
        (Join-Path $target "dwmapi.dll"),
        (Join-Path $target "ue4ss\UE4SS.dll"),
        (Join-Path $target "ue4ss\Mods\fd_tcode_probe\Scripts\main.lua")
    )
    foreach ($requiredFile in $requiredInstalledFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Installation verification failed; missing: $requiredFile"
        }
    }
    Write-Output "Installed $Edition support to: $target"
    Write-Output "Configured local runtime edition: $(if ($runtimeEdition) { $runtimeEdition } else { '<sidecars-refused>' })"
    Write-Output "Runtime write test passed: $runtimeRoot"
    Write-Output "Installation verified successfully."
} else {
    Write-Output "Validated $Edition target: $target"
    Write-Output "Would configure local runtime edition: $(if ($runtimeEdition) { $runtimeEdition } else { '<sidecars-refused>' })"
}
