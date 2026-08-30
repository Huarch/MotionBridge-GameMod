local Log = require("fd_tcode.core.log")
local MotionContract = require("fd_tcode.core.hanime_motion_contract")
local Config = require("fd_tcode.config")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local GenericHAnimeProbe = {}

local binding_generation = 0
local binding_signature = nil
local input_binding_signature = nil
local read_result_signature = nil
local bone_fnames = {}
local get_socket_transform_function = nil
local get_socket_transform_lookup_error = nil
local motion_contract_cache = {}

local function quaternion_multiply(a, b)
    local ax, ay, az, aw = a[1], a[2], a[3], a[4]
    local bx, by, bz, bw = b[1], b[2], b[3], b[4]
    local result = {
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    }
    local length = math.sqrt(
        result[1] * result[1] + result[2] * result[2]
        + result[3] * result[3] + result[4] * result[4]
    )
    if length > 0.000001 then
        for index = 1, 4 do
            result[index] = result[index] / length
        end
    end
    return result
end

local function quaternion_rotate(q, v)
    local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
    local vx, vy, vz = v[1], v[2], v[3]
    local tx = 2 * (qy * vz - qz * vy)
    local ty = 2 * (qz * vx - qx * vz)
    local tz = 2 * (qx * vy - qy * vx)
    return {
        vx + qw * tx + (qy * tz - qz * ty),
        vy + qw * ty + (qz * tx - qx * tz),
        vz + qw * tz + (qx * ty - qy * tx),
    }
end

local function compose_transform(parent, child)
    local parent_scale = parent.scale or { 1, 1, 1 }
    local child_scale = child.scale or { 1, 1, 1 }
    local scaled_position = {
        child.position[1] * parent_scale[1],
        child.position[2] * parent_scale[2],
        child.position[3] * parent_scale[3],
    }
    local rotated = quaternion_rotate(parent.rotation, scaled_position)
    return {
        position = {
            rotated[1] + parent.position[1],
            rotated[2] + parent.position[2],
            rotated[3] + parent.position[3],
        },
        rotation = quaternion_multiply(parent.rotation, child.rotation),
        scale = {
            parent_scale[1] * child_scale[1],
            parent_scale[2] * child_scale[2],
            parent_scale[3] * child_scale[3],
        },
    }
end

local function struct_number(value, name)
    local ok, result = pcall(function()
        return value[name]
    end)
    return ok and type(result) == "number" and result or nil
end

local function relative_transform(component)
    local fields_ok, location, rotation, scale = pcall(function()
        return component.RelativeLocation, component.RelativeRotation, component.RelativeScale3D
    end)
    if not fields_ok then
        return nil, tostring(location)
    end
    local px = struct_number(location, "X")
    local py = struct_number(location, "Y")
    local pz = struct_number(location, "Z")
    local pitch = struct_number(rotation, "Pitch")
    local yaw = struct_number(rotation, "Yaw")
    local roll = struct_number(rotation, "Roll")
    local sx = struct_number(scale, "X")
    local sy = struct_number(scale, "Y")
    local sz = struct_number(scale, "Z")
    if px == nil or py == nil or pz == nil
        or pitch == nil or yaw == nil or roll == nil
        or sx == nil or sy == nil or sz == nil
    then
        return nil, "relative transform fields unreadable"
    end

    local half_to_radians = math.pi / 360
    local sp, cp = math.sin(pitch * half_to_radians), math.cos(pitch * half_to_radians)
    local syaw, cyaw = math.sin(yaw * half_to_radians), math.cos(yaw * half_to_radians)
    local sr, cr = math.sin(roll * half_to_radians), math.cos(roll * half_to_radians)
    return {
        position = { px, py, pz },
        rotation = {
            cr * sp * syaw - sr * cp * cyaw,
            -cr * sp * cyaw - sr * cp * syaw,
            cr * cp * syaw - sr * sp * cyaw,
            cr * cp * cyaw + sr * sp * syaw,
        },
        scale = { sx, sy, sz },
    }, nil
end

local function component_world_transform(component)
    -- UE 5.7's reflected parent pointer is not safe through the current UE4SS
    -- layout.  Keep the component-space validation path read-only until a
    -- verified world transform source is available.
    return {
        position = { 0, 0, 0 },
        rotation = { 0, 0, 0, 1 },
        scale = { 1, 1, 1 },
    }, nil
end

local function resolve_get_socket_transform_function()
    if get_socket_transform_function ~= nil then
        return get_socket_transform_function, nil
    end
    if get_socket_transform_lookup_error ~= nil then
        return nil, get_socket_transform_lookup_error
    end

    local lookup_ok, value = pcall(
        StaticFindObject,
        "/Script/Engine.SceneComponent:GetSocketTransform"
    )
    if not lookup_ok or not Safe.is_object(value) then
        get_socket_transform_lookup_error = "UFunction lookup failed: " .. tostring(value)
        return nil, get_socket_transform_lookup_error
    end
    get_socket_transform_function = value
    return value, nil
end

local function component_is_live(component)
    -- UE 5.7 exposes IsRegistered as a non-callable TrivialObject through the
    -- current UE4SS Lua bridge.  Calling it here used to throw and catch an
    -- exception for every participant on every motion frame.  World changes
    -- already clear the participant cache, and Safe.is_object performs the
    -- supported validity check, so do not put that failed reflection call in
    -- the realtime path.
    return Safe.is_object(component)
end

local function read_bone(
    component,
    bone_name,
    entry,
    component_space_transforms,
    component_space_transform_count,
    component_world
)
    local bone_index = ((entry or {}).bone_indices or {})[bone_name]
    if bone_index ~= nil and component_space_transforms ~= nil and component_world ~= nil then
        local transform_count = component_space_transform_count
        if type(transform_count) ~= "number" then
            return nil, "ComponentSpaceTransforms count unavailable"
        end
        if bone_index < 0 or bone_index >= transform_count then
            return nil, string.format(
                "bone index %d is outside ComponentSpaceTransforms count %d",
                bone_index,
                transform_count
            )
        end
        local array_ok, local_transform = pcall(function()
            return component_space_transforms[bone_index + 1]
        end)
        if not array_ok then
            return nil, "ComponentSpaceTransforms[" .. tostring(bone_index) .. "] failed: " .. tostring(local_transform)
        end
        local component_values = Safe.transform_values(local_transform)
        if component_values == nil then
            return nil, "component-space transform fields unreadable"
        end
        local values = compose_transform(component_world, component_values)
        local valid, reason = Safe.is_valid_transform(values)
        if not valid then
            return nil, reason
        end
        return values, nil
    end

    local socket_name = bone_fnames[bone_name]
    if socket_name == nil then
        local fname_ok, value = pcall(FName, bone_name)
        if not fname_ok then
            return nil, "FName failed: " .. tostring(value)
        end
        socket_name = value
        bone_fnames[bone_name] = socket_name
    end
    -- Resolve the UFunction once. Calling component:GetSocketTransform by
    -- name makes the Lua bridge repeat reflected method lookup for every bone
    -- on every frame; the explicit UFunction path has already been validated
    -- against the UE 5.7 parameter layout.
    local socket_function, socket_function_error = resolve_get_socket_transform_function()
    if socket_function == nil then
        return nil, socket_function_error
    end
    local call_ok, transform = pcall(function()
        return socket_function(component, socket_name, 0)
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

    local component_space_transforms = nil
    local component_space_transform_count = nil
    local component_world = nil
    if type(entry.bone_indices) == "table" then
        local transforms_ok, transforms = pcall(function()
            return component.ComponentSpaceTransforms
        end)
        if not transforms_ok then
            return nil, "ComponentSpaceTransforms unavailable: " .. tostring(transforms)
        end
        component_space_transforms = transforms
        local count_ok, transform_count = pcall(function()
            return #component_space_transforms
        end)
        if not count_ok or type(transform_count) ~= "number" then
            return nil, "ComponentSpaceTransforms length failed: " .. tostring(transform_count)
        end
        component_space_transform_count = transform_count
        local world_error = nil
        component_world, world_error = component_world_transform(component)
        if component_world == nil then
            return nil, "component world transform unavailable: " .. tostring(world_error)
        end
    end

    local contract_key = table.concat({
        tostring(entry.id or binding.catalog_role or "<entry>"),
        tostring(identity.hanime_id or "<hanime>"),
        tostring(identity.asset or "<asset>"),
        tostring(identity.category or "other"),
        tostring(identity.phase or "normal"),
    }, "|")
    local contract = motion_contract_cache[contract_key]
    local contract_error = nil
    if contract == nil then
        contract, contract_error = MotionContract.resolve(entry, identity)
        if contract ~= nil then
            motion_contract_cache[contract_key] = contract
        end
    end
    if contract == nil then
        return nil, contract_error or "HAnime motion contract unavailable"
    end
    local contact_pairs = MotionContract.contact_pairs(identity)
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
    local component_name = binding.component_name or Safe.object_name(component) or "<unknown>"
    for _, bone_name in ipairs(bone_names) do
        local source_bone_name = source_bones[bone_name] or bone_name
        local bone, read_error = read_bone(
            component,
            source_bone_name,
            entry,
            component_space_transforms,
            component_space_transform_count,
            component_world
        )
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
                local debug_bone = read_bone(
                    component,
                    debug_bone_name,
                    entry,
                    component_space_transforms,
                    component_space_transform_count,
                    component_world
                )
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
        component_name = component_name,
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
        contact_pairs = contact_pairs,
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
    local diagnostic_labels = {}
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
        local live = component_is_live(component)
        table.insert(diagnostic_labels, string.format(
            "%s[%s,live=%s]",
            tostring(binding.component_name or Safe.object_name(component) or "<component>"),
            tostring((binding.catalog_entry or {}).id or "<catalog>"),
            tostring(live)
        ))
        if live then
            local name = Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(result, binding)
            end
        end
    end
    local diagnostic_signature = table.concat(diagnostic_labels, "|")
    if diagnostic_signature ~= input_binding_signature then
        input_binding_signature = diagnostic_signature
        Log.info(string.format(
            "generic HAnime input bindings=%d live=%d %s",
            #source,
            #result,
            table.concat(diagnostic_labels, ",")
        ))
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
    local read_labels = {}
    for _, binding in ipairs(bindings) do
        local participant, read_error = read_component(binding, identity)
        if participant ~= nil then
            table.insert(participants, participant)
            table.insert(read_labels, tostring(binding.component_name or "<component>") .. "=ok")
        elseif #errors < 4 then
            table.insert(read_labels, string.format(
                "%s=error:%s",
                tostring(binding.component_name or "<component>"),
                tostring(read_error)
            ))
            table.insert(errors, string.format(
                "%s[%s]=%s",
                tostring(binding.component_name or Safe.object_name(binding.component) or "<component>"),
                tostring((binding.catalog_entry or {}).id or "<catalog>"),
                tostring(read_error)
            ))
        end
    end
    if #participants == 0 then
        return nil, "registered participant bone reads failed: " .. table.concat(errors, "; ")
    end

    if #errors > 0 then
        -- UE 5.7 can keep an old character actor registered and visible after
        -- a pose/character swap. Drop only participants whose complete
        -- functional contract failed, and emit the frame only if the
        -- survivors still form a self-contained reference + target pair.
        local references = 0
        local targets = 0
        for _, participant in ipairs(participants) do
            if participant.motion_contract_kind == "reference" then
                references = references + 1
            elseif participant.motion_contract_kind == "target" then
                targets = targets + 1
            end
        end
        if references == 0 or targets == 0 then
            return nil, "participant mapping incomplete: " .. table.concat(errors, "; ")
        end
    end
    local current_read_signature = table.concat(read_labels, "|")
    if current_read_signature ~= read_result_signature then
        read_result_signature = current_read_signature
        Log.info("generic HAnime read results " .. table.concat(read_labels, ","))
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
    input_binding_signature = nil
    read_result_signature = nil
    motion_contract_cache = {}
end

return GenericHAnimeProbe
