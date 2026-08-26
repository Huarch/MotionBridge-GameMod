-- Opt-in evidence recorder for strict precision queues.  This module is
-- intentionally separate from SkeletonStream: it never emits F8Studio packets,
-- does not load runtime rules, and is inert unless the explicit environment
-- switch is present before the game starts.

local Config = require("fd_tcode.config")
local IdentitySources = {
    ["demo-ue4.25"] = require("fd_tcode.demo_hanime_identity_data"),
    ["playtest-ue5"] = require("fd_tcode.hanime_identity_data"),
}
local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local CaptureData = require("fd_tcode.precision_capture_data")

local PrecisionCapture = {
    running = false,
    loop_handle = nil,
    spool = nil,
    components = {},
    pending_components = {},
    last_state_key = nil,
    sequence = 0,
    started_epoch_ms = 0,
    started_clock_s = 0,
    case_by_hanime = {},
    identity_source = nil,
}

local function json_escape(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\n", "\\n")
    return text
end

local function object_text(value)
    return Safe.object_name(value) or Safe.value_text(value) or "<unreadable>"
end

local function component_is_live(component)
    if not Safe.is_object(component) then
        return false
    end
    local ok, registered = pcall(function()
        return component:IsRegistered()
    end)
    return not ok or registered ~= false
end

local function asset_full_name(component)
    for _, property_name in ipairs({ "SkinnedAsset", "SkeletalMesh" }) do
        local ok, asset = Safe.read(component, property_name)
        if ok and asset ~= nil then
            local name = Safe.object_name(asset)
            if name ~= nil then
                return name, property_name
            end
            local text = Safe.value_text(asset)
            if text ~= nil and text ~= "<nil>" then
                return text, property_name
            end
        end
    end
    return "", "<unreadable>"
end

local function asset_leaf(full_name)
    return tostring(full_name or ""):match("([^%./:]+)$") or tostring(full_name or "")
end

local function refresh_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        return false, tostring(values or "FindAllOf returned nil")
    end
    local components = {}
    local seen = {}
    for _, component in pairs(values) do
        if component_is_live(component) then
            local name = Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(components, component)
            end
        end
    end
    table.sort(components, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
    PrecisionCapture.components = components
    return true, nil
end

local function merge_pending_components()
    if #PrecisionCapture.pending_components == 0 then
        return
    end
    -- A component-added event can happen during a queued HAnime transition.
    -- Rebuild once from the authoritative engine collection; no periodic
    -- discovery occurs while the cache stays live.
    PrecisionCapture.pending_components = {}
    refresh_components()
end

local function ensure_components()
    merge_pending_components()
    if #PrecisionCapture.components == 0 then
        return refresh_components()
    end
    for _, component in ipairs(PrecisionCapture.components) do
        if not component_is_live(component) then
            return refresh_components()
        end
    end
    return true, nil
end

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function active_montage(component)
    if not component_is_live(component) then
        return nil
    end
    local anim_ok, anim_instance = pcall(function()
        return component:GetAnimInstance()
    end)
    if not anim_ok or not Safe.is_object(anim_instance) then
        return nil
    end
    local montage_ok, montage = pcall(function()
        return anim_instance:GetCurrentActiveMontage()
    end)
    if not montage_ok or not Safe.is_object(montage) then
        return nil
    end
    local full_name = Safe.object_name(montage)
    local asset = tostring(full_name or ""):match("%.([^%.:]+)$")
        or tostring(full_name or ""):match("([^/]+)$")
        or tostring(full_name or "")
    local source = PrecisionCapture.identity_source
    local identity = source and source.by_montage and source.by_montage[normalized(asset)] or nil
    if identity == nil then
        return nil
    end
    return {
        component = component,
        component_name = Safe.object_name(component) or "<unknown>",
        anim_instance = anim_instance,
        montage = montage,
        montage_full_name = full_name or asset,
        montage_asset = asset,
        identity = identity,
    }
end

local function current_section(anim_instance, montage)
    local ok, value = pcall(function()
        return anim_instance:Montage_GetCurrentSection(montage)
    end)
    if not ok then
        return "<unavailable>"
    end
    return object_text(value)
end

local function montage_position(anim_instance, montage)
    local ok, value = pcall(function()
        return anim_instance:Montage_GetPosition(montage)
    end)
    return ok and type(value) == "number" and value or nil
end

local function transform_json(value)
    local values = Safe.transform_values(value)
    if values == nil then
        return nil
    end
    local valid, reason = Safe.is_valid_transform(values)
    if not valid then
        return nil, reason
    end
    local p = values.position
    local q = values.rotation
    return string.format(
        '{"positionCm":[%.6f,%.6f,%.6f],"rotationXyzw":[%.8f,%.8f,%.8f,%.8f]}',
        p[1], p[2], p[3], q[1], q[2], q[3], q[4]
    )
end

local function read_transform(component, bone_name, space)
    local name_ok, fname = pcall(FName, bone_name)
    if not name_ok then
        return nil, "FName failed: " .. tostring(fname)
    end
    local ok, transform = pcall(function()
        return component:GetSocketTransform(fname, space)
    end)
    if not ok then
        return nil, tostring(transform)
    end
    return transform_json(transform)
end

local function component_transform(component)
    local ok, transform = pcall(function()
        return component:GetComponentTransform()
    end)
    if not ok then
        return nil, tostring(transform)
    end
    return transform_json(transform)
end

local function bone_json(component, bone_name)
    -- ERelativeTransformSpace: RTS_World=0 and RTS_Component=2.  The latter
    -- is the runtime component/local-space observation; it is deliberately
    -- not mislabeled as a parent-bone local transform.
    local world, world_error = read_transform(component, bone_name, 0)
    local component_space, component_error = read_transform(component, bone_name, 2)
    if world == nil or component_space == nil then
        return nil, string.format(
            "%s world=%s component=%s",
            bone_name,
            tostring(world_error or "ok"),
            tostring(component_error or "ok")
        )
    end
    return string.format(
        '{"name":"%s","world":%s,"componentSpace":%s}',
        json_escape(bone_name), world, component_space
    )
end

local function now_ms()
    return PrecisionCapture.started_epoch_ms
        + math.floor((os.clock() - PrecisionCapture.started_clock_s) * 1000)
end

local function write_line(line)
    if PrecisionCapture.spool == nil then
        return false
    end
    local ok = pcall(function()
        PrecisionCapture.spool:write(line, "\n")
        PrecisionCapture.spool:flush()
    end)
    return ok
end

local function open_spool()
    local path = Config.precision_capture_spool_path
    local parent = tostring(path):match("^(.*)/[^/]+$")
    if parent ~= nil and parent ~= "" then
        local created = pcall(function()
            os.execute('mkdir "' .. parent .. '" >nul 2>&1')
        end)
        if not created then
            return false, "cannot create capture directory"
        end
    end
    local handle, open_error = io.open(path, "w")
    if handle == nil then
        return false, tostring(open_error)
    end
    PrecisionCapture.spool = handle
    return true, nil
end

local function select_strict_case(active)
    local candidates = PrecisionCapture.case_by_hanime[tostring(active.identity.hanime_id or "")]
    if candidates == nil then
        return nil
    end
    return candidates
end

local function active_cases()
    local grouped = {}
    for _, component in ipairs(PrecisionCapture.components) do
        local active = active_montage(component)
        if active ~= nil then
            local cases = select_strict_case(active)
            if cases ~= nil then
                local hanime_id = tostring(active.identity.hanime_id)
                grouped[hanime_id] = grouped[hanime_id] or { active = active, cases = cases, count = 0 }
                grouped[hanime_id].count = grouped[hanime_id].count + 1
            end
        end
    end
    local selected = nil
    for _, group in pairs(grouped) do
        if selected == nil or group.count > selected.count then
            selected = group
        elseif selected ~= nil and group.count == selected.count
            -- Two exact queued HAnime IDs at the same priority are ambiguous;
            -- never guess which scene supplies a capture record.
            return nil, "ambiguous_exact_hanime"
        end
    end
    return selected, nil
end

local function capture_case(group, case)
    local expected = case.mesh_leaf
    local active = group.active
    local any_mesh = false
    for _, component in ipairs(PrecisionCapture.components) do
        if component_is_live(component) then
            local asset, property = asset_full_name(component)
            if asset_leaf(asset) == expected then
                any_mesh = true
                local component_world, component_error = component_transform(component)
                local bones = {}
                local errors = {}
                for _, bone_name in ipairs(case.bones) do
                    local record, error_text = bone_json(component, bone_name)
                    if record == nil then
                        table.insert(errors, error_text)
                    else
                        table.insert(bones, record)
                    end
                end
                local status = (#errors == 0 and component_world ~= nil) and "complete" or "incomplete"
                local line = string.format(
                    '{"schema":"fd-precision-capture-v1","sequence":%d,"timestampMs":%d,"edition":"%s","caseId":"%s","hanimeId":"%s","hanimeAsset":"%s","montageFullName":"%s","montageSection":"%s","montagePosition":%s,"matchedMontageComponent":"%s","component":"%s","skinnedAsset":"%s","skinnedAssetProperty":"%s","componentWorld":%s,"status":"%s","bones":[%s],"errors":[%s]}',
                    PrecisionCapture.sequence,
                    now_ms(),
                    json_escape(Config.precision_capture_edition),
                    json_escape(case.id),
                    json_escape(active.identity.hanime_id),
                    json_escape(active.montage_asset),
                    json_escape(active.montage_full_name),
                    json_escape(current_section(active.anim_instance, active.montage)),
                    montage_position(active.anim_instance, active.montage) and string.format("%.6f", montage_position(active.anim_instance, active.montage)) or "null",
                    json_escape(active.component_name),
                    json_escape(Safe.object_name(component) or "<unknown>"),
                    json_escape(asset),
                    json_escape(property),
                    component_world or "null",
                    status,
                    table.concat(bones, ","),
                    table.concat((function()
                        local result = {}
                        for _, error_text in ipairs(errors) do table.insert(result, '"' .. json_escape(error_text) .. '"') end
                        if component_error ~= nil then table.insert(result, '"componentWorld=' .. json_escape(component_error) .. '"') end
                        return result
                    end)(), ",")
                )
                PrecisionCapture.sequence = PrecisionCapture.sequence + 1
                if not write_line(line) then
                    Log.warn("precision capture spool write failed")
                end
            end
        end
    end
    return any_mesh
end

local function sample_once()
    if not PrecisionCapture.running then
        return
    end
    local ready, error_text = ensure_components()
    if not ready then
        Log.warn("precision capture component discovery failed: " .. tostring(error_text))
        return
    end
    local group, selection_error = active_cases()
    local key = group and tostring(group.active.identity.hanime_id) or tostring(selection_error or "idle")
    if key ~= PrecisionCapture.last_state_key then
        PrecisionCapture.last_state_key = key
        Log.info("precision capture state=" .. key)
    end
    if group == nil then
        return
    end
    for _, case in ipairs(group.cases) do
        capture_case(group, case)
    end
end

function PrecisionCapture.queue_component(component)
    if PrecisionCapture.running and component ~= nil then
        table.insert(PrecisionCapture.pending_components, component)
    end
end

function PrecisionCapture.start()
    if Config.precision_capture_enabled ~= true then
        return
    end
    if PrecisionCapture.running then
        return
    end
    local cases = CaptureData.editions[Config.precision_capture_edition]
    local identity_source = IdentitySources[Config.precision_capture_edition]
    if cases == nil or identity_source == nil then
        Log.error("precision capture refused: FD_TCODE_PRECISION_EDITION must be a strict supported edition")
        return
    end
    if type(LoopInGameThreadWithDelay) ~= "function" then
        Log.error("precision capture refused: LoopInGameThreadWithDelay is unavailable")
        return
    end
    PrecisionCapture.case_by_hanime = {}
    PrecisionCapture.identity_source = identity_source
    for _, case in ipairs(cases) do
        local bucket = PrecisionCapture.case_by_hanime[case.hanime_id] or {}
        table.insert(bucket, case)
        PrecisionCapture.case_by_hanime[case.hanime_id] = bucket
    end
    local opened, open_error = open_spool()
    if not opened then
        Log.error("precision capture refused: " .. tostring(open_error))
        return
    end
    PrecisionCapture.running = true
    PrecisionCapture.sequence = 0
    PrecisionCapture.started_epoch_ms = os.time() * 1000
    PrecisionCapture.started_clock_s = os.clock()
    PrecisionCapture.last_state_key = nil
    PrecisionCapture.loop_handle = LoopInGameThreadWithDelay(Config.precision_capture_interval_ms, sample_once)
    ExecuteInGameThread(sample_once)
    Log.info(string.format(
        "precision capture ENABLED edition=%s cases=%d interval=%dms output=%s; no device output or rule generation",
        Config.precision_capture_edition, #cases, Config.precision_capture_interval_ms, Config.precision_capture_spool_path
    ))
end

return PrecisionCapture
