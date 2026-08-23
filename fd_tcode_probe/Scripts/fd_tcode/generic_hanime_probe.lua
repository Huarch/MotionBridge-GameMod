local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

local GenericHAnimeProbe = {}

local binding_generation = 0
local binding_signature = nil

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
    local fname_ok, socket_name = pcall(FName, bone_name)
    if not fname_ok then
        return nil, "FName failed: " .. tostring(socket_name)
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

local function read_component(component)
    local _, entry, match = SkeletonCatalog.match_component(component)
    if entry == nil then
        return nil, "component is not in the unpacked skeleton catalog"
    end

    local bones = {}
    for _, bone_name in ipairs(entry.stream_bones or {}) do
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
        component_name = Safe.object_name(component) or "<unknown>",
        catalog = entry.id,
        role = entry.role,
        bone_names = entry.stream_bones,
        bones = bones,
        match_method = match and match.method or "unknown",
    }, nil
end

local function unique_live_components(identity)
    local result = {}
    local seen = {}
    local source = identity and identity.montage_components or {}
    if #source == 0 and identity ~= nil then
        source = identity.matched_components or {}
    end
    for _, component in ipairs(source) do
        if component_is_live(component) then
            local name = Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(result, component)
            end
        end
    end
    return result
end

local function assign_stable_indices(participants)
    table.sort(participants, function(a, b)
        if a.catalog == b.catalog then
            return a.component_name < b.component_name
        end
        return a.catalog < b.catalog
    end)
    local counts = {}
    for _, participant in ipairs(participants) do
        local index = counts[participant.catalog] or 0
        counts[participant.catalog] = index + 1
        participant.role_index = index
        participant.model_name = string.format("fd:%s:%d", participant.catalog, index)
        participant.stable_key = string.format("fallen-doll:%s:%d", participant.catalog, index)
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
    local components = unique_live_components(identity)
    if #components == 0 then
        return nil, "exact HAnime has no live registered participant components"
    end

    local participants = {}
    local errors = {}
    for _, component in ipairs(components) do
        local participant, read_error = read_component(component)
        if participant ~= nil then
            table.insert(participants, participant)
        elseif #errors < 4 then
            table.insert(errors, tostring(read_error))
        end
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
