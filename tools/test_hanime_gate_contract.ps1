$ErrorActionPreference = "Stop"

$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$moduleRoot = Join-Path $workspace "fd_tcode_probe\Scripts\fd_tcode"
$configPath = Join-Path $moduleRoot "config.lua"
$detectorPath = Join-Path $moduleRoot "core\hanime_detector.lua"
$resolverPath = Join-Path $moduleRoot "core\hanime_identity_resolver.lua"
$catalogPath = Join-Path $moduleRoot "core\skeleton_catalog.lua"
$registryPath = Join-Path $moduleRoot "core\hanime_component_registry.lua"
$runtimePath = Join-Path $moduleRoot "core\hanime_runtime.lua"
$localActionGatePath = Join-Path $moduleRoot "core\local_player_action_gate.lua"
$streamPath = Join-Path $moduleRoot "core\skeleton_stream.lua"
$targetFramePath = Join-Path $moduleRoot "data\target_frame_catalog.lua"

$config = Get-Content -Raw -LiteralPath $configPath
$detector = Get-Content -Raw -LiteralPath $detectorPath
$resolver = Get-Content -Raw -LiteralPath $resolverPath
$catalog = Get-Content -Raw -LiteralPath $catalogPath
$registry = Get-Content -Raw -LiteralPath $registryPath
$runtime = Get-Content -Raw -LiteralPath $runtimePath
$localActionGate = Get-Content -Raw -LiteralPath $localActionGatePath
$stream = Get-Content -Raw -LiteralPath $streamPath
$targetFrames = Get-Content -Raw -LiteralPath $targetFramePath

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
Assert-Matches $localActionGate '/Script/Paralogue\.RoomManagerBase:OnLocalPlayerActionChanged' `
    "Verified local-player action hook is missing"
Assert-Matches $localActionGate 'handler\(select\(3, \.\.\.\)\)' `
    "Local action hook must forward only the new-action enum"
Assert-NotMatches $localActionGate 'select\((1|2|4), \.\.\.\)|GetLocalPlayerId|HPerformer|Roles|IsLocallyControlled|IsLocalController|Find(All|First)Of' `
    "Local action gate must not inspect identity, ownership, role, or manager objects"
Assert-Matches $localActionGate 'new_action == ACTION_IN_H or new_action == ACTION_IN_DUMMY_H[\s\S]*?set_active\(true' `
    "Local InH/InDummyH transitions must open the action gate"
Assert-Matches $localActionGate 'new_action == ACTION_NONE[\s\S]*?set_active\(false' `
    "Local None transition must close the action gate"
Assert-Matches $detector 'function HAnimeDetector\.sample\(\)[\s\S]*?local_action_active ~= true[\s\S]*?local_player_not_in_h[\s\S]*?ensure_hot_spool_batching' `
    "Closed local-player gate must stop before any HAnime observation"
Assert-Matches $detector 'function HAnimeDetector\.set_local_action_active\(active\)[\s\S]*?if active then[\s\S]*?transition_review_requested = true[\s\S]*?else[\s\S]*?HAnimeDetector\.clear_cache\(\)' `
    "Local action entry must review queued BeginPlay components and exit must clear old bindings"
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
Assert-Matches $resolver 'assets_indicate_confirmed_session_phase\(assets\)[\s\S]*?exp_idle_touch_[\s\S]*?exp_inout_touch_[\s\S]*?exp_ing_touch_[\s\S]*?exp_idle_sex_[\s\S]*?exp_inout_sex_[\s\S]*?exp_ing_sex_' `
    "UE 5.7 playable Touch and Sex phases must be recognized as confirmed-session continuations"
Assert-Matches $detector 'HAnimeDetector\.active ~= nil[\s\S]*?assets_indicate_confirmed_session_phase\(unknown_assets\)[\s\S]*?table_hanim_exact_confirmed_session_phase' `
    "Generic Touch and Sex phases must inherit only an already confirmed TableHAnim identity"
Assert-Matches $detector 'local function identity_bindings_are_complete\(identity\)[\s\S]*?expected_catalog_roles[\s\S]*?actual\[role\]' `
    "Fallback discovery must verify every expected participant role"
Assert-Matches $detector 'finish_component_discovery_if_bound\(identity\)[\s\S]*?identity_bindings_are_complete\(identity\)' `
    "Fallback discovery must not finish on a one-sided binding"
Assert-Matches $catalog 'A_CharacterGala_' `
    "UE 5.7 Galatea Actor marker is missing"
Assert-Matches $catalog 'Ghoul\s*=\s*\{\s*"Mesh_Ghoul"\s*\}' `
    "UE 5.7 Ghoul must reject DickCap and opacity helper components"
Assert-Matches $catalog 'TchoTcho\s*=\s*\{\s*"Mesh_TchoTcho"\s*,\s*"Mesh_TchoTcho_opacity"\s*\}' `
    "UE 5.7 TchoTcho must support ordinary and hidden-model body components"
Assert-Matches $catalog 'TchoTcho\s*=\s*\{\s*"AMBP_TchoTcho_C"\s*\}' `
    "UE 5.7 TchoTcho must identify the body component currently carrying its AnimBP"
Assert-NotMatches ([regex]::Match($catalog, 'TchoTcho\s*=\s*\{\s*"Mesh_TchoTcho"\s*,\s*"Mesh_TchoTcho_opacity"\s*\}').Value) 'DickCap' `
    "UE 5.7 TchoTcho DickCap helper must never become a body candidate"
Assert-Matches $registry 'function Registry\.binding_items\(\)[\s\S]*?has_exact_montage_event[\s\S]*?preferred_anim_class[\s\S]*?actor_generation' `
    "Display-mode body selection must prefer Montage, current AnimBP, then newest actor generation"
Assert-Matches $detector 'ComponentRegistry\.binding_items\(\)' `
    "Participant completion must consume the ranked display-mode body candidates"
Assert-Matches $registry 'function Registry\.drop_role[\s\S]*?Registry\.pending = kept_pending' `
    "single-role actor replacement must purge stale pending preview components"
Assert-Matches $catalog 'find_owned_component_by_path[\s\S]*?StaticFindObject' `
    "UE 5.7 primary nonhuman meshes need a targeted path lookup before any global scan"
Assert-Matches $catalog 'local function actor_matches_entry[\s\S]*?entry\.nonhuman_direct == true[\s\S]*?monster_directory' `
    "direct BeginPlay lookup must recognize nonhuman actors by their exact static directory"
Assert-Matches $catalog 'function Catalog\.primary_components_from_actor[\s\S]*?actor_matches_entry\(actor_name, entry\)' `
    "nonhuman BeginPlay must use the same exact actor matcher as humanoid entries"
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
Assert-Matches $runtime 'function Runtime\.local_action_changed\(active\)[\s\S]*?set_local_action_active[\s\S]*?SkeletonStream\.notify_hanime_event\(\)' `
    "Local action transitions must update the detector and wake the next stream tick"
Assert-NotMatches $runtime 'local_player_action_probe|observe_character' `
    "Runtime must not retain the removed ownership probe"
Assert-Matches $detector '(?s)hot_swap_table_module\("fd_tcode\.data\.target_frame_catalog"\).*?hot_swap_table_module\("fd_tcode\.core\.hanime_motion_contract"\)' `
    "F10 must reload target contact frames before rebuilding the motion contract"
Assert-Matches $targetFrames 'schema_version\s*=\s*2' `
    "Target contact-frame protocol must identify the plane-intersection schema"
Assert-Matches $targetFrames 'local function entrance[\s\S]*?plane\([^\r\n]*"plane_intersection"\)[\s\S]*?frame\.mode\s*=\s*"plane_intersection"' `
    "Penetration entrances must explicitly opt into plane-intersection translations"
Assert-Matches $stream '"translationMode":"%s"[\s\S]*?frame\.translationMode' `
    "Skeleton packets must forward the adapter-declared target translation mode"
Assert-Matches $stream '(?s)local function reset_action_cache_if_changed\(identity\).*?previous_hanime_id ~= next_hanime_id.*?GenericHAnimeProbe\.clear_cache\(\).*?SkeletonStream\.active_hanime_id = next_hanime_id' `
    "A confirmed direct HAnime switch must reset action-scoped probe caches"
$actionReset = [regex]::Match($stream, '(?s)local function reset_action_cache_if_changed\(identity\).*?(?=local function sample_once)').Value
Assert-NotMatches $actionReset 'HAnimeDetector\.clear_cache|ComponentRegistry\.clear' `
    "A direct action switch must preserve verified participant component bindings"

Write-Output "HAnime gate contract verified: local action only; no identity probe; BeginPlay queue preserved"
