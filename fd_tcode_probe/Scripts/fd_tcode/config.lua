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

return {
    name = "FD-TCode",
    version = "0.17.0-dev",
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
    -- participant. F8Studio enables/disables candidates and chooses priority.
    -- Full-body debug skeletons are deliberately excluded from this loop.
    skeleton_sample_interval_ms = 50,
    -- HAnime/Montage discovery reads only cached primary components and does
    -- not need to run on every motion frame.
    hanime_poll_interval_ms = 250,
    -- Zero keeps the automatic HAnime-gated stream armed for the Mod lifetime.
    skeleton_sample_limit = 0,
    skeleton_discovery_retry_ms = 500,
    -- HAnime identity is confirmed only from exact active Montage assets that
    -- occur in the unpacked TableHAnim import allowlist.
    hanime_confirm_frames = 3,
    hanime_empty_hold_frames = 2,
    -- After a valid HAnime disappears, remain dormant throughout Exp_Idle.
    -- Exp_In/Exp_Sexing confirms that a new action has started and permits one
    -- non-periodic component rediscovery; the lightweight stream stays armed.
    hanime_reentry_confirm_frames = 2,
    -- Legacy manual Hand/profile probes reject pairs farther than one metre.
    -- The automatic functional contact stream does not perform proximity-based target
    -- guessing.
    hand_pair_max_distance_cm = 100,
    skeleton_spool_path = runtime_dir .. "/fd-skeleton.ndjson",
    pose_catalog_path = runtime_dir .. "/fd-visible-poses.tsv",

    -- F7 is reserved for a future external F8Studio preview launcher and is
    -- intentionally not registered by Lua. F8 performs a one-shot, read-only
    -- export of the current runtime-filtered pose list.
    keys = {
        toggle_runtime = Key.F6,
        export_pose_catalog = Key.F8,
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
        "AnimState",
        "CurrentState",
        "AutoSpeedChange",
        "AutoSpeedCoolDown",
        "AutoSpeedTraget",
    },
}
