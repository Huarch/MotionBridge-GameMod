local Log = require("fd_tcode.core.log")
local MotionContract = require("fd_tcode.core.hanime_motion_contract")
local Config = require("fd_tcode.config")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local GenericHAnimeProbe = {}

local binding_generation = 0
local binding_signature = nil
local bone_fnames = {}

local function component_is_live(component)
    if not Safe.is_object(component) then
        return false
    end
    local registered_ok, registered = pcall(function()
        return component:IsRegistered()
    end)
    return not registered_ok or registered ~= false
end

local function read_bone(component, bone_name)
    local socket_name = bone_fnames[bone_name]
    if socket_name == nil then
        local fname_ok, value = pcall(FName, bone_name)
        if not fname_ok then
            return nil, "FName failed: " .. tostring(value)
        end
        socket_name = value
        bone_fnames[bone_name] = socket_name
    end
    local call_ok, transform = pcall(function()
        return component:GetSocketTransform(socket_name, 0)
    end)
    if not call_ok then
        return nil, tostring(transform)
    end
    local values = Safe.transform_values(transform)
    if values == nil then
        return nil, "transform fields unreadable"
    end
    local valid, reason = Safe.is_valid_transform(values)
    if not valid then
        return nil, reason
    end
    return values, nil
end

local function read_component(binding, identity)
    local component = binding.component
    local entry = binding.catalog_entry
    if entry == nil then
        local _, matched_entry = SkeletonCatalog.match_component(component)
        entry = matched_entry
    end
    if entry == nil then
        return nil, "component is not in the unpacked skeleton catalog"
    end

    local contract, contract_error = MotionContract.resolve(entry, identity)
    if contract == nil then
        return nil, contract_error or "HAnime motion contract unavailable"
    end
    local bone_names = contract.bone_names or {}
    if #bone_names == 0 then
        return nil, string.format(
            "catalog %s has no minimal motion bone for category %s",
            tostring(entry.id),
            tostring(identity.category or "other")
        )
    end
    local bones = {}
    local source_bones = contract.source_bones or {}
    for _, bone_name in ipairs(bone_names) do
        local source_bone_name = source_bones[bone_name] or bone_name
        local bone, read_error = read_bone(component, source_bone_name)
        if bone == nil then
            return nil, source_bone_name .. "=" .. tostring(read_error)
        end
        bones[bone_name] = bone
    end
    if Config.motion_debug_enabled == true then
        local emitted = {}
        for _, bone_name in ipairs(bone_names) do
            emitted[bone_name] = true
        end
        for _, debug_bone_name in ipairs(contract.debug_bone_names or {}) do
            if not emitted[debug_bone_name] then
                local debug_bone = read_bone(component, debug_bone_name)
                if debug_bone ~= nil then
                    emitted[debug_bone_name] = true
                    bones[debug_bone_name] = debug_bone
                    table.insert(bone_names, debug_bone_name)
                end
            end
        end
    end
    if next(bones) == nil then
        return nil, "catalog has no stream bones"
    end
    return {
        component = component,
        component_name = binding.component_name or Safe.object_name(component) or "<unknown>",
        component_match_method = (binding.component_evidence or {}).method,
        catalog = entry.id,
        catalog_role = entry.role,
        role = contract.role,
        bone_names = bone_names,
        preferred_bone_names = contract.preferred_bone_names or {},
        -- The target contract is built from the edition-specific unpacked
        -- skeleton catalog.  Export it explicitly so the bridge never has to
        -- infer a genital/anal/mouth socket from a generic bone-name list.
        contact_bone_names = contract.kind == "target" and (contract.preferred_bone_names or {}) or {},
        target_frames = contract.target_frames or {},
        participant_tag = binding.participant_tag,
        participant_slot = binding.participant_slot,
        participant_priority = binding.participant_priority or 0,
        bones = bones,
        motion_contract_kind = contract.kind,
        motion_contract_source = contract.source,
        direct_geometry = contract.direct_geometry,
    }, nil
end

local function unique_live_bindings(identity)
    local result = {}
    local seen = {}
    local source = identity and identity.participant_bindings or {}
    if #source == 0 and identity ~= nil then
        for _, component in ipairs(identity.matched_components or {}) do
            table.insert(source, {
                component = component,
                component_name = Safe.object_name(component),
                participant_tag = "runtime_fallback",
                participant_slot = "generic",
                participant_priority = 0,
            })
        end
    end
    for _, binding in ipairs(source) do
        local component = binding.component
        if component_is_live(component) then
            local name = Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(result, binding)
            end
        end
    end
    return result
end

local function assign_stable_indices(participants)
    table.sort(participants, function(a, b)
        if a.role == b.role then
            if a.participant_priority ~= b.participant_priority then
                return a.participant_priority < b.participant_priority
            end
            if a.catalog == b.catalog then
                return a.component_name < b.component_name
            end
            return a.catalog < b.catalog
        end
        return a.role < b.role
    end)
    local counts = {}
    for _, participant in ipairs(participants) do
        local index = counts[participant.role] or 0
        counts[participant.role] = index + 1
        participant.role_index = index
        participant.model_name = string.format("fd:%s:%d", participant.catalog, index)
        participant.stable_key = string.format("fallen-doll:%s:%d", participant.role, index)
    end
end

local function update_binding(participants, hanime_id)
    local parts = { tostring(hanime_id or "<none>") }
    for _, participant in ipairs(participants) do
        table.insert(parts, participant.stable_key .. "=" .. participant.component_name)
    end
    local signature = table.concat(parts, "|")
    if signature ~= binding_signature then
        binding_signature = signature
        binding_generation = binding_generation + 1
        local labels = {}
        for _, participant in ipairs(participants) do
            table.insert(labels, string.format(
                "%s[%d bones,%s,%s]",
                participant.stable_key,
                #participant.bone_names,
                tostring(participant.motion_contract_source or "unknown"),
                tostring(participant.component_match_method or "unknown-match")
            ))
        end
        Log.info(string.format(
            "generic HAnime binding generation=%d id=%s participants=%d %s",
            binding_generation,
            tostring(hanime_id or "<none>"),
            #participants,
            table.concat(labels, ",")
        ))
    end
end

function GenericHAnimeProbe.sample(hanime)
    if hanime == nil or hanime.active ~= true then
        return nil, "HAnime gate is not active"
    end
    local identity = hanime.identity or {}
    if type(identity.motion_reference_missing) == "table" and #identity.motion_reference_missing > 0 then
        return nil, "motion contract reference missing after restricted rescan: "
            .. table.concat(identity.motion_reference_missing, ",")
    end
    local bindings = unique_live_bindings(identity)
    if #bindings == 0 then
        return nil, "exact HAnime has no live registered participant components"
    end

    local participants = {}
    local errors = {}
    for _, binding in ipairs(bindings) do
        local participant, read_error = read_component(binding, identity)
        if participant ~= nil then
            table.insert(participants, participant)
        elseif #errors < 4 then
            table.insert(errors, tostring(read_error))
        end
    end
    if #errors > 0 then
        -- Never emit a reference-only or target-only frame. F8Studio retains
        -- the last value for a missing model, so a partial frame could combine
        -- fresh data with a stale contact point and create false motion.
        return nil, "participant mapping incomplete: " .. table.concat(errors, "; ")
    end
    if #participants == 0 then
        return nil, "registered participant bone reads failed: " .. table.concat(errors, "; ")
    end

    assign_stable_indices(participants)
    update_binding(participants, identity.hanime_id)
    return {
        participants = participants,
        binding_generation = binding_generation,
        hanime_identity = identity,
        hanime_state = hanime.state,
        matched_pose = identity.hanime_id,
        matched_pose_status = "exact_hanime_active",
    }, nil
end

function GenericHAnimeProbe.clear_cache()
    binding_signature = nil
end

return GenericHAnimeProbe
