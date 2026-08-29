local function normalize_path(value)
    local path = tostring(value or "")
    path = string.gsub(path, "\\", "/")
    path = string.gsub(path, "/+$", "")
    return path
end

local function resolve_runtime_dir()
    local exact_dir = normalize_path(os.getenv("FD_TCODE_RUNTIME_DIR"))
    if exact_dir ~= "" then
        return exact_dir
    end

    local games_dir = normalize_path(os.getenv("F8STUDIO_GAMES_DIR"))
    if games_dir == "" then
        local user_profile = normalize_path(os.getenv("USERPROFILE"))
        if user_profile == "" then
            user_profile = "."
        end
        games_dir = user_profile .. "/.f8/studio/games"
    end
    return games_dir .. "/fallen-doll/runtime"
end

local runtime_dir = resolve_runtime_dir()

-- An installed local marker takes priority over a process environment value.
-- It is intentionally data-only and blank in the repository checkout.
local local_ok, edition_local = pcall(require, "fd_tcode.edition_local")
if not local_ok or type(edition_local) ~= "table" then
    edition_local = {}
end
local local_edition = tostring(edition_local.edition or "")
local environment_edition = tostring(os.getenv("FD_TCODE_GAME_EDITION") or "")
local game_edition = local_edition ~= "" and local_edition or environment_edition
local anim_blueprint_class_data = require("fd_tcode.data.playtest_anim_blueprint_class_data")

-- This recorder is intentionally opt-in.  It is independent from the ordinary
-- Motion Bridge stream and never changes its packet selection, device routing, or
-- motion rules.  An empty/invalid edition is a hard refusal rather than a
-- cross-build fallback.
local precision_capture_enabled = os.getenv("FD_TCODE_PRECISION_CAPTURE") == "1"
local precision_capture_edition = local_edition ~= "" and local_edition
    or tostring(os.getenv("FD_TCODE_PRECISION_EDITION") or environment_edition)
-- Static formal profile sidecars are intentionally edition-gated.  Empty or
-- invalid means they are not loaded; this prevents Demo/Playtest ID collisions.

return {
    name = "FD-TCode",
    version = "0.17.2",
    simulation_only = true,
    monitor_interval_ms = 500,
    bone_probe_names = {
        "R_Hand",
        "Penis01",
        "Penis02",
        "Penis09",
        "M_Hips",
    },
    bone_probe_max_matches = 24,
    -- The realtime path reads only the compact functional contact set per
    -- participant. The desktop bridge enables/disables candidates and chooses priority.
    -- Full-body debug skeletons are deliberately excluded from this loop.
    skeleton_sample_interval_ms = 20,
    -- Batch two realtime frames per stdio flush. This keeps bridge latency
    -- below 100 ms while avoiding a synchronous flush on every game-thread
    -- callback.
    skeleton_spool_flush_interval_frames = 2,
    -- Routine throughput logs are diagnostic only. Logging every 20 frames
    -- caused a visible hitch roughly once per second in the UE 5.7 build.
    skeleton_log_interval_frames = 500,
    -- Extra contract-declared chain bones are available for targeted
    -- calibration builds only. Normal runtime emits the minimal functional
    -- set so 50 Hz sampling remains lightweight.
    motion_debug_enabled = false,
    motion_debug_max_bones = 32,
    -- Nonhuman chains do not yet have a verified, per-skeleton rotation
    -- reference frame. Keep R0/R1/R2 centered until their geometry is
    -- calibrated; positional axes and debug sampling remain active.
    nonhuman_rotation_axes_enabled = false,
    -- HAnime/Montage discovery reads only cached primary components and does
    -- not need to run on every motion frame.
    hanime_poll_interval_ms = 250,
    -- Once a complete HAnime binding is active, the gate is transition-driven:
    -- steady 50 Hz bone sampling reuses that verified binding and never walks
    -- AnimBP, visibility, Montage or HManager state. World/character lifecycle
    -- and F10 request a bounded observation. The detector also exposes a
    -- one-shot Montage notification API for a future verified hook adapter.
    -- Development probe for the UE 5.7 HAnimManager/HSceneManager transition
    -- callbacks. It is log-only until enter/switch/idle/exit coverage is proven.
    hanime_manager_event_probe_enabled = false,
    -- Expensive one-shot API/schema probes are development-only. They must
    -- never run during ordinary participant acquisition or action switches.
    performance_diagnostics_enabled = false,
    -- Zero keeps the active HAnime bone stream unlimited. Outside HAnime only
    -- the low-frequency state watcher remains armed.
    skeleton_sample_limit = 0,
    skeleton_discovery_retry_ms = 500,
    -- HAnime identity is confirmed only from exact active Montage assets that
    -- occur in the unpacked TableHAnim import allowlist.
    -- Initial entry keeps two observations. Once an HAnime is already active,
    -- an exact TableHAnim Montage can switch identity on its first observation.
    hanime_confirm_frames = 2,
    hanime_switch_confirm_frames = 1,
    hanime_empty_hold_frames = 2,
    -- After a valid HAnime disappears, remain dormant throughout Exp_Idle.
    -- Exp_In/Exp_Sexing confirms that a new action has started and permits one
    -- non-periodic component rediscovery; the lightweight stream stays armed.
    hanime_reentry_confirm_frames = 2,
    -- Exact AnimBlueprintGeneratedClass names from the unpacked UE 5.7
    -- Playtest assets. Several playable characters reuse their ordinary AMBP
    -- for HAnime, while Alet/Hound/Anya use HAnim-specific spellings.
    hanime_anim_blueprint_classes = anim_blueprint_class_data.by_class,
    -- Legacy manual Hand/profile probes reject pairs farther than one metre.
    -- The automatic functional contact stream does not perform proximity-based target
    -- guessing.
    hand_pair_max_distance_cm = 100,
    skeleton_spool_path = runtime_dir .. "/fd-skeleton.ndjson",
    precision_capture_enabled = precision_capture_enabled,
    precision_capture_edition = precision_capture_edition,
    game_edition = game_edition,
    edition_local_source = tostring(edition_local.source or "<unknown>"),
    precision_capture_interval_ms = 100,
    precision_capture_spool_path = runtime_dir .. "/fd-precision-capture.ndjson",

    -- F7 is reserved for a future external preview launcher and is
    -- intentionally not registered by Lua. Participant selection is handled
    -- in MotionBridge from the live skeleton stream.
    keys = {
        toggle_runtime = Key.F6,
    },

    manager_classes = {
        "HManager_C",
        "HManager",
        "HSceneManager_C",
        "HSceneManager",
        "HAnimManager_C",
        "HAnimManager",
        "HStateManager_C",
        "HStateManager",
        "HSceneContorller_C",
        "HSceneMode_C",
    },

    manager_properties = {
        "CurrentState",
        "CurrentCustomIndex",
    },

    manager_object_properties = {
        "AnimManager",
        "StateManager",
        "CharacterGroupManager",
        "UIManager",
        "SceneManager",
        "HSceneManager",
        "HAnimManager",
        "DefaultAlet",
        "MainCharacter",
        "Female",
        "TargetCharacter",
        "ThirdCharacter",
        "SecondCharacter",
        "FourthCharacter",
        "PartnerCharacter",
        "CharacterA",
        "CharacterB",
        "CharacterC",
        "FemaleA",
        "FemaleB",
        "Male",
        "MaleA",
        "MaleB",
    },

    animation_properties = {
        "AnimID",
        "AnimName",
        "AnimationID",
        "AnimationName",
        "CurrentAnimID",
        "CurrentAnimName",
        "CurrentAnimation",
        "CurrentMontage",
        "CurrentSection",
        "AnimSpeed",
        "CurrAnimState",
        "AnimState",
        "CurrentState",
        "AutoSpeedChange",
        "AutoSpeedCoolDown",
        "AutoSpeedTraget",
    },
}
