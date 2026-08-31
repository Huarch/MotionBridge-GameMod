local Config = require("fd_tcode.config")
local HScene = require("fd_tcode.core.hscene")
local Log = require("fd_tcode.core.log")
local PoseResolver = require("fd_tcode.core.pose_resolver")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local ProfileProbe = {}

local cached_binding = nil
local discovery_cooldown_samples = 0
local refresh_samples = 0
local binding_generation = 0

local participant_properties = {
    primary = {
        DefaultAlet = 900, MainCharacter = 850, Female = 800,
        FemaleA = 750, CharacterA = 700,
    },
    partner = {
        TargetCharacter = 900, PartnerCharacter = 850, Male = 820,
        MaleA = 800, MaleB = 780, ThirdCharacter = 720,
        SecondCharacter = 680, CharacterB = 640, CharacterC = 600,
    },
}

local function retry_samples()
    return math.max(1, math.floor(Config.skeleton_discovery_retry_ms / Config.skeleton_sample_interval_ms))
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

local function discover_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        return {}, tostring(values or "FindAllOf returned nil")
    end
    local components = {}
    for _, component in pairs(values) do
        if Safe.is_object(component) then
            local name = Safe.object_name(component) or ""
            if not string.find(name, "Default__", 1, true) then
                local _, entry, match = SkeletonCatalog.match_component(component)
                if entry ~= nil then
                    table.insert(components, {
                        component = component,
                        entry = entry,
                        match = match,
                    })
                end
            end
        end
    end
    return components, nil
end

local function component_objects(components)
    local result = {}
    for _, candidate in ipairs(components) do
        table.insert(result, candidate.component)
    end
    return result
end

local function object_chain_names(object)
    local names = {}
    local current = object
    local depth = 0
    while Safe.is_object(current) and depth < 6 do
        local name = Safe.object_name(current)
        if name == nil or names[name] then
            break
        end
        names[name] = true
        current = Safe.outer(current)
        depth = depth + 1
    end
    return names
end

local function participant_score(component, binding_role, scene_snapshot)
    if not scene_snapshot or not scene_snapshot.valid then
        return 0, nil
    end
    local chain_names = object_chain_names(component)
    local best_score = 0
    local best_property = nil
    for property_name, score in pairs(participant_properties[binding_role] or {}) do
        local participant = scene_snapshot.object_refs and scene_snapshot.object_refs[property_name]
        local participant_name = Safe.object_name(participant)
        if participant_name ~= nil and chain_names[participant_name] and score > best_score then
            best_score = score
            best_property = property_name
        end
    end
    return best_score, best_property
end

local function append_unique(target, seen, value)
    if value ~= nil and not seen[value] then
        seen[value] = true
        table.insert(target, value)
    end
end

local function semantic_bones(entry, semantic)
    local bones = {}
    local seen = {}
    if semantic == "hand_nearest_reference" then
        append_unique(bones, seen, entry.functional.right_hand)
        append_unique(bones, seen, entry.functional.left_hand)
    elseif semantic == "foot_nearest_reference" then
        append_unique(bones, seen, entry.functional.right_foot)
        append_unique(bones, seen, entry.functional.left_foot)
    else
        append_unique(bones, seen, entry.functional[semantic])
    end
    return bones
end

local function read_named_bones(component, names)
    local bones = {}
    for _, name in ipairs(names) do
        local bone, read_error = read_bone(component, name)
        if bone == nil then
            return nil, name .. "=" .. tostring(read_error)
        end
        bones[name] = bone
    end
    return bones, nil
end

local function distance(a, b)
    local dx = a[1] - b[1]
    local dy = a[2] - b[2]
    local dz = a[3] - b[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function pair_metrics(reference_bones, origin_name, tip_name, target_bones, target_names, max_distance_cm)
    local base = reference_bones[origin_name].position
    local tip = reference_bones[tip_name].position
    local axis_length_cm = distance(base, tip)
    if axis_length_cm < 0.1 or axis_length_cm > 30 then
        return nil, "reference axis length is invalid: " .. tostring(axis_length_cm)
    end

    local best_name = nil
    local best_distance = math.huge
    for _, name in ipairs(target_names) do
        local target = target_bones[name]
        if target ~= nil then
            local current_distance = distance(target.position, base)
            if current_distance < best_distance then
                best_name = name
                best_distance = current_distance
            end
        end
    end
    if best_name == nil then
        return nil, "no valid target bone"
    end
    if best_distance > max_distance_cm then
        return nil, string.format("profile pair is too far apart: %.1fcm", best_distance)
    end
    return {
        axis_length_cm = axis_length_cm,
        pair_distance_cm = best_distance,
        target_bone = best_name,
    }, nil
end

local function collect_role_candidates(components, catalog_id, binding_role, bone_names, scene_snapshot)
    local candidates = {}
    for _, candidate in ipairs(components) do
        if candidate.entry.id == catalog_id then
            local bones, read_error = read_named_bones(candidate.component, bone_names)
            if bones ~= nil then
                local scene_score, participant_property = participant_score(
                    candidate.component,
                    binding_role,
                    scene_snapshot
                )
                table.insert(candidates, {
                    component = candidate.component,
                    entry = candidate.entry,
                    match = candidate.match,
                    bones = bones,
                    score = scene_score + (candidate.match.method == "skinned-asset" and 200 or 50),
                    participant_property = participant_property,
                })
            else
                candidate.read_error = read_error
            end
        end
    end
    return candidates
end

local function choose_pair(profile, components, scene_snapshot)
    local geometry = profile.geometry
    local primary_catalog = profile.roles and profile.roles.primary
    local partner_catalog = profile.roles and profile.roles.partner
    local primary_entry = SkeletonCatalog.get(primary_catalog)
    local partner_entry = SkeletonCatalog.get(partner_catalog)
    if primary_entry == nil or partner_entry == nil then
        return nil, "profile skeleton catalog is not loaded"
    end

    local reference_entry = geometry.reference_role == "primary" and primary_entry or partner_entry
    local target_entry = geometry.target_role == "partner" and partner_entry or primary_entry
    local origin_name = reference_entry.functional[geometry.reference_origin_semantic]
    local tip_name = reference_entry.functional[geometry.reference_tip_semantic]
    local target_names = semantic_bones(target_entry, geometry.target_semantic)
    if origin_name == nil or tip_name == nil or #target_names == 0 then
        return nil, "profile semantic bone is missing from skeleton catalog"
    end

    local reference_catalog = geometry.reference_role == "primary" and primary_catalog or partner_catalog
    local target_catalog = geometry.target_role == "partner" and partner_catalog or primary_catalog
    local references = collect_role_candidates(
        components, reference_catalog, geometry.reference_role, { origin_name, tip_name }, scene_snapshot
    )
    local targets = collect_role_candidates(
        components, target_catalog, geometry.target_role, target_names, scene_snapshot
    )

    local best = nil
    local best_score = -math.huge
    for _, reference in ipairs(references) do
        for _, target in ipairs(targets) do
            local metrics = pair_metrics(
                reference.bones, origin_name, tip_name,
                target.bones, target_names,
                tonumber(geometry.max_pair_distance_cm or Config.hand_pair_max_distance_cm)
            )
            if metrics ~= nil then
                local score = reference.score + target.score - metrics.pair_distance_cm
                if score > best_score then
                    best_score = score
                    best = {
                        profile = profile,
                        reference = reference,
                        target = target,
                        origin_name = origin_name,
                        tip_name = tip_name,
                        target_names = target_names,
                        metrics = metrics,
                        score = score,
                    }
                end
            end
        end
    end
    if best == nil then
        return nil, string.format(
            "no active profile pair (profile=%s references=%d targets=%d)",
            tostring(profile.id), #references, #targets
        )
    end
    return best, nil
end

local function discover_binding()
    local components, discovery_error = discover_components()
    if discovery_error ~= nil then
        return false, discovery_error, false
    end
    local scene_snapshot = HScene.snapshot()
    local profile, resolution = PoseResolver.resolve(scene_snapshot, component_objects(components))
    if profile == nil then
        return false, resolution.reason, true
    end
    if profile.status ~= "enabled_for_simulation_validation" or profile.geometry == nil then
        return false, string.format("pose %s status=%s", profile.id, profile.status), false
    end
    local binding, binding_error = choose_pair(profile, components, scene_snapshot)
    if binding == nil then
        return false, binding_error, false
    end

    binding_generation = binding_generation + 1
    binding.generation = binding_generation
    binding.scene_key = HScene.binding_key(scene_snapshot)
    binding.resolution = resolution
    cached_binding = binding
    refresh_samples = 0
    Log.info(string.format(
        "profile binding generation=%d pose=%s primary=%s reference=%s target=%s targetBone=%s distance=%.2fcm axis=%.2fcm",
        binding_generation,
        profile.id,
        tostring(profile.roles.primary),
        tostring(binding.reference.entry.id),
        tostring(binding.target.entry.id),
        binding.metrics.target_bone,
        binding.metrics.pair_distance_cm,
        binding.metrics.axis_length_cm
    ))
    return true, nil, false
end

local function invalidate(reason)
    if cached_binding ~= nil then
        Log.warn(string.format(
            "profile binding invalidated generation=%d reason=%s",
            cached_binding.generation or 0,
            tostring(reason)
        ))
    end
    cached_binding = nil
    refresh_samples = 0
    discovery_cooldown_samples = 0
end

local function refresh_profile_if_needed()
    refresh_samples = refresh_samples + 1
    local interval = math.max(1, math.floor(500 / Config.skeleton_sample_interval_ms))
    if refresh_samples < interval or cached_binding == nil then
        return true, nil
    end
    refresh_samples = 0
    local snapshot = HScene.snapshot()
    local profile = PoseResolver.resolve(snapshot, {
        cached_binding.reference.component,
        cached_binding.target.component,
    })
    if profile == nil or profile.id ~= cached_binding.profile.id then
        invalidate("pose identity changed")
        return false, "pose identity changed"
    end
    return true, nil
end

local function ensure_binding()
    if cached_binding ~= nil
        and Safe.is_object(cached_binding.reference.component)
        and Safe.is_object(cached_binding.target.component) then
        return refresh_profile_if_needed()
    end
    cached_binding = nil
    if discovery_cooldown_samples > 0 then
        discovery_cooldown_samples = discovery_cooldown_samples - 1
        return false, "profile discovery is cooling down", false
    end
    local ready, discovery_error, allow_legacy = discover_binding()
    if not ready then
        discovery_cooldown_samples = retry_samples()
    end
    return ready, discovery_error, allow_legacy
end

function ProfileProbe.sample()
    local ready, binding_error, allow_legacy = ensure_binding()
    if not ready then
        return nil, binding_error, allow_legacy == true
    end

    local reference_bones, reference_error = read_named_bones(
        cached_binding.reference.component,
        { cached_binding.origin_name, cached_binding.tip_name }
    )
    local target_bones, target_error = read_named_bones(
        cached_binding.target.component,
        cached_binding.target_names
    )
    if reference_bones == nil or target_bones == nil then
        local reason = string.format(
            "profile bone read failed (reference=%s target=%s)",
            tostring(reference_error or "ok"), tostring(target_error or "ok")
        )
        invalidate(reason)
        return nil, reason, false
    end

    local metrics, metrics_error = pair_metrics(
        reference_bones, cached_binding.origin_name, cached_binding.tip_name,
        target_bones, cached_binding.target_names,
        tonumber(cached_binding.profile.geometry.max_pair_distance_cm or Config.hand_pair_max_distance_cm)
    )
    if metrics == nil then
        invalidate(metrics_error)
        return nil, metrics_error, false
    end
    cached_binding.metrics = metrics

    return {
        profile = cached_binding.profile,
        matched_pose = cached_binding.profile.id,
        matched_pose_status = cached_binding.profile.status,
        binding_generation = cached_binding.generation,
        reference = {
            component = Safe.object_name(cached_binding.reference.component),
            catalog = cached_binding.reference.entry.id,
            origin_name = cached_binding.origin_name,
            tip_name = cached_binding.tip_name,
            bones = reference_bones,
        },
        target = {
            component = Safe.object_name(cached_binding.target.component),
            catalog = cached_binding.target.entry.id,
            bone_name = metrics.target_bone,
            bones = target_bones,
        },
    }, nil, false
end

function ProfileProbe.clear_cache()
    cached_binding = nil
    discovery_cooldown_samples = 0
    refresh_samples = 0
end

return ProfileProbe
