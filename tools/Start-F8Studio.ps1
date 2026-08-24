[CmdletBinding()]
param(
    [string]$F8StudioRoot = "",
    [ValidateSet("v16", "v17")]
    [string]$ProjectVersion = "v17",
    [switch]$Foreground
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($F8StudioRoot)) {
    # `$PSScriptRoot` is not reliably populated while Windows PowerShell is
    # evaluating parameter default expressions. Resolve the default here,
    # after script invocation has established the script directory.
    $F8StudioRoot = Join-Path $PSScriptRoot "..\.deps\f8studio-pr"
}
$root = [System.IO.Path]::GetFullPath($F8StudioRoot)
$python = Join-Path $root ".pixi\envs\default\python.exe"
$pythonw = Join-Path $root ".pixi\envs\default\pythonw.exe"
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
$launchLogDirectory = Join-Path $env:LOCALAPPDATA "FallenDollTCode\logs"
$stdoutLog = Join-Path $launchLogDirectory "f8studio.stdout.log"
$stderrLog = Join-Path $launchLogDirectory "f8studio.stderr.log"
$projectFileName = if ($ProjectVersion -eq "v17") {
    "fallen-doll-skeleton-preview-v17.json"
} else {
    "fallen-doll-skeleton-preview-v16.json"
}
$projectName = if ($ProjectVersion -eq "v17") {
    "Fallen Doll Skeleton Preview v17 (real-time multi-axis)"
} else {
    "Fallen Doll Skeleton Preview v16 (direct L0)"
}
$projectDescription = if ($ProjectVersion -eq "v17") {
    "Operation Lovecraft: Fallen Doll real-time multi-axis TCode project"
} else {
    "Operation Lovecraft: Fallen Doll real-time L0 project"
}
$projectTags = if ($ProjectVersion -eq "v17") {
    @("fallen-doll", "tcode", "six-axis", "release")
} else {
    @("fallen-doll", "tcode", "l0")
}
$projectFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\f8studio\$projectFileName"))
$projectSelector = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "Prepare-F8StudioProject.py"))
# This launcher is for Fallen Doll only.  Avoid probing unrelated audio, AI, video,
# and capture services (some require optional Pixi environments) during Studio startup.
$env:F8_DISABLED_SERVICE_CLASSES = @(
    "f8.audiocap", "f8.audiofeat.core", "f8.audiofeat.rhythm",
    "f8.cppengine", "f8.cvkit.denseoptflow", "f8.cvkit.flowmetric",
    "f8.cvkit.templatematch", "f8.cvkit.tracking", "f8.cvkit.videostab",
    "f8.dl.classifier", "f8.dl.detector", "f8.dl.detsorter", "f8.dl.humandetector",
    "f8.dl.optflow", "f8.dl.tcnwave", "f8.implayer", "f8.mp.pose",
    "f8.proclauncher", "f8.pyexpr", "f8.pyscript", "f8.screencap"
) -join ","
Set-Location -LiteralPath $root
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Fallen Doll F8Studio project file not found: $projectFile"
}
$selectorArguments = @($projectSelector, $projectFile, "--name", $projectName, "--description", $projectDescription)
foreach ($tag in $projectTags) {
    $selectorArguments += @("--tag", $tag)
}
& $python @selectorArguments
if ($LASTEXITCODE -ne 0) {
    throw "Could not prepare the Fallen Doll F8Studio project."
}
$arguments = @("-m", "f8pystudio.main", "--automation", "--automation-port-file", $connectionFile)

if ($Foreground) {
    & $python @arguments
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Path $launchLogDirectory -Force | Out-Null
$hostExecutable = if (Test-Path -LiteralPath $pythonw -PathType Leaf) { $pythonw } else { $python }
$process = Start-Process -FilePath $hostExecutable -ArgumentList $arguments -WorkingDirectory $root -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
Write-Output "F8Studio started in the background (PID $($process.Id)). Logs: $launchLogDirectory"
