$ErrorActionPreference = "Stop"

$moduleRoot = Join-Path $PSScriptRoot "..\fd_tcode_probe\Scripts\fd_tcode"
$app = Get-Content -Raw -LiteralPath (Join-Path $moduleRoot "app.lua")
$gate = Get-Content -Raw -LiteralPath (Join-Path $moduleRoot "core\hanime_stream_gate.lua")
$stream = Get-Content -Raw -LiteralPath (Join-Path $moduleRoot "core\skeleton_stream.lua")
$frames = Get-Content -Raw -LiteralPath (Join-Path $moduleRoot "data\target_frame_catalog.lua")

function Assert-Matches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}
function Assert-NotMatches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) { throw $Message }
}

Assert-Matches $app 'HAnimeStreamGate\.start\(\)' `
    "Demo app must arm the low-frequency HAnime gate"
Assert-NotMatches $app 'SkeletonStream\.start\(\)' `
    "Demo app must not start the 50 Hz skeleton stream at the main menu"
Assert-Matches $gate 'LoopInGameThreadWithDelay\(Config\.hanime_poll_interval_ms, review_once\)' `
    "Inactive HAnime detection must use the configured low-frequency interval"
Assert-Matches $gate 'status\.active[\s\S]*?SkeletonStream\.start\(\{[\s\S]*?stop_when_inactive\s*=\s*true' `
    "Exact HAnime activation must own the bounded high-frequency stream"
Assert-Matches $stream 'SkeletonStream\.stop_when_inactive[\s\S]*?stop_internal\("hanime-inactive", true\)' `
    "The high-frequency stream must stop after the HAnime gate releases"
Assert-Matches $stream 'local spool, spool_error = io\.open\(Config\.skeleton_spool_path, "w"\)[\s\S]*?if spool == nil then[\s\S]*?ensure_parent_directory' `
    "HAnime entry must open the existing spool before using the directory-creation fallback"
Assert-Matches $frames 'schema_version\s*=\s*2' `
    "Demo target-frame protocol must identify the plane-intersection schema"
Assert-Matches $frames 'entrance\("M_Gen", "M_Gen"\)[\s\S]*?entrance\("M_AnusInside", "M_AnusInside"\)' `
    "Demo vaginal and anal entrances must opt into stable plane intersections"
Assert-Matches $frames '"M_Spine1", "L_Thigh", "R_Thigh", "plane_intersection"' `
    "Demo entrance planes must use stable torso/thigh landmarks"
Assert-Matches $stream '"translationMode":"%s"[\s\S]*?frame\.translationMode' `
    "Demo packets must forward the target translation mode"

Write-Output "Demo HAnime stream gate verified: 4 Hz idle, 50 Hz active only"
