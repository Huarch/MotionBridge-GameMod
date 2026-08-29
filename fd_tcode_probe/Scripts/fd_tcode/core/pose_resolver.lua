local ProfileStore = require("fd_tcode.core.profile_store")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local PoseResolver = {}

local primary_catalog_patterns = {
    { pattern = "charactersalet", id = "alet-humanoid", name = "Alet" },
    { pattern = "charactersanya", id = "anya-humanoid", name = "Anya" },
    { pattern = "characterseirka", id = "erika-humanoid", name = "Erika" },
    { pattern = "characterserika", id = "erika-humanoid", name = "Erika" },
    { pattern = "charactersgalatea", id = "galatea-humanoid", name = "Galatea" },
    { pattern = "charactersjuzhi", id = "juzi-humanoid", name = "Juzi" },
    { pattern = "charactersjuzi", id = "juzi-humanoid", name = "Juzi" },
    { pattern = "charactersyanshi", id = "yanshi-humanoid", name = "yanshi" },
}

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function append_signal(signals, seen, source, value)
    local text = tostring(value or "")
    local key = normalized(text)
    if key == "" or seen[key] then
        return
    end
    seen[key] = true
    table.insert(signals, {
        source = source,
        text = text,
        normalized = key,
    })
end

local function append_table_signals(signals, seen, source_prefix, values)
    for key, value in pairs(values or {}) do
        append_signal(signals, seen, source_prefix .. "." .. tostring(key), value)
    end
end

local function active_montage_name(component)
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
    return Safe.object_name(montage)
end

local function discover_known_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        return {}
    end
    local components = {}
    for _, component in pairs(values) do
        if Safe.is_object(component) then
            local _, entry = SkeletonCatalog.match_component(component)
            if entry ~= nil then
                table.insert(components, component)
            end
        end
    end
    return components
end

function PoseResolver.signals(scene_snapshot, known_components)
    local signals = {}
    local seen = {}
    if scene_snapshot and scene_snapshot.valid then
        append_table_signals(signals, seen, "animation", scene_snapshot.animation_values)
        append_table_signals(signals, seen, "manager", scene_snapshot.manager_values)
    end

    local components = known_components or discover_known_components()
    for _, component in ipairs(components) do
        local montage_name = active_montage_name(component)
        if montage_name ~= nil then
            append_signal(signals, seen, "montage", montage_name)
        end
    end
    return signals
end

local function signal_asset_name(text)
    local tail = string.match(text or "", "([^%./:]+)$") or tostring(text or "")
    tail = string.gsub(tail, "_[Mm][Oo][Nn][Tt][Aa][Gg][Ee].*$", "")
    return tail
end

local function infer_primary(signal)
    for _, candidate in ipairs(primary_catalog_patterns) do
        if string.find(signal.normalized, candidate.pattern, 1, true) then
            return candidate
        end
    end
    local asset = normalized(signal_asset_name(signal.text))
    local asset_prefixes = {
        { prefix = "alet", id = "alet-humanoid", name = "Alet" },
        { prefix = "anya", id = "anya-humanoid", name = "Anya" },
        { prefix = "erika", id = "erika-humanoid", name = "Erika" },
        { prefix = "galatea", id = "galatea-humanoid", name = "Galatea" },
        { prefix = "juzi", id = "juzi-humanoid", name = "Juzi" },
        { prefix = "yanshi", id = "yanshi-humanoid", name = "yanshi" },
    }
    for _, candidate in ipairs(asset_prefixes) do
        if string.sub(asset, 1, #candidate.prefix) == candidate.prefix then
            return candidate
        end
    end
    return nil
end

local function contains_any(value, patterns)
    for _, pattern in ipairs(patterns) do
        if string.find(value, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function infer_family(signal)
    local primary = infer_primary(signal)
    if primary == nil then
        return nil
    end

    local value = signal.normalized
    local contact_kinds = 0
    local has_hand = string.find(value, "hand", 1, true) ~= nil
    local has_foot = string.find(value, "foot", 1, true) ~= nil
    local has_mouth = contains_any(value, { "mouth", "oral" })
    local has_anal = contains_any(value, { "anal", "anus", "arse" })
    local has_vaginal = contains_any(value, { "vaginal", "vagina" })
    for _, present in ipairs({ has_hand, has_foot, has_mouth, has_anal, has_vaginal }) do
        if present then
            contact_kinds = contact_kinds + 1
        end
    end

    local category = nil
    local target_semantic = nil
    if contact_kinds == 1 and has_hand then
        category = "hand_guided"
        target_semantic = "hand_nearest_reference"
    elseif contact_kinds == 1 and has_foot then
        category = "foot_guided"
        target_semantic = "foot_nearest_reference"
    elseif contact_kinds == 1 and has_mouth then
        category = "mouth_guided"
        target_semantic = "mouth_origin"
    elseif contact_kinds == 1 and has_anal then
        category = "penetration"
        target_semantic = "anal_origin"
    elseif contact_kinds == 1 and has_vaginal then
        category = "penetration"
        target_semantic = "vaginal_origin"
    elseif contains_any(value, { "dildo", "sex" }) then
        category = contains_any(value, { "dildo" }) and "prop_guided" or "generic_pair"
    end
    if category == nil then
        return nil
    end

    local has_male = contains_any(value, { "male", "dreamer" })
    local is_multi = contains_any(value, { "maleab", "dreamerab" }) or contact_kinds > 1
    local profile = {
        id = signal_asset_name(signal.text),
        category = category,
        participant_hint = has_male and (is_multi and "MaleAB" or "Male") or "unverified",
        roles = {
            primary = primary.id,
        },
        match_origin = "inferred_animation_family",
    }
    if has_male and not is_multi then
        profile.roles.partner = "male-b-humanoid"
    end

    if profile.roles.partner ~= nil and target_semantic ~= nil then
        profile.status = "enabled_for_simulation_validation"
        profile.geometry = {
            reference_role = "partner",
            reference_origin_semantic = "primary_origin",
            reference_tip_semantic = "primary_tip",
            target_role = "primary",
            target_semantic = target_semantic,
            max_pair_distance_cm = 100,
        }
    elseif is_multi then
        profile.status = "awaiting_multi_participant_binding"
    elseif has_male then
        profile.status = "catalog_match_only"
    else
        profile.status = "awaiting_partner_skeleton"
    end
    return profile, primary
end

function PoseResolver.resolve_signals(signals)
    local data, generation = ProfileStore.current()
    local best_profile = nil
    local best_signal = nil
    local best_key = nil
    local best_length = -1

    for _, profile in pairs(data.profiles or {}) do
        for _, match_key in ipairs(profile.match_keys or {}) do
            local normalized_key = normalized(match_key)
            if normalized_key ~= "" then
                for _, signal in ipairs(signals or {}) do
                    if string.find(signal.normalized, normalized_key, 1, true)
                        and #normalized_key > best_length then
                        best_profile = profile
                        best_signal = signal
                        best_key = match_key
                        best_length = #normalized_key
                    end
                end
            end
        end
    end

    if best_profile == nil then
        for _, signal in ipairs(signals or {}) do
            local inferred, primary = infer_family(signal)
            if inferred ~= nil then
                return inferred, {
                    profile_generation = generation,
                    match_key = inferred.id,
                    signal_source = signal.source,
                    signal_text = signal.text,
                    signals = signals,
                    inferred = true,
                    primary_name = primary.name,
                }
            end
        end
        return nil, {
            profile_generation = generation,
            reason = #signals == 0 and "no animation identity is exposed" or "animation is not in pose catalog",
            signals = signals,
        }
    end
    return best_profile, {
        profile_generation = generation,
        match_key = best_key,
        signal_source = best_signal.source,
        signal_text = best_signal.text,
        signals = signals,
    }
end

function PoseResolver.resolve(scene_snapshot, known_components)
    return PoseResolver.resolve_signals(PoseResolver.signals(scene_snapshot, known_components))
end

function PoseResolver.lines(profile, resolution)
    if profile == nil then
        return {
            "pose=<unmapped>",
            "poseReason=" .. tostring(resolution and resolution.reason or "unknown"),
            "poseSignals=" .. tostring(resolution and resolution.signals and #resolution.signals or 0),
        }
    end
    local partner_catalog = profile.roles and profile.roles.partner
    return {
        "pose=" .. tostring(profile.id),
        "poseCategory=" .. tostring(profile.category),
        "poseStatus=" .. tostring(profile.status),
        "poseMatchOrigin=" .. tostring(profile.match_origin or "exact_pose_catalog"),
        "posePrimaryCatalog=" .. tostring(profile.roles and profile.roles.primary or "<none>"),
        "posePartnerCatalog=" .. tostring(partner_catalog or "<unverified>"),
        "posePartnerCatalogLoaded=" .. tostring(partner_catalog ~= nil and SkeletonCatalog.get(partner_catalog) ~= nil),
        "poseMatch=" .. tostring(resolution and resolution.signal_source or "<unknown>")
            .. ":" .. tostring(resolution and resolution.match_key or "<unknown>"),
    }
end

return PoseResolver
