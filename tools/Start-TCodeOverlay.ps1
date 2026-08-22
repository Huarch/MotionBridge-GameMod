param(
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..\overlay\FallenDollTCodeOverlay.csproj')
)

$project = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $project)) {
    throw "找不到覆盖层项目：$project"
}

Start-Process dotnet -ArgumentList @('run', '--project', $project, '--configuration', 'Release', '--no-build')
