local Config = require("fd_tcode.config")
local HScene = require("fd_tcode.core.hscene")
local Log = require("fd_tcode.core.log")
local PoseResolver = require("fd_tcode.core.pose_resolver")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local BoneProbe = {}

local cached_pair = nil
local discovery_cooldown_samples = 0
local binding_generation = 0

local function discovery_retry_samples()
    return math.max(1, math.floor(Config.skeleton_discovery_retry_ms / Config.skeleton_sample_interval_ms))
end

local function call_get_socket_transform(component, socket_name)
    local ok, transform = pcall(function()
        -- ERelativeTransformSpace::RTS_World is zero. World space is required
        -- to compare components belonging to different participant actors.
        return component:GetSocketTransform(socket_name, 0)
    end)
    if not ok then
        return false, nil, tostring(transform)
    end
    return true, transform, nil
end

local function discover_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        return {}, tostring(values or "FindAllOf returned nil")
    end

    local components = {}
    for _, value in pairs(values) do
        if Safe.is_object(value) then
            local name = Safe.object_name(value) or ""
            if not string.find(name, "Default__", 1, true) then
                table.insert(components, value)
            end
        end
    end
    return components, nil
end

local function read_bone(component, bone_name)
    local fname_ok, socket_name = pcall(FName, bone_name)
    if not fname_ok then
        return nil, "FName failed: " .. tostring(socket_name)
    end
    local transform_ok, transform, transform_error = call_get_socket_transform(component, socket_name)
    if not transform_ok then
        return nil, transform_error
    end
    local values = Safe.transform_values(transform)
    if values == nil then
        return nil, "transform fields unreadable"
    end
    local valid, invalid_reason = Safe.is_valid_transform(values)
    if not valid then
        return nil, invalid_reason
    end
    return values, nil
end

local function read_entry_bones(component, entry)
    local bones = {}
    for _, bone_name in ipairs(entry.stream_bones or {}) do
        local value, read_error = read_bone(component, bone_name)
        if value == nil then
            return nil, bone_name .. "=" .. tostring(read_error)
        end
        bones[bone_name] = value
    end
    return bones, nil
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

local role_properties = {
    alet = {
        DefaultAlet = 900,
        MainCharacter = 800,
        Female = 750,
        FemaleA = 700,
        CharacterA = 650,
    },
    male = {
        TargetCharacter = 900,
        PartnerCharacter = 850,
        Male = 800,
        MaleA = 780,
        MaleB = 760,
        ThirdCharacter = 700,
        SecondCharacter = 650,
        CharacterB = 600,
        CharacterC = 550,
        MainCharacter = 300,
    },
}

local function participant_score(component, role, scene_snapshot)
    if not scene_snapshot or not scene_snapshot.valid then
        return 0, nil
    end
    local chain_names = object_chain_names(component)
    local best_score = 0
    local best_property = nil
    for property_name, score in pairs(role_properties[role] or {}) do
        local participant = scene_snapshot.object_refs and scene_snapshot.object_refs[property_name]
        local participant_name = Safe.object_name(participant)
        if participant_name ~= nil and chain_names[participant_name] and score > best_score then
            best_score = score
            best_property = property_name
        end
    end
    return best_score, best_property
end

local function collect_candidates(components, scene_snapshot)
    local candidates = { alet = {}, male = {} }
    for _, component in ipairs(components) do
        local role, entry, binding = SkeletonCatalog.match_component(component)
        if candidates[role] ~= nil then
            local bones, read_error = read_entry_bones(component, entry)
            if bones ~= nil then
                local scene_score, participant_property = participant_score(component, role, scene_snapshot)
                local match_score = binding.method == "skinned-asset" and 200 or 50
                table.insert(candidates[role], {
                    component = component,
                    entry = entry,
                    binding = binding,
                    bones = bones,
                    score = scene_score + match_score,
                    participant_property = participant_property,
                })
            else
                binding.read_error = read_error
            end
        end
    end
    return candidates
end

local function distance(a, b)
    local dx = a[1] - b[1]
    local dy = a[2] - b[2]
    local dz = a[3] - b[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function hand_pair_metrics(alet_bones, male_bones)
    local hand = alet_bones.R_Hand.position
    local base = male_bones.Penis01.position
    local tip = male_bones.Penis02.position
    local axis_length_cm = distance(base, tip)
    local pair_distance_cm = distance(hand, base)
    if axis_length_cm < 0.1 or axis_length_cm > 30 then
        return nil, string.format("reference axis length is invalid: %.3fcm", axis_length_cm)
    end
    if pair_distance_cm > Config.hand_pair_max_distance_cm then
        return nil, string.format("Hand profile pair is too far apart: %.1fcm", pair_distance_cm)
    end
    return {
        axis_length_cm = axis_length_cm,
        pair_distance_cm = pair_distance_cm,
    }, nil
end

local function choose_hand_pair(candidates)
    local best = nil
    local best_score = -math.huge
    for _, alet in ipairs(candidates.alet) do
        for _, male in ipairs(candidates.male) do
            local metrics = hand_pair_metrics(alet.bones, male.bones)
            if metrics ~= nil then
                -- HScene ownership wins when available. Geometry resolves
                -- duplicate live/stale instances of the same known asset.
                local score = alet.score + male.score - metrics.pair_distance_cm
                if score > best_score then
                    best_score = score
                    best = {
                        alet = alet,
                        male = male,
                        metrics = metrics,
                        score = score,
                    }
                end
            end
        end
    end
    return best
end

local function binding_text(candidate)
    return string.format(
        "%s via=%s participant=%s component=%s",
        candidate.entry.id,
        tostring(candidate.binding.method),
        tostring(candidate.participant_property or "<geometry>"),
        tostring(candidate.binding.component)
    )
end

local function discover_hand_pair()
    local components, discovery_error = discover_components()
    if discovery_error ~= nil then
        return false, discovery_error
    end
    local scene_snapshot = HScene.snapshot()
    local candidates = collect_candidates(components, scene_snapshot)
    local pair = choose_hand_pair(candidates)
    if pair == nil then
        return false, string.format(
            "no active Hand pair (aletCandidates=%d maleCandidates=%d scene=%s)",
            #candidates.alet,
            #candidates.male,
            HScene.binding_key(scene_snapshot)
        )
    end

    binding_generation = binding_generation + 1
    pair.pose, pair.pose_resolution = PoseResolver.resolve(scene_snapshot, components)
    pair.scene_key = HScene.binding_key(scene_snapshot)
    pair.generation = binding_generation
    cached_pair = pair
    Log.info(string.format(
        "skeleton binding generation=%d distance=%.2fcm axis=%.2fcm scene=%s | alet=%s | male=%s",
        binding_generation,
        pair.metrics.pair_distance_cm,
        pair.metrics.axis_length_cm,
        pair.scene_key,
        binding_text(pair.alet),
        binding_text(pair.male)
    ))
    for _, line in ipairs(PoseResolver.lines(pair.pose, pair.pose_resolution)) do
        Log.info("binding." .. line)
    end
    return true, nil
end

local function invalidate_binding(reason)
    if cached_pair ~= nil then
        Log.warn(string.format(
            "skeleton binding invalidated generation=%d reason=%s",
            cached_pair.generation or 0,
            tostring(reason)
        ))
    end
    cached_pair = nil
    discovery_cooldown_samples = 0
end

local function ensure_hand_pair()
    if cached_pair ~= nil
        and Safe.is_object(cached_pair.alet.component)
        and Safe.is_object(cached_pair.male.component) then
        return true, nil
    end
    cached_pair = nil
    if discovery_cooldown_samples > 0 then
        discovery_cooldown_samples = discovery_cooldown_samples - 1
        return false, "active Hand pair discovery is cooling down"
    end
    local ready, discovery_error = discover_hand_pair()
    if not ready then
        discovery_cooldown_samples = discovery_retry_samples()
    end
    return ready, discovery_error
end

function BoneProbe.sample_main()
    local ready, discovery_error = ensure_hand_pair()
    if not ready then
        return nil, discovery_error
    end

    local alet_bones, alet_error = read_entry_bones(cached_pair.alet.component, cached_pair.alet.entry)
    local male_bones, male_error = read_entry_bones(cached_pair.male.component, cached_pair.male.entry)
    if alet_bones == nil or male_bones == nil then
        local reason = string.format(
            "bone read failed (alet=%s male=%s)",
            tostring(alet_error or "ok"),
            tostring(male_error or "ok")
        )
        invalidate_binding(reason)
        return nil, reason
    end

    local metrics, geometry_error = hand_pair_metrics(alet_bones, male_bones)
    if metrics == nil then
        invalidate_binding(geometry_error)
        return nil, geometry_error
    end
    cached_pair.metrics = metrics

    return {
        profile = "hand",
        matched_pose = cached_pair.pose and cached_pair.pose.id or nil,
        matched_pose_status = cached_pair.pose and cached_pair.pose.status or "unmapped",
        binding_generation = cached_pair.generation,
        alet = {
            component = Safe.object_name(cached_pair.alet.component),
            catalog = cached_pair.alet.entry.id,
            bones = alet_bones,
        },
        male = {
            component = Safe.object_name(cached_pair.male.component),
            catalog = cached_pair.male.entry.id,
            bones = male_bones,
        },
    }, nil
end

function BoneProbe.clear_cache()
    cached_pair = nil
    discovery_cooldown_samples = 0
end

function BoneProbe.snapshot()
    local components, discovery_error = discover_components()
    local result = {
        component_count = #components,
        matches = {},
        errors = {},
    }
    if discovery_error ~= nil then
        table.insert(result.errors, "discovery=" .. discovery_error)
        return result
    end

    local scene_snapshot = HScene.snapshot()
    for _, component in ipairs(components) do
        local role, entry, binding = SkeletonCatalog.match_component(component)
        if entry ~= nil then
            local bones, read_error = read_entry_bones(component, entry)
            table.insert(result.matches, {
                name = Safe.object_name(component),
                class = Safe.class_name(component),
                role = role,
                catalog = entry.id,
                binding = binding,
                bones = bones or {},
                error = read_error,
            })
            if #result.matches >= Config.bone_probe_max_matches then
                break
            end
        end
    end
    result.scene_key = HScene.binding_key(scene_snapshot)
    return result
end

function BoneProbe.lines(snapshot)
    local lines = {
        "skeletalMeshComponents=" .. tostring(snapshot.component_count),
        "matchingComponents=" .. tostring(#snapshot.matches),
        "scene=" .. tostring(snapshot.scene_key or "<unknown>"),
    }
    for _, error_text in ipairs(snapshot.errors) do
        table.insert(lines, "error." .. error_text)
    end
    for index, match in ipairs(snapshot.matches) do
        local prefix = string.format("match[%d]", index)
        table.insert(lines, prefix .. ".component=" .. tostring(match.name))
        table.insert(lines, prefix .. ".class=" .. tostring(match.class))
        table.insert(lines, prefix .. ".role=" .. tostring(match.role))
        table.insert(lines, prefix .. ".catalog=" .. tostring(match.catalog))
        table.insert(lines, prefix .. ".binding=" .. tostring(match.binding and match.binding.method))
        if match.error ~= nil then
            table.insert(lines, prefix .. ".error=" .. tostring(match.error))
        end
        for bone_name, bone in pairs(match.bones) do
            local p = bone.position
            local q = bone.rotation
            table.insert(lines, prefix .. ".bone." .. bone_name .. "=" .. string.format(
                "P=(%.3f,%.3f,%.3f) Q=(%.6f,%.6f,%.6f,%.6f)",
                p[1], p[2], p[3], q[1], q[2], q[3], q[4]
            ))
        end
    end
    return lines
end

return BoneProbe
