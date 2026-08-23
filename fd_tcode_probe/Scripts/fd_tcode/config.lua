return {
    name = "FD-TCode",
    version = "0.14.0-functional-contact-selection",
    simulation_only = true,
    monitor_interval_ms = 500,
    bone_probe_names = {
        "R_Hand",
        "Penis01",
        "Penis02",
    },
    bone_probe_max_matches = 24,
    -- The realtime path reads only the compact functional contact set per
    -- participant. F8Studio enables/disables candidates and chooses priority.
    -- Full-body debug skeletons are deliberately excluded from this loop.
    skeleton_sample_interval_ms = 50,
    -- HAnime/Montage discovery is much more expensive than sampling the two
    -- selected contact bones and does not need to run on every motion frame.
    hanime_poll_interval_ms = 250,
    -- Zero means the F9 stream runs until it is explicitly stopped.
    skeleton_sample_limit = 0,
    skeleton_discovery_retry_ms = 500,
    -- HAnime identity is confirmed only from exact active Montage assets that
    -- occur in the unpacked TableHAnim import allowlist.
    hanime_discovery_retry_ms = 500,
    hanime_scene_refresh_ms = 250,
    hanime_confirm_frames = 3,
    hanime_empty_hold_frames = 2,
    -- Legacy manual Hand/profile probes reject pairs farther than one metre.
    -- The F9 functional contact stream does not perform proximity-based target
    -- guessing.
    hand_pair_max_distance_cm = 100,
    skeleton_spool_path = "D:/zhifu/Desktop/code/tcode plugin FD/runtime/fd-skeleton.ndjson",
    pose_catalog_path = "D:/zhifu/Desktop/code/tcode plugin FD/runtime/fd-visible-poses.tsv",

    -- F7 is reserved for a future external F8Studio preview launcher and is
    -- intentionally not registered by Lua. F8 performs a one-shot, read-only
    -- export of the current runtime-filtered pose list.
    keys = {
        toggle_runtime = Key.F6,
        export_pose_catalog = Key.F8,
        skeleton_stream = Key.F9,
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
