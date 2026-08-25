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
        [Parameter(Mandatory = $true)][string]$ExpectedEdition
    )

    $gameRoot = Join-Path $testRoot $Name
    New-EmptyFile -Path (Join-Path $gameRoot $Executable)
    $result = & $installer -GameRoot $gameRoot -PayloadRoot $payload -WhatIf 6>&1 | Out-String
    if ($result -notmatch [regex]::Escape("Validated $ExpectedEdition target")) {
        throw "Auto detection failed for $Name. Output: $result"
    }
}

try {
    New-EmptyFile -Path (Join-Path $payload "dwmapi.dll")

    Assert-AutoEdition -Name "legacy049" `
        -Executable "Paralogue\Binaries\Win64\KiritoMod049.exe" `
        -ExpectedEdition "Legacy049"
    Assert-AutoEdition -Name "playtest" `
        -Executable "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "Playtest"
    Assert-AutoEdition -Name "demo-desktop" `
        -Executable "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "DemoDesktop"
    Assert-AutoEdition -Name "demo-vr" `
        -Executable "VR\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe" `
        -ExpectedEdition "DemoVR"

    $priorityRoot = Join-Path $testRoot "legacy-priority"
    New-EmptyFile -Path (Join-Path $priorityRoot "Paralogue\Binaries\Win64\KiritoMod049.exe")
    New-EmptyFile -Path (Join-Path $priorityRoot "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe")
    $priorityResult = & $installer -GameRoot $priorityRoot -PayloadRoot $payload -WhatIf 6>&1 | Out-String
    if ($priorityResult -notmatch [regex]::Escape("Validated Legacy049 target")) {
        throw "Legacy 0.49 did not take precedence over the modern layout. Output: $priorityResult"
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
