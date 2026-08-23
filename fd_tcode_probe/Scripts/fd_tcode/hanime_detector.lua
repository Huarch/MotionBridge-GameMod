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
            if entry ~= nil then
                table.insert(result, component)
            end
        end
    end
    HAnimeDetector.components = result
    HAnimeDetector.samples_until_discovery = math.max(
        1,
        math.floor(Config.hanime_discovery_retry_ms / Config.skeleton_sample_interval_ms)
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
        math.floor(Config.hanime_scene_refresh_ms / Config.skeleton_sample_interval_ms)
    )
    return HAnimeDetector.scene_state
end

local function select_identity(matches)
    local groups = {}
    for _, match in ipairs(matches) do
        local id = tostring(match.identity.hanime_id)
        local group = groups[id]
        if group == nil then
            group = { count = 0, representative = match, components = {} }
            groups[id] = group
        end
        group.count = group.count + 1
        table.insert(group.components, match.component)
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
    -- Runtime-only UObject references. They never enter the wire payload; the
    -- generic skeleton probe uses them to avoid another global enumeration.
    selected.matched_components = best.components
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
        -- Only exact identity owners are carried forward. Other room actors
        -- can have unrelated active Montages and are not participants merely
        -- because a HAnime is visible.
        selected.montage_components = selected.matched_components
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
