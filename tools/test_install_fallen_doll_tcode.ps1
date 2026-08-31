$ErrorActionPreference = "Stop"

$installer = Join-Path $PSScriptRoot "Install-FallenDollTCode.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("fd-tcode-installer-" + [guid]::NewGuid().ToString("N"))
$payload = Join-Path $testRoot "payload"

function New-EmptyFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    New-Item -ItemType File -Force -Path $Path | Out-Null
}

function Assert-AutoEdition {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$ExpectedEdition,
        [Parameter(Mandatory = $true)][string]$ExpectedRuntimeEdition
    )

    $gameRoot = Join-Path $testRoot $Name
    New-EmptyFile -Path (Join-Path $gameRoot $Executable)
    $result = & $installer -GameRoot $gameRoot -PayloadRoot $payload -WhatIf 6>&1 | Out-String
    if ($result -notmatch [regex]::Escape("Validated $ExpectedEdition target")) {
        throw "Auto detection failed for $Name. Output: $result"
    }
    if ($result -notmatch [regex]::Escape("Would configure local runtime edition: $ExpectedRuntimeEdition")) {
        throw "Edition-local mapping failed for $Name. Output: $result"
    }
}

try {
    New-EmptyFile -Path (Join-Path $payload "dwmapi.dll")

    Assert-AutoEdition -Name "legacy049" `
        -Executable "Paralogue\Binaries\Win64\KiritoMod049.exe" `
        -ExpectedEdition "Legacy049" `
        -ExpectedRuntimeEdition "<sidecars-refused>"
    Assert-AutoEdition -Name "playtest" `
        -Executable "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "Playtest" `
        -ExpectedRuntimeEdition "playtest-ue5"
    Assert-AutoEdition -Name "demo-desktop" `
        -Executable "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "DemoDesktop" `
        -ExpectedRuntimeEdition "demo-ue4.25"
    Assert-AutoEdition -Name "demo-vr" `
        -Executable "VR\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "DemoVR" `
        -ExpectedRuntimeEdition "demo-ue4.25"

    $priorityRoot = Join-Path $testRoot "legacy-priority"
    New-EmptyFile -Path (Join-Path $priorityRoot "Paralogue\Binaries\Win64\KiritoMod049.exe")
    New-EmptyFile -Path (Join-Path $priorityRoot "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe")
    $priorityResult = & $installer -GameRoot $priorityRoot -PayloadRoot $payload -WhatIf 6>&1 | Out-String
    if ($priorityResult -notmatch [regex]::Escape("Validated Legacy049 target")) {
        throw "Legacy 0.49 did not take precedence over the modern layout. Output: $priorityResult"
    }
    if ($priorityResult -notmatch [regex]::Escape("Would configure local runtime edition: <sidecars-refused>")) {
        throw "Legacy 0.49 must not map to Demo/Playtest static sidecars. Output: $priorityResult"
    }

    # Reproduce the player-facing README command in a fresh Windows PowerShell
    # process.  The release installer must find its sibling Game directory when
    # PayloadRoot is omitted; parameter-default evaluation previously left
    # PSScriptRoot empty in this exact invocation.
    $standalonePackage = Join-Path $testRoot "release-package"
    $standaloneInstaller = Join-Path $standalonePackage "Install-Mod.ps1"
    $standaloneGameRoot = Join-Path $testRoot "standalone-playtest"
    New-Item -ItemType Directory -Force -Path $standalonePackage | Out-Null
    Copy-Item -LiteralPath $installer -Destination $standaloneInstaller
    New-EmptyFile -Path (Join-Path $standalonePackage "Game\dwmapi.dll")
    New-EmptyFile -Path (Join-Path $standaloneGameRoot "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe")

    $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell is required for the standalone installer regression test: $windowsPowerShell"
    }
    $standaloneResult = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass `
        -File $standaloneInstaller -GameRoot $standaloneGameRoot -WhatIf 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Standalone Windows PowerShell installer failed. Output: $standaloneResult"
    }
    if ($standaloneResult -notmatch [regex]::Escape("Validated Playtest target")) {
        throw "Standalone installer did not resolve its sibling Game payload. Output: $standaloneResult"
    }

    Write-Output "Installer edition tests passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test directory outside the temporary root: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
