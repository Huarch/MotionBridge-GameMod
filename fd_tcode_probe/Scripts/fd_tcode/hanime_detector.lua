local Config = require("fd_tcode.config")
local HScene = require("fd_tcode.hscene")
local IdentityData = require("fd_tcode.hanime_identity_data")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

local HAnimeDetector = {
    components = {},
    samples_until_discovery = 0,
    candidate_id = nil,
    candidate_frames = 0,
    active = nil,
    empty_frames = 0,
    scene_samples_until_refresh = 0,
    scene_state = nil,
}

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function participant_slot(participant_tag)
    local raw_tag = string.lower(tostring(participant_tag or ""))
    return string.match(raw_tag, "[_%-]([abc])[_%-]?%d*$")
        or string.match(raw_tag, "[_%-]([abc])$")
        or "generic"
end

local function participant_base(participant_tag)
    local raw_tag = string.lower(tostring(participant_tag or ""))
    raw_tag = string.gsub(raw_tag, "[_%-][abc][_%-%d]*$", "")
    raw_tag = string.gsub(raw_tag, "[_%-]%d+$", "")
    return normalized(raw_tag)
end

local function build_family_catalog_roles()
    local families = {}
    for _, identity in pairs(IdentityData.by_montage or {}) do
        local hanime_id = tostring(identity.hanime_id or "")
        local role = SkeletonCatalog.role_for_participant_tag(identity.participant_tag)
        if hanime_id ~= "" and role ~= nil then
            local family = families[hanime_id]
            if family == nil then
                family = {}
                families[hanime_id] = family
            end
            local role_slots = family[role]
            if role_slots == nil then
                role_slots = { generic = false, named = {}, first_position = nil }
                family[role] = role_slots
            end
            local position = string.find(
                normalized(hanime_id),
                participant_base(identity.participant_tag),
                1,
                true
            )
            if position ~= nil
                and (role_slots.first_position == nil or position < role_slots.first_position)
            then
                role_slots.first_position = position
            end

            -- TableHAnim contains aliases such as Male and Male_A_01 for one
            -- participant. Count explicit A/B/C slots when present; otherwise
            -- all aliases for a catalog role represent one generic slot.
            local slot = participant_slot(identity.participant_tag)
            if slot ~= "generic" then
                role_slots.named[slot] = true
            else
                role_slots.generic = true
            end
        end
    end

    local result = {}
    local slot_result = {}
    local priority_result = {}
    for hanime_id, family in pairs(families) do
        local roles = {}
        local role_slots_result = {}
        result[hanime_id] = roles
        slot_result[hanime_id] = role_slots_result
        local ordered_roles = {}
        priority_result[hanime_id] = {}
        for role, slots in pairs(family) do
            local ordered_slots = {}
            for _, slot in ipairs({ "a", "b", "c" }) do
                if slots.named[slot] then
                    table.insert(ordered_slots, slot)
                end
            end
            if #ordered_slots == 0 and slots.generic then
                table.insert(ordered_slots, "generic")
            end
            role_slots_result[role] = ordered_slots
            roles[role] = #ordered_slots
            table.insert(ordered_roles, {
                role = role,
                position = slots.first_position or 1000000,
            })
        end
        table.sort(ordered_roles, function(a, b)
            if a.position == b.position then
                return a.role < b.role
            end
            return a.position < b.position
        end)
        for index, item in ipairs(ordered_roles) do
            priority_result[hanime_id][item.role] = index - 1
        end
    end
    return result, slot_result, priority_result
end

local family_catalog_roles, family_catalog_slots, family_catalog_priorities = build_family_catalog_roles()

local function slot_priority(slots, wanted_slot)
    for index, slot in ipairs(slots or {}) do
        if slot == wanted_slot then
            return index - 1
        end
    end
    return nil
end

local function montage_asset_name(full_name)
    local text = tostring(full_name or "")
    local object_path = string.match(text, "([^%s]+)$") or text
    return string.match(object_path, "%.([^%.:]+)$")
        or string.match(object_path, "([^/]+)$")
        or object_path
end

local function component_is_live(component)
    if not Safe.is_object(component) then
        return false
    end
    local registered_ok, registered = pcall(function()
        return component:IsRegistered()
    end)
    if registered_ok and registered == false then
        return false
    end
    local visible_ok, visible = pcall(function()
        return component:IsVisible()
    end)
    if visible_ok and visible == false then
        return false
    end
    return true
end

local function discover_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        HAnimeDetector.components = {}
        return false, tostring(values or "FindAllOf returned nil")
    end
    local result = {}
    for _, component in pairs(values) do
        if component_is_live(component) then
            local _, entry = SkeletonCatalog.match_component(component)
            if entry ~= nil and SkeletonCatalog.is_primary_component(component, entry) then
                table.insert(result, component)
            end
        end
    end
    table.sort(result, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
    HAnimeDetector.components = result
    HAnimeDetector.samples_until_discovery = math.max(
        1,
        math.floor(Config.hanime_discovery_retry_ms / Config.hanime_poll_interval_ms)
    )
    return true, nil
end

local function ensure_components()
    HAnimeDetector.samples_until_discovery = HAnimeDetector.samples_until_discovery - 1
    local has_live = false
    for _, component in ipairs(HAnimeDetector.components) do
        if component_is_live(component) then
            has_live = true
            break
        end
    end
    if HAnimeDetector.samples_until_discovery <= 0 or not has_live then
        return discover_components()
    end
    return true, nil
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
    return Safe.object_name(montage)
end

local function scene_state()
    HAnimeDetector.scene_samples_until_refresh = HAnimeDetector.scene_samples_until_refresh - 1
    if HAnimeDetector.scene_state ~= nil and HAnimeDetector.scene_samples_until_refresh > 0 then
        return HAnimeDetector.scene_state
    end

    local snapshot = HScene.snapshot()
    local values = snapshot.animation_values or {}
    HAnimeDetector.scene_state = {
        valid = snapshot.valid == true,
        manager = snapshot.manager_name,
        anim_manager = snapshot.anim_manager_name,
        anim_id = values.AnimID,
        current_state = values.CurrentState or values.AnimState,
        current_animation = values.CurrentAnimation,
        current_montage = values.CurrentMontage,
        current_section = values.CurrentSection,
    }
    HAnimeDetector.scene_samples_until_refresh = math.max(
        1,
        math.floor(Config.hanime_scene_refresh_ms / Config.hanime_poll_interval_ms)
    )
    return HAnimeDetector.scene_state
end

local function select_identity(matches)
    local groups = {}
    for _, match in ipairs(matches) do
        local id = tostring(match.identity.hanime_id)
        local group = groups[id]
        if group == nil then
            group = { count = 0, representative = match, components = {}, matches = {} }
            groups[id] = group
        end
        group.count = group.count + 1
        table.insert(group.components, match.component)
        table.insert(group.matches, match)
        if group.representative.identity.phase ~= "normal" and match.identity.phase == "normal" then
            group.representative = match
        end
    end

    local best_id = nil
    local best = nil
    for id, group in pairs(groups) do
        if best == nil or group.count > best.count or (group.count == best.count and id < best_id) then
            best_id = id
            best = group
        end
    end
    if best == nil then
        return nil
    end

    local selected = {}
    for key, value in pairs(best.representative.identity) do
        selected[key] = value
    end
    selected.hanime_id = best_id
    selected.active_participant_montages = best.count
    selected.montage_full_name = best.representative.full_name
    selected.recognition_source = "table_hanim_exact_active_montage"
    selected.expected_catalog_roles = family_catalog_roles[best_id] or {}
    selected.expected_catalog_slots = family_catalog_slots[best_id] or {}
    selected.expected_catalog_priorities = family_catalog_priorities[best_id] or {}
    -- Runtime-only UObject references. They never enter the wire payload; the
    -- generic skeleton probe uses them to avoid another global enumeration.
    selected.matched_components = best.components
    selected.matched_participants = best.matches
    return selected
end

local function observe()
    local current_scene_state = scene_state()
    local ready, discovery_error = ensure_components()
    if not ready then
        return nil, {
            montage_count = 0,
            unknown_montage_count = 0,
            reason = "component_discovery_failed: " .. tostring(discovery_error),
            scene_state = current_scene_state,
        }
    end

    local matches = {}
    local montage_count = 0
    local unknown_montage_count = 0
    local unknown_assets = {}
    for _, component in ipairs(HAnimeDetector.components) do
        local full_name = active_montage(component)
        if full_name ~= nil then
            montage_count = montage_count + 1
            local asset = montage_asset_name(full_name)
            local identity = IdentityData.by_montage[normalized(asset)]
            if identity ~= nil then
                table.insert(matches, {
                    identity = identity,
                    full_name = full_name,
                    component = component,
                })
            else
                unknown_montage_count = unknown_montage_count + 1
                if #unknown_assets < 8 then
                    table.insert(unknown_assets, asset)
                end
            end
        end
    end

    local selected = select_identity(matches)
    if selected ~= nil then
        -- The exact active Montage opens the HAnime gate. The authoritative
        -- unpacked family then supplies the known participant skeleton roles,
        -- including partners whose animation is running through an AnimBP
        -- state machine rather than an active Montage.
        local participant_components = {}
        local participant_bindings = {}
        local seen = {}
        local role_counts = {}
        local used_priorities = {}
        for _, match in ipairs(selected.matched_participants or {}) do
            local component = match.component
            local name = Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(participant_components, component)
                local role = SkeletonCatalog.match_component(component)
                if role ~= nil then
                    role_counts[role] = (role_counts[role] or 0) + 1
                    local slot = participant_slot(match.identity.participant_tag)
                    local local_priority = slot_priority(selected.expected_catalog_slots[role], slot)
                        or (role_counts[role] - 1)
                    used_priorities[role] = used_priorities[role] or {}
                    used_priorities[role][local_priority] = true
                    local role_priority = selected.expected_catalog_priorities[role] or 0
                    table.insert(participant_bindings, {
                        component = component,
                        participant_tag = match.identity.participant_tag,
                        participant_slot = slot,
                        participant_priority = role_priority * 16 + local_priority,
                    })
                end
            end
        end
        for _, component in ipairs(HAnimeDetector.components) do
            local name = Safe.object_name(component)
            local role = SkeletonCatalog.match_component(component)
            local expected_count = role ~= nil
                and (selected.expected_catalog_roles[role] or 0)
                or 0
            if name ~= nil
                and not seen[name]
                and role ~= nil
                and (role_counts[role] or 0) < expected_count
            then
                seen[name] = true
                table.insert(participant_components, component)
                role_counts[role] = (role_counts[role] or 0) + 1
                local local_priority = 0
                used_priorities[role] = used_priorities[role] or {}
                while used_priorities[role][local_priority] do
                    local_priority = local_priority + 1
                end
                used_priorities[role][local_priority] = true
                local slots = selected.expected_catalog_slots[role] or {}
                local role_priority = selected.expected_catalog_priorities[role] or 0
                table.insert(participant_bindings, {
                    component = component,
                    participant_tag = role .. "_" .. tostring(local_priority + 1),
                    participant_slot = slots[local_priority + 1] or "generic",
                    participant_priority = role_priority * 16 + local_priority,
                })
            end
        end
        selected.participant_components = participant_components
        selected.participant_bindings = participant_bindings
    end

    return selected, {
        montage_count = montage_count,
        matched_montage_count = #matches,
        unknown_montage_count = unknown_montage_count,
        unknown_assets = unknown_assets,
        scene_state = current_scene_state,
    }
end

local function status(state, active, observation, reason)
    return {
        state = state,
        active = active == true,
        identity = active and HAnimeDetector.active or nil,
        reason = reason,
        montage_count = observation.montage_count or 0,
        matched_montage_count = observation.matched_montage_count or 0,
        unknown_montage_count = observation.unknown_montage_count or 0,
        unknown_assets = observation.unknown_assets or {},
        scene_state = observation.scene_state or {},
    }
end

function HAnimeDetector.sample()
    local observed, observation = observe()
    if observed ~= nil then
        HAnimeDetector.empty_frames = 0
        if HAnimeDetector.active ~= nil and HAnimeDetector.active.hanime_id == observed.hanime_id then
            HAnimeDetector.active = observed
            HAnimeDetector.candidate_id = observed.hanime_id
            HAnimeDetector.candidate_frames = Config.hanime_confirm_frames
            return status("active", true, observation, nil)
        end

        if HAnimeDetector.candidate_id == observed.hanime_id then
            HAnimeDetector.candidate_frames = HAnimeDetector.candidate_frames + 1
        else
            HAnimeDetector.candidate_id = observed.hanime_id
            HAnimeDetector.candidate_frames = 1
        end
        HAnimeDetector.active = nil
        if HAnimeDetector.candidate_frames >= Config.hanime_confirm_frames then
            HAnimeDetector.active = observed
            return status("active", true, observation, nil)
        end
        return status("acquiring", false, observation, "candidate_not_stable")
    end

    HAnimeDetector.candidate_id = nil
    HAnimeDetector.candidate_frames = 0
    if observation.montage_count > 0 then
        -- An explicit active Montage that is absent from TableHAnim is idle,
        -- transition, UI, or otherwise non-HAnime. Release immediately.
        HAnimeDetector.active = nil
        HAnimeDetector.empty_frames = 0
        return status("inactive", false, observation, "active_montage_not_in_table_hanim")
    end

    HAnimeDetector.empty_frames = HAnimeDetector.empty_frames + 1
    if HAnimeDetector.active ~= nil and HAnimeDetector.empty_frames <= Config.hanime_empty_hold_frames then
        return status("holding", true, observation, "short_montage_gap")
    end
    HAnimeDetector.active = nil
    return status("inactive", false, observation, "no_active_hanime_montage")
end

function HAnimeDetector.clear_cache()
    HAnimeDetector.components = {}
    HAnimeDetector.samples_until_discovery = 0
    HAnimeDetector.candidate_id = nil
    HAnimeDetector.candidate_frames = 0
    HAnimeDetector.active = nil
    HAnimeDetector.empty_frames = 0
    HAnimeDetector.scene_samples_until_refresh = 0
    HAnimeDetector.scene_state = nil
end

return HAnimeDetector
