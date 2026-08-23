local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

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

-- Category defaults only rank contact candidates with no left/right ambiguity.
-- Hand and foot poses are intentionally absent: their active side and
-- primary/secondary limb must be annotated per HAnime instead of guessed.
local target_functions_by_category = {
    mouth = { "mouth_origin", "tongue_origin" },
    anal = { "anal_origin" },
    vaginal = { "vaginal_origin" },
}

local candidate_functions_by_category = {
    hand = { "right_hand", "left_hand" },
    foot = { "right_foot", "left_foot" },
    mouth = { "mouth_origin", "tongue_origin" },
    anal = { "anal_origin" },
    vaginal = { "vaginal_origin" },
}

-- Runtime-confirmed HAnime annotations rank all useful candidates. F8Studio
-- may disable the preferred bone and will then fall back to the next enabled
-- candidate without reloading this Mod. Hand02 was verified as right-primary;
-- the left hand remains an explicit secondary candidate.
local target_functions_by_hanime_id = {
    AletMale_Hand02 = { "right_hand", "left_hand" },
}

local function preferred_function_names(entry, identity)
    if entry.motion_role == "male" then
        return { "primary_origin" }
    end
    return target_functions_by_hanime_id[tostring(identity.hanime_id or "")]
        or target_functions_by_category[tostring(identity.category or "")]
        or {}
end

local function candidate_function_names(entry, identity)
    if entry.motion_role == "male" then
        -- Two points define the reference direction. Unrelated functional
        -- bones are not sampled for this participant on every motion frame.
        return { "primary_origin", "primary_tip" }
    end
    return target_functions_by_hanime_id[tostring(identity.hanime_id or "")]
        or candidate_functions_by_category[tostring(identity.category or "")]
        or {}
end

local function motion_bone_names(entry, identity)
    local functional = entry.functional or {}
    local result = {}
    local seen = {}
    for _, function_name in ipairs(candidate_function_names(entry, identity)) do
        local bone_name = functional[function_name]
        if bone_name ~= nil and not seen[bone_name] then
            seen[bone_name] = true
            table.insert(result, bone_name)
        end
    end
    return result
end

local function preferred_bone_names(entry, identity)
    local functional = entry.functional or {}
    local result = {}
    local seen = {}
    for _, function_name in ipairs(preferred_function_names(entry, identity)) do
        local bone_name = functional[function_name]
        if bone_name ~= nil and not seen[bone_name] then
            seen[bone_name] = true
            table.insert(result, bone_name)
        end
    end
    return result
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

    local bone_names = motion_bone_names(entry, identity)
    if #bone_names == 0 then
        return nil, string.format(
            "catalog %s has no minimal motion bone for category %s",
            tostring(entry.id),
            tostring(identity.category or "other")
        )
    end
    local bones = {}
    for _, bone_name in ipairs(bone_names) do
        local bone, read_error = read_bone(component, bone_name)
        if bone == nil then
            return nil, bone_name .. "=" .. tostring(read_error)
        end
        bones[bone_name] = bone
    end
    if next(bones) == nil then
        return nil, "catalog has no stream bones"
    end

    return {
        component = component,
        component_name = binding.component_name or Safe.object_name(component) or "<unknown>",
        catalog = entry.id,
        catalog_role = entry.role,
        role = entry.motion_role or entry.role,
        bone_names = bone_names,
        preferred_bone_names = preferred_bone_names(entry, identity),
        participant_tag = binding.participant_tag,
        participant_slot = binding.participant_slot,
        participant_priority = binding.participant_priority or 0,
        bones = bones,
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
                "%s[%d bones]", participant.stable_key, #participant.bone_names
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
