$ErrorActionPreference = "Stop"

$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$moduleRoot = Join-Path $workspace "fd_tcode_probe\Scripts\fd_tcode"
$configPath = Join-Path $moduleRoot "config.lua"
$detectorPath = Join-Path $moduleRoot "core\hanime_detector.lua"
$resolverPath = Join-Path $moduleRoot "core\hanime_identity_resolver.lua"
$catalogPath = Join-Path $moduleRoot "core\skeleton_catalog.lua"
$runtimePath = Join-Path $moduleRoot "core\hanime_runtime.lua"

$config = Get-Content -Raw -LiteralPath $configPath
$detector = Get-Content -Raw -LiteralPath $detectorPath
$resolver = Get-Content -Raw -LiteralPath $resolverPath
$catalog = Get-Content -Raw -LiteralPath $catalogPath
$runtime = Get-Content -Raw -LiteralPath $runtimePath

function Assert-Matches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -match $Pattern) {
        throw $Message
    }
}

# Active steady state must not contain a configurable periodic path. This is a
# source-contract test because UE4SS supplies the Lua runtime inside the game.
Assert-NotMatches $config 'hanime_active_periodic_review_enabled' `
    "Periodic active gate review must not be configurable"
Assert-NotMatches $detector 'active_cached_polls|hanime_active_full_poll_stride|hanime_active_periodic_review_enabled' `
    "Periodic active gate review state returned to hanime_detector.lua"
Assert-Matches $config 'hanime_switch_confirm_frames\s*=\s*1' `
    "Exact action switches must not wait for repeated gate polls"
Assert-Matches $detector 'local exact_observation = string\.find\(recognition_source, "exact"[\s\S]*?local required_confirm_frames = exact_observation' `
    "An exact TableHAnim start must use the one-frame exact confirmation path"
Assert-Matches $resolver 'assets_indicate_active_hanime\(assets\)[\s\S]*?exp_touch_in_' `
    "EXP_TOUCH_IN must preserve an already exact HAnime identity"
Assert-Matches $resolver 'assets_indicate_active_hanime\(assets\)[\s\S]*?exp_suffocate_[\s\S]*?exp_ahegao_' `
    "Ada active facial expressions must preserve an already exact HAnime identity"
Assert-NotMatches ([regex]::Match($resolver, '(?s)function Resolver\.assets_indicate_reentry\(assets\).*?end\s*function Resolver\.assets_indicate_active_hanime').Value) 'exp_suffocate_|exp_ahegao_' `
    "Ada facial expressions must not start HAnime without an exact TableHAnim observation"
Assert-Matches $detector 'local function identity_bindings_are_complete\(identity\)[\s\S]*?expected_catalog_roles[\s\S]*?actual\[role\]' `
    "Fallback discovery must verify every expected participant role"
Assert-Matches $detector 'finish_component_discovery_if_bound\(identity\)[\s\S]*?identity_bindings_are_complete\(identity\)' `
    "Fallback discovery must not finish on a one-sided binding"
Assert-Matches $catalog 'A_CharacterGala_' `
    "UE 5.7 Galatea Actor marker is missing"
Assert-Matches $catalog 'Ghoul\s*=\s*\{\s*"Mesh_Ghoul"\s*\}' `
    "UE 5.7 Ghoul must reject DickCap and opacity helper components"
Assert-Matches $catalog 'find_owned_component_by_path[\s\S]*?StaticFindObject' `
    "UE 5.7 primary nonhuman meshes need a targeted path lookup before any global scan"
Assert-Matches $detector 'table_hanim_exact_active_expression_refresh' `
    "An active expression transition must rebuild bindings after UE 5.7 replaces participant Actors"
Assert-Matches $detector 'expected_count == 1[\s\S]*?ComponentRegistry\.drop_role\(actor_role\)' `
    "A single-role participant Actor replacement must evict stale zero-transform bindings"
Assert-Matches $detector 'ComponentRegistry\.contains\(component\)' `
    "An evicted UObject must not remain a registered active binding merely because IsValid stays true"

$samplePattern = '(?s)function HAnimeDetector\.sample\(\)(.*?)function HAnimeDetector\.clear_cache\(\)'
$sampleMatch = [regex]::Match($detector, $samplePattern)
if (-not $sampleMatch.Success) {
    throw "Could not isolate HAnimeDetector.sample()"
}
$sample = $sampleMatch.Groups[1].Value
Assert-Matches $sample 'identity_components_are_registered\(HAnimeDetector\.active\)' `
    "Active fast path must validate every participant binding"
Assert-Matches $sample 'transition_review_requested ~= true[\s\S]*?return status\("active"' `
    "Active steady state must return without a full observation"
Assert-Matches $sample 'component_discovery_pending ~= true[\s\S]*?return status\("active"' `
    "A bounded component discovery must finish before the active fast path resumes"
Assert-Matches $sample 'transition_review_requested = false[\s\S]*?local observed, observation = observe\(\)' `
    "A transition request must be consumed before its one full observation"

Assert-Matches $detector '(?s)function HAnimeDetector\.clear_cache\(\).*?transition_review_requested = false' `
    "Cache clear must discard stale transition requests"
foreach ($api in @(
    'request_component_discovery',
    'queue_component',
    'queue_actor_components',
    'observe_montage_play',
    'observe_montage_stop'
)) {
    $nextFunction = '(?=\r?\nfunction HAnimeDetector\.|\r?\nreturn HAnimeDetector)'
    $functionPattern = '(?s)function HAnimeDetector\.' + [regex]::Escape($api) + '\(.*?' + $nextFunction
    $functionMatch = [regex]::Match($detector, $functionPattern)
    if (-not $functionMatch.Success) {
        throw "Could not isolate HAnimeDetector.$api()"
    }
    Assert-Matches $functionMatch.Value 'transition_review_requested = true' `
        "HAnimeDetector.$api() must request one transition review"
}

Assert-Matches $runtime 'RegisterBeginPlayPostHook' `
    "Character BeginPlay transition signal is missing"
Assert-Matches $runtime 'Runtime\.detector\.queue_actor_components\(actor\)' `
    "Character BeginPlay must queue every directly owned primary component"
Assert-Matches $runtime '(?s)local queued = Runtime\.detector\.queue_actor_components\(actor\).*?local fallback_discovery = tonumber\(queued or 0\) <= 0.*?if fallback_discovery then\s*Runtime\.detector\.request_component_discovery' `
    "Character BeginPlay must use class discovery only when direct primary-component acquisition fails"
Assert-Matches $detector '(?s)function HAnimeDetector\.request_component_discovery\(class_names\).*?actor_scoped_request.*?direct_actor_queue_succeeded == true.*?return false' `
    "Detector hot reload must reject redundant actor-scoped discovery after a successful direct queue"
Assert-Matches $detector '(?s)function HAnimeDetector\.queue_actor_components\(actor\).*?direct_actor_queue_succeeded = #items > 0' `
    "Direct Actor acquisition must report whether its primary component was queued"
Assert-Matches $detector '(?s)local function finish_component_discovery_if_bound\(identity\).*?identity_bindings_are_complete\(identity\).*?component_discovery_pending = false.*?component_discovery_attempts = 0' `
    "A complete participant binding must cancel unused component-discovery retries"
Assert-Matches $sample 'finish_component_discovery_if_bound\(observed\)' `
    "Every successful HAnime observation must retire stale discovery work"
Assert-Matches $runtime 'Runtime\.detector\.clear_cache\(\)' `
    "World changes must invalidate active participant bindings"

Write-Output "HAnime gate contract verified: no periodic active review; direct BeginPlay binding avoids redundant discovery"
