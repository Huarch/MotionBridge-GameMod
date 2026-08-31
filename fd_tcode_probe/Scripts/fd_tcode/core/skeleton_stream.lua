local Config = require("fd_tcode.config")
local GenericHAnimeProbe = require("fd_tcode.core.generic_hanime_probe")
local HAnimeDetector = require("fd_tcode.core.hanime_detector")
local Log = require("fd_tcode.core.log")

local SkeletonStream = {
    running = false,
    loop_handle = nil,
    sequence = 0,
    sample_count = 0,
    attempt_count = 0,
    timestamp_base_ms = 0,
    spool = nil,
    last_hanime_state_key = nil,
    was_hanime_active = false,
    active_hanime_id = nil,
    cached_hanime = nil,
    samples_until_hanime_poll = 0,
    samples_until_spool_retry = 0,
    spool_retry_count = 0,
    samples_since_flush = 0,
    generation = 0,
    flush_interval_supported = true,
}

local exporter_version = "fd-tcode-lua-" .. tostring(Config.version)

local function json_escape(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return text
end

local function string_array_json(values)
    local entries = {}
    for _, value in ipairs(values or {}) do
        table.insert(entries, '"' .. json_escape(value) .. '"')
    end
    return "[" .. table.concat(entries, ",") .. "]"
end

local function bone_json(name, bone)
    local p = bone.position
    local q = bone.rotation
    return string.format(
        '{"name":"%s","pos":[%.6f,%.6f,%.6f],"rot":[%.7f,%.7f,%.7f,%.7f]}',
        json_escape(name),
        p[1] * 0.01,
        p[2] * 0.01,
        p[3] * 0.01,
        q[4],
        q[1],
        q[2],
        q[3]
    )
end

local function target_frames_json(frames)
    local entries = {}
    for _, frame in ipairs(frames or {}) do
        table.insert(entries, string.format(
            '{"mode":"%s","translationMode":"%s","sourceBone":"%s","originBone":"%s","forwardBone":"%s","leftBone":"%s","rightBone":"%s"}',
            json_escape(frame.mode), json_escape(frame.translationMode),
            json_escape(frame.sourceBone), json_escape(frame.originBone),
            json_escape(frame.forwardBone), json_escape(frame.leftBone), json_escape(frame.rightBone)
        ))
    end
    return "[" .. table.concat(entries, ",") .. "]"
end

local function contact_pairs_json(values)
    local entries = {}
    for _, pair in ipairs(values or {}) do
        local reference = pair.reference or {}
        local target = pair.target or {}
        table.insert(entries, string.format(
            '{"id":"%s","reference":{"participantSlot":"%s"},"target":{"participantTag":"%s","catalogId":"%s","semantic":"%s","bone":"%s"}}',
            json_escape(pair.id),
            json_escape(reference.participantSlot),
            json_escape(target.participantTag),
            json_escape(target.catalogId),
            json_escape(target.semantic),
            json_escape(target.bone)
        ))
    end
    return "[" .. table.concat(entries, ",") .. "]"
end

local function direct_geometry_json(geometry)
    if type(geometry) ~= "table" then
        return "null"
    end
    local basis = geometry.targetBasis or {}
    local fallback = geometry.axisFallback
    local plane = geometry.referencePlane or {}
    local fallback_json = "null"
    if type(fallback) == "table" then
        fallback_json = string.format(
            '{"mode":"%s","lengthCm":%.9f,"evidence":"%s"}',
            json_escape(fallback.mode),
            tonumber(fallback.lengthCm or 0.0),
            json_escape(fallback.evidence)
        )
    end
    return string.format(
        '{"source":"%s","deviceOutput":"%s","referenceOriginBone":"%s","referenceDirectionBone":"%s","referenceTipBone":"%s","referenceSupportBone":"%s","referencePlane":{"mode":"%s","centerBone":"%s","forwardBone":"%s","leftBone":"%s","rightBone":"%s"},"l0Normalization":"%s","l0MinMeters":%.6f,"l0MaxMeters":%.6f,"l0Inverted":%s,"targetSemantic":"%s","targetBasis":{"up":"%s","right":"%s"},"outputAxes":%s,"axisFallback":%s}',
        json_escape(geometry.source),
        json_escape(geometry.deviceOutput),
        json_escape(geometry.referenceOriginBone),
        json_escape(geometry.referenceDirectionBone),
        json_escape(geometry.referenceTipBone),
        json_escape(geometry.referenceSupportBone),
        json_escape(plane.mode),
        json_escape(plane.centerBone),
        json_escape(plane.forwardBone),
        json_escape(plane.leftBone),
        json_escape(plane.rightBone),
        json_escape(geometry.l0Normalization),
        tonumber(geometry.l0MinMeters or 0.0),
        tonumber(geometry.l0MaxMeters or 0.0),
        geometry.l0Inverted == true and "true" or "false",
        json_escape(geometry.targetSemantic),
        json_escape(basis.up),
        json_escape(basis.right),
        string_array_json(geometry.outputAxes),
        fallback_json
    )
end

local function trailer_json(participant, sample)
    local identity = sample.hanime_identity or {}
    return string.format(
        '{"profileId":"fallen-doll","poseId":"%s","poseStatus":"%s","hanimeActive":true,"hanimeId":"%s","hanimeAsset":"%s","hanimeCategory":"%s","hanimePhase":"%s","hanimeState":"%s","recognitionSource":"%s","bindingGeneration":%d,"role":"%s","roleIndex":%d,"characterRole":"%s","catalogId":"%s","participantTag":"%s","participantSlot":"%s","participantPriority":%d,"component":"%s","componentMatchMethod":"%s","preferredBones":%s,"contactBones":%s,"contactPairs":%s,"targetFrames":%s,"motionContractKind":"%s","motionContractSource":"%s","directGeometry":%s,"streamMode":"functional-contact-bones","exporterVersion":"%s"}',
        json_escape(sample.matched_pose or ""),
        json_escape(sample.matched_pose_status or "unmapped"),
        json_escape(identity.hanime_id or ""),
        json_escape(identity.asset or ""),
        json_escape(identity.category or "other"),
        json_escape(identity.phase or "normal"),
        json_escape(sample.hanime_state or "active"),
        json_escape(identity.recognition_source or ""),
        tonumber(sample.binding_generation or 0),
        json_escape(participant.role),
        tonumber(participant.role_index or 0),
        json_escape(participant.catalog_role),
        json_escape(participant.catalog),
        json_escape(participant.participant_tag),
        json_escape(participant.participant_slot),
        tonumber(participant.participant_priority or 0),
        json_escape(participant.component_name),
        json_escape(participant.component_match_method),
        string_array_json(participant.preferred_bone_names),
        string_array_json(participant.contact_bone_names),
        contact_pairs_json(participant.contact_pairs),
        target_frames_json(participant.target_frames),
        json_escape(participant.motion_contract_kind),
        json_escape(participant.motion_contract_source),
        direct_geometry_json(participant.direct_geometry),
        json_escape(exporter_version)
    )
end

local function packet_json(participant, timestamp_ms, entries, sample)
    return string.format(
        '{"type":"skeleton_binary","modelName":"%s","stableKey":"%s","timestampMs":%d,"schema":"fallen-doll-ue-world-v1","boneCount":%d,"bones":[%s],"trailer":%s}',
        json_escape(participant.model_name),
        json_escape(participant.stable_key),
        timestamp_ms,
        #entries,
        table.concat(entries, ","),
        trailer_json(participant, sample)
    )
end

local function write_packet(line)
    if SkeletonStream.spool == nil then
        return false
    end
    local ok = pcall(function()
        SkeletonStream.spool:write(line, "\n")
    end)
    return ok
end

local function ensure_parent_directory(file_path)
    local parent = tostring(file_path or ""):match("^(.*)/[^/]+$")
    if parent == nil or parent == "" then
        return true
    end
    if parent:find('[\r\n"]') ~= nil then
        return false, "runtime directory contains unsupported characters"
    end
    if os == nil or type(os.execute) ~= "function" then
        return false, "os.execute is unavailable"
    end
    os.execute('mkdir "' .. parent .. '" >nul 2>&1')
    return true
end

local function open_spool()
    local directory_ok, directory_error = ensure_parent_directory(Config.skeleton_spool_path)
    if not directory_ok then
        return false, directory_error
    end
    local spool, spool_error = io.open(Config.skeleton_spool_path, "w")
    if spool == nil then
        return false, spool_error
    end
    SkeletonStream.spool = spool
    SkeletonStream.samples_since_flush = 0
    SkeletonStream.spool_retry_count = 0
    SkeletonStream.samples_until_spool_retry = 0
    Log.info(string.format(
        "skeleton sampling enabled interval=%dms limit=%s output=%s",
        Config.skeleton_sample_interval_ms,
        Config.skeleton_sample_limit > 0 and tostring(Config.skeleton_sample_limit) or "continuous",
        Config.skeleton_spool_path
    ))
    return true
end

local function flush_packets()
    if SkeletonStream.spool == nil then
        return false
    end
    return pcall(function()
        SkeletonStream.spool:flush()
    end)
end

local function close_spool()
    if SkeletonStream.spool ~= nil then
        pcall(function()
            SkeletonStream.spool:flush()
            SkeletonStream.spool:close()
        end)
        SkeletonStream.spool = nil
    end
end

local function stop_internal(reason, preserve_detector_cache)
    if not SkeletonStream.running then
        return
    end
    SkeletonStream.running = false
    if SkeletonStream.loop_handle ~= nil and type(CancelDelayedAction) == "function" then
        CancelDelayedAction(SkeletonStream.loop_handle)
    end
    SkeletonStream.loop_handle = nil
    close_spool()
    GenericHAnimeProbe.clear_cache()
    SkeletonStream.active_hanime_id = nil
    if preserve_detector_cache ~= true then
        HAnimeDetector.clear_cache()
    end
    Log.info(string.format(
        "skeleton sampling stopped reason=%s samples=%d packets=%d",
        tostring(reason or "manual"),
        SkeletonStream.sample_count,
        SkeletonStream.sequence
    ))
end

local function reset_action_cache_if_changed(identity)
    local next_hanime_id = tostring((identity or {}).hanime_id or "")
    if next_hanime_id == "" then
        return
    end
    local previous_hanime_id = SkeletonStream.active_hanime_id
    if previous_hanime_id ~= nil and previous_hanime_id ~= next_hanime_id then
        -- A direct wheel switch can keep the same live participant Actors. Drop
        -- only action-scoped rules and diagnostic signatures; the verified
        -- component registry remains intact, so this never triggers another
        -- object discovery pass or refreshes clothing/physics.
        GenericHAnimeProbe.clear_cache()
        Log.info(string.format(
            "HAnime action cache reset previous=%s next=%s",
            tostring(previous_hanime_id),
            tostring(next_hanime_id)
        ))
    end
    SkeletonStream.active_hanime_id = next_hanime_id
end

local function sample_once()
    if tonumber(_G.FD_TCODE_STREAM_GENERATION or 0) ~= SkeletonStream.generation then
        stop_internal("superseded-by-hot-reload")
        return
    end
    if not SkeletonStream.running then
        return
    end
    SkeletonStream.attempt_count = SkeletonStream.attempt_count + 1
    if SkeletonStream.spool == nil then
        if SkeletonStream.samples_until_spool_retry > 0 then
            SkeletonStream.samples_until_spool_retry = SkeletonStream.samples_until_spool_retry - 1
            return
        end
        local opened, spool_error = open_spool()
        if not opened then
            SkeletonStream.spool_retry_count = SkeletonStream.spool_retry_count + 1
            SkeletonStream.samples_until_spool_retry = math.max(
                1,
                math.floor(1000 / Config.skeleton_sample_interval_ms)
            )
            if SkeletonStream.spool_retry_count == 1 or SkeletonStream.spool_retry_count % 10 == 0 then
                Log.warn("skeleton spool unavailable; retrying: " .. tostring(spool_error))
            end
        end
        return
    end
    SkeletonStream.samples_until_hanime_poll = SkeletonStream.samples_until_hanime_poll - 1
    if SkeletonStream.cached_hanime == nil or SkeletonStream.samples_until_hanime_poll <= 0 then
        SkeletonStream.cached_hanime = HAnimeDetector.sample()
        SkeletonStream.samples_until_hanime_poll = math.max(
            1,
            math.floor(Config.hanime_poll_interval_ms / Config.skeleton_sample_interval_ms)
        )
    end
    local hanime = SkeletonStream.cached_hanime
    local identity = hanime.identity or {}
    local scene_state = hanime.scene_state or {}
    local state_key = table.concat({
        tostring(hanime.state),
        tostring(identity.hanime_id or "<none>"),
        tostring(hanime.reason or "<none>"),
        tostring(hanime.montage_count or 0),
        tostring(hanime.matched_montage_count or 0),
        tostring(hanime.unknown_montage_count or 0),
        tostring(hanime.hanime_anim_blueprint_count or 0),
        tostring(hanime.visible_anim_blueprint_count or 0),
        table.concat(hanime.visible_anim_blueprint_labels or {}, ","),
        table.concat(hanime.unknown_assets or {}, ","),
        tostring(scene_state.anim_id or "<none>"),
        tostring(scene_state.current_state or "<none>"),
    }, "|")
    if state_key ~= SkeletonStream.last_hanime_state_key then
        SkeletonStream.last_hanime_state_key = state_key
        Log.info(string.format(
            "HAnime gate state=%s active=%s id=%s hAnimId=%s hState=%s matchedMontages=%d unknownMontages=%d hAnimBlueprints=%d visibleAnimBlueprints=%d visibleClasses=%s unknownAssets=%s reason=%s",
            tostring(hanime.state),
            tostring(hanime.active),
            tostring(identity.hanime_id or "<none>"),
            tostring(scene_state.anim_id or "<none>"),
            tostring(scene_state.current_state or "<none>"),
            tonumber(hanime.matched_montage_count or 0),
            tonumber(hanime.unknown_montage_count or 0),
            tonumber(hanime.hanime_anim_blueprint_count or 0),
            tonumber(hanime.visible_anim_blueprint_count or 0),
            table.concat(hanime.visible_anim_blueprint_labels or {}, ","),
            table.concat(hanime.unknown_assets or {}, ","),
            tostring(hanime.reason or "<none>")
        ))
    end
    if not hanime.active then
        if SkeletonStream.was_hanime_active then
            GenericHAnimeProbe.clear_cache()
        end
        SkeletonStream.was_hanime_active = false
        SkeletonStream.active_hanime_id = nil
        if SkeletonStream.stop_when_inactive then
            stop_internal("hanime-inactive", true)
        end
        return
    end
    SkeletonStream.was_hanime_active = true
    reset_action_cache_if_changed(identity)

    local sample, sample_error = GenericHAnimeProbe.sample(hanime)
    if sample == nil then
        local warning_interval = math.max(1, math.floor(2000 / Config.skeleton_sample_interval_ms))
        if SkeletonStream.attempt_count == 1 or SkeletonStream.attempt_count % warning_interval == 0 then
            Log.warn("skeleton sample waiting: " .. tostring(sample_error))
        end
        return
    end

    SkeletonStream.sample_count = SkeletonStream.sample_count + 1
    local timestamp_ms = SkeletonStream.timestamp_base_ms
        + (SkeletonStream.sample_count - 1) * Config.skeleton_sample_interval_ms
    for _, participant in ipairs(sample.participants) do
        local entries = {}
        for _, bone_name in ipairs(participant.bone_names) do
            table.insert(entries, bone_json(bone_name, participant.bones[bone_name]))
        end
        if not write_packet(packet_json(participant, timestamp_ms, entries, sample)) then
            Log.warn("skeleton spool write failed; reopening automatically")
            close_spool()
            SkeletonStream.samples_until_spool_retry = 0
            return
        end
        SkeletonStream.sequence = SkeletonStream.sequence + 1
    end
    SkeletonStream.samples_since_flush = SkeletonStream.samples_since_flush + 1
    local flush_interval = math.max(
        1,
        tonumber(Config.skeleton_spool_flush_interval_frames or 2)
    )
    if SkeletonStream.samples_since_flush >= flush_interval then
        if not flush_packets() then
            Log.warn("skeleton spool flush failed; reopening automatically")
            close_spool()
            SkeletonStream.samples_until_spool_retry = 0
            return
        end
        SkeletonStream.samples_since_flush = 0
    end

    local log_interval = math.max(1, tonumber(Config.skeleton_log_interval_frames or 500))
    if SkeletonStream.sample_count == 1 or SkeletonStream.sample_count % log_interval == 0 then
        Log.info(string.format(
            "skeleton sample=%d mode=generic-hanime id=%s binding=%d participants=%d packets=%d",
            SkeletonStream.sample_count,
            tostring(identity.hanime_id),
            tonumber(sample.binding_generation or 0),
            #sample.participants,
            SkeletonStream.sequence
        ))
    end

    if Config.skeleton_sample_limit > 0 and SkeletonStream.sample_count >= Config.skeleton_sample_limit then
        stop_internal("sample-limit")
    end
end

function SkeletonStream.start(options)
    if SkeletonStream.running then
        return
    end
    options = type(options) == "table" and options or {}
    if type(LoopInGameThreadWithDelay) ~= "function" then
        Log.error("LoopInGameThreadWithDelay is unavailable in this UE4SS build")
        return
    end
    _G.FD_TCODE_STREAM_GENERATION = tonumber(_G.FD_TCODE_STREAM_GENERATION or 0) + 1
    SkeletonStream.generation = _G.FD_TCODE_STREAM_GENERATION
    SkeletonStream.running = true
    SkeletonStream.sequence = 0
    SkeletonStream.sample_count = 0
    SkeletonStream.attempt_count = 0
    SkeletonStream.timestamp_base_ms = os.time() * 1000
    SkeletonStream.last_hanime_state_key = nil
    SkeletonStream.was_hanime_active = false
    SkeletonStream.active_hanime_id = nil
    SkeletonStream.cached_hanime = options.initial_hanime
    SkeletonStream.samples_until_hanime_poll = options.initial_hanime ~= nil
        and math.max(1, math.floor(Config.hanime_poll_interval_ms / Config.skeleton_sample_interval_ms))
        or 0
    SkeletonStream.samples_until_spool_retry = 0
    SkeletonStream.spool_retry_count = 0
    SkeletonStream.samples_since_flush = 0
    SkeletonStream.stop_when_inactive = options.stop_when_inactive == true
    GenericHAnimeProbe.clear_cache()
    if options.preserve_detector_cache ~= true then
        HAnimeDetector.clear_cache()
    end
    local opened, spool_error = open_spool()
    if not opened then
        Log.warn("skeleton spool unavailable at startup; retrying automatically: " .. tostring(spool_error))
        SkeletonStream.spool_retry_count = 1
        SkeletonStream.samples_until_spool_retry = math.max(
            1,
            math.floor(1000 / Config.skeleton_sample_interval_ms)
        )
    end
    SkeletonStream.loop_handle = LoopInGameThreadWithDelay(Config.skeleton_sample_interval_ms, sample_once)
    -- The loop already executes on the game thread. Do not enqueue a second
    -- immediate action from an object/event callback; overlapping delayed
    -- actions are a known UE4SS crash path and the component may still be
    -- inside construction at this point.
end

function SkeletonStream.stop(options)
    options = type(options) == "table" and options or {}
    stop_internal(options.reason or "manual", options.preserve_detector_cache == true)
end

function SkeletonStream.toggle()
    if SkeletonStream.running then
        SkeletonStream.stop()
    else
        SkeletonStream.start()
    end
end

function SkeletonStream.notify_hanime_event()
    -- Event hooks run on the game thread and only request an immediate
    -- identity sample. UObject reads remain centralized in sample_once.
    SkeletonStream.samples_until_hanime_poll = 0
end

function SkeletonStream.set_detector(detector)
    if type(detector) == "table" and type(detector.sample) == "function" then
        HAnimeDetector = detector
        SkeletonStream.cached_hanime = nil
        SkeletonStream.samples_until_hanime_poll = 0
        return true
    end
    return false
end

function SkeletonStream.is_running()
    return SkeletonStream.running == true
end

return SkeletonStream
