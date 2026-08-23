local Config = require("fd_tcode.config")
local GenericHAnimeProbe = require("fd_tcode.generic_hanime_probe")
local HAnimeDetector = require("fd_tcode.hanime_detector")
local Log = require("fd_tcode.log")

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
    cached_hanime = nil,
    samples_until_hanime_poll = 0,
}

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

local function trailer_json(participant, sample)
    local identity = sample.hanime_identity or {}
    return string.format(
        '{"profileId":"fallen-doll","poseId":"%s","poseStatus":"%s","hanimeActive":true,"hanimeId":"%s","hanimeAsset":"%s","hanimeCategory":"%s","hanimePhase":"%s","hanimeState":"%s","recognitionSource":"%s","bindingGeneration":%d,"role":"%s","roleIndex":%d,"characterRole":"%s","catalogId":"%s","participantTag":"%s","participantSlot":"%s","participantPriority":%d,"component":"%s","preferredBones":%s,"streamMode":"functional-contact-bones","exporterVersion":"fd-tcode-lua-0.14"}',
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
        string_array_json(participant.preferred_bone_names)
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
            SkeletonStream.spool:close()
        end)
        SkeletonStream.spool = nil
    end
end

local function stop_internal(reason)
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
    HAnimeDetector.clear_cache()
    Log.info(string.format(
        "skeleton sampling stopped reason=%s samples=%d packets=%d",
        tostring(reason or "manual"),
        SkeletonStream.sample_count,
        SkeletonStream.sequence
    ))
end

local function sample_once()
    if not SkeletonStream.running then
        return
    end
    SkeletonStream.attempt_count = SkeletonStream.attempt_count + 1
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
        table.concat(hanime.unknown_assets or {}, ","),
        tostring(scene_state.anim_id or "<none>"),
        tostring(scene_state.current_state or "<none>"),
    }, "|")
    if state_key ~= SkeletonStream.last_hanime_state_key then
        SkeletonStream.last_hanime_state_key = state_key
        Log.info(string.format(
            "HAnime gate state=%s active=%s id=%s hAnimId=%s hState=%s matchedMontages=%d unknownMontages=%d unknownAssets=%s reason=%s",
            tostring(hanime.state),
            tostring(hanime.active),
            tostring(identity.hanime_id or "<none>"),
            tostring(scene_state.anim_id or "<none>"),
            tostring(scene_state.current_state or "<none>"),
            tonumber(hanime.matched_montage_count or 0),
            tonumber(hanime.unknown_montage_count or 0),
            table.concat(hanime.unknown_assets or {}, ","),
            tostring(hanime.reason or "<none>")
        ))
    end
    if not hanime.active then
        if SkeletonStream.was_hanime_active then
            GenericHAnimeProbe.clear_cache()
        end
        SkeletonStream.was_hanime_active = false
        return
    end
    SkeletonStream.was_hanime_active = true

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
            stop_internal("spool-write-failed")
            return
        end
        SkeletonStream.sequence = SkeletonStream.sequence + 1
    end
    if not flush_packets() then
        stop_internal("spool-flush-failed")
        return
    end

    if SkeletonStream.sample_count == 1 or SkeletonStream.sample_count % 20 == 0 then
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

function SkeletonStream.start()
    if SkeletonStream.running then
        return
    end
    if type(LoopInGameThreadWithDelay) ~= "function" then
        Log.error("LoopInGameThreadWithDelay is unavailable in this UE4SS build")
        return
    end
    local spool, spool_error = io.open(Config.skeleton_spool_path, "w")
    if spool == nil then
        Log.error("cannot open skeleton spool: " .. tostring(spool_error))
        return
    end

    SkeletonStream.spool = spool
    SkeletonStream.running = true
    SkeletonStream.sequence = 0
    SkeletonStream.sample_count = 0
    SkeletonStream.attempt_count = 0
    SkeletonStream.timestamp_base_ms = os.time() * 1000
    SkeletonStream.last_hanime_state_key = nil
    SkeletonStream.was_hanime_active = false
    SkeletonStream.cached_hanime = nil
    SkeletonStream.samples_until_hanime_poll = 0
    GenericHAnimeProbe.clear_cache()
    HAnimeDetector.clear_cache()
    SkeletonStream.loop_handle = LoopInGameThreadWithDelay(Config.skeleton_sample_interval_ms, sample_once)
    Log.info(string.format(
        "skeleton sampling enabled interval=%dms limit=%s output=%s",
        Config.skeleton_sample_interval_ms,
        Config.skeleton_sample_limit > 0 and tostring(Config.skeleton_sample_limit) or "continuous",
        Config.skeleton_spool_path
    ))
    ExecuteInGameThread(sample_once)
end

function SkeletonStream.stop()
    stop_internal("manual")
end

function SkeletonStream.toggle()
    if SkeletonStream.running then
        SkeletonStream.stop()
    else
        SkeletonStream.start()
    end
end

return SkeletonStream
