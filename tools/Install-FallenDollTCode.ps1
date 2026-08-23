[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,

    [ValidateSet("Auto", "Playtest", "DemoDesktop", "DemoVR")]
    [string]$Edition = "Auto",

    [string]$PayloadRoot = (Join-Path $PSScriptRoot "Game")
)

$ErrorActionPreference = "Stop"
$resolvedGameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$resolvedPayloadRoot = [System.IO.Path]::GetFullPath($PayloadRoot)

if (-not (Test-Path -LiteralPath $resolvedGameRoot -PathType Container)) {
    throw "Game root not found: $resolvedGameRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedPayloadRoot "dwmapi.dll") -PathType Leaf)) {
    throw "Mod payload not found. Expected Game/dwmapi.dll beside this installer: $resolvedPayloadRoot"
}

if ($Edition -eq "Auto") {
    if (Test-Path -LiteralPath (Join-Path $resolvedGameRoot "Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe")) {
        $Edition = "Playtest"
    } elseif (Test-Path -LiteralPath (Join-Path $resolvedGameRoot "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe")) {
        $Edition = "DemoDesktop"
    } else {
        throw "Could not recognize the Playtest or Demo layout under: $resolvedGameRoot"
    }
}

$relativeTarget = switch ($Edition) {
    "Playtest" { "Paralogue\Binaries\Win64" }
    "DemoDesktop" { "Desktop\WindowsNoEditor\Paralogue\Binaries\Win64" }
    "DemoVR" { "VR\WindowsNoEditor\Paralogue\Binaries\Win64" }
}
$target = [System.IO.Path]::GetFullPath((Join-Path $resolvedGameRoot $relativeTarget))
$expectedExecutable = Join-Path $target "Paralogue-Win64-Shipping.exe"
if (-not (Test-Path -LiteralPath $expectedExecutable -PathType Leaf)) {
    throw "Selected edition is not installed at: $target"
}

$running = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith(
        $resolvedGameRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}
if ($running) {
    $names = ($running | Select-Object -ExpandProperty Name -Unique) -join ", "
    throw "Close Operation Lovecraft: Fallen Doll before installing. Running: $names"
}

if ($PSCmdlet.ShouldProcess($target, "Install Fallen Doll TCode Mod for $Edition")) {
    Get-ChildItem -LiteralPath $resolvedPayloadRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
    }
    Write-Output "Installed $Edition support to: $target"
} else {
    Write-Output "Validated $Edition target: $target"
}
