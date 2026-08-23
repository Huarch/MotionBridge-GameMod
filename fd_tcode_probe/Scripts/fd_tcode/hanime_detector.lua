local Config = require("fd_tcode.config")
local IdentityData = require("fd_tcode.hanime_identity_catalog")
local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

local HAnimeDetector = {
    components = {},
    component_metadata = {},
    candidate_id = nil,
    candidate_frames = 0,
    active = nil,
    empty_frames = 0,
    reentry_recovery_armed = false,
    reentry_signal_frames = 0,
    pending_components = {},
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
    local function add_participant(hanime_id, participant_tag)
        hanime_id = tostring(hanime_id or "")
        local role = SkeletonCatalog.role_for_participant_tag(participant_tag)
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
                participant_base(participant_tag),
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
            local slot = participant_slot(participant_tag)
            if slot ~= "generic" then
                role_slots.named[slot] = true
            else
                role_slots.generic = true
            end
        end
    end

    for _, identity in pairs(IdentityData.by_montage or {}) do
        add_participant(identity.hanime_id, identity.participant_tag)
    end
    for hanime_id, metadata in pairs(IdentityData.by_family or {}) do
        for _, participant_tag in ipairs(metadata.participant_tags or {}) do
            add_participant(hanime_id, participant_tag)
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

local function unknown_assets_indicate_hanime_reentry(assets)
    for _, asset in ipairs(assets or {}) do
        local text = string.lower(tostring(asset or ""))
        -- TableHAnim does not contain facial-expression Montages, but the
        -- unpacked/runtime naming convention distinguishes room idle from an
        -- HAnime entry/loop. Idle expressions must never consume recovery:
        -- the new participant component may not exist until Exp_In begins.
        if string.find(text, "exp_in_", 1, true)
            or string.find(text, "exp_sexing_", 1, true)
        then
            return true
        end
    end
    return false
end

local function unknown_assets_indicate_active_hanime(assets)
    for _, asset in ipairs(assets or {}) do
        local text = string.lower(tostring(asset or ""))
        -- In the Demo VR build, switching camera perspective can hide the
        -- exact body Montage from GetCurrentActiveMontage while the facial
        -- expression remains in its Sexing loop.  This is different from
        -- Exp_In/Exp_Out/Exp_Idle and is safe evidence that the previously
        -- confirmed HAnime is still running.
        if string.find(text, "exp_sexing_", 1, true) then
            return true
        end
    end
    return false
end

local function identity_components_are_registered(identity)
    local bindings = identity and identity.participant_bindings or {}
    if #bindings == 0 then
        return false
    end
    for _, binding in ipairs(bindings) do
        local component = binding.component
        if not Safe.is_object(component) then
            return false
        end
        local registered_ok, registered = pcall(function()
            return component:IsRegistered()
        end)
        if registered_ok and registered == false then
            return false
        end
    end
    return true
end

local function identity_has_hidden_component(identity)
    local bindings = identity and identity.participant_bindings or {}
    for _, binding in ipairs(bindings) do
        local component = binding.component
        if Safe.is_object(component) then
            local visible_ok, visible = pcall(function()
                return component:IsVisible()
            end)
            if visible_ok and visible == false then
                return true
            end
        end
    end
    return false
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
    -- Rendering visibility is not object lifetime.  Fallen Doll deliberately
    -- hides body meshes in VR first-person and in the "genitals only" display
    -- modes while their AnimInstance and socket transforms remain usable.
    -- Rejecting hidden components stopped the HAnime stream and also forced a
    -- costly rediscovery every poll.  Registration is the stable lifetime
    -- signal used by the realtime bone reader as well.
    return true
end

local function discover_components()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        HAnimeDetector.components = {}
        return false, tostring(values or "FindAllOf returned nil")
    end
    local result = {}
    local metadata = {}
    for _, component in pairs(values) do
        if component_is_live(component) then
            local role, entry = SkeletonCatalog.match_component(component)
            if entry ~= nil and SkeletonCatalog.is_primary_component(component, entry) then
                table.insert(result, component)
                metadata[component] = {
                    role = role,
                    entry = entry,
                    name = Safe.object_name(component),
                }
            end
        end
    end
    table.sort(result, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
    HAnimeDetector.components = result
    HAnimeDetector.component_metadata = metadata
    return true, nil
end

local function merge_pending_components()
    if #HAnimeDetector.pending_components == 0 then
        return
    end
    local pending = HAnimeDetector.pending_components
    HAnimeDetector.pending_components = {}
    local seen = {}
    for _, component in ipairs(HAnimeDetector.components) do
        local name = Safe.object_name(component)
        if name ~= nil then
            seen[name] = true
        end
    end
    for _, component in ipairs(pending) do
        if Safe.is_object(component) then
            local registered_ok, registered = pcall(function()
                return component:IsRegistered()
            end)
            if registered_ok and registered == false then
                -- Object construction may precede component registration.
                -- Retain this event payload until it becomes usable.
                table.insert(HAnimeDetector.pending_components, component)
            else
                local role, entry = SkeletonCatalog.match_component(component)
                local name = Safe.object_name(component)
                if entry ~= nil
                    and name ~= nil
                    and not seen[name]
                    and SkeletonCatalog.is_primary_component(component, entry)
                then
                    seen[name] = true
                    table.insert(HAnimeDetector.components, component)
                    HAnimeDetector.component_metadata[component] = {
                        role = role,
                        entry = entry,
                        name = name,
                    }
                end
            end
        end
    end
    table.sort(HAnimeDetector.components, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
end

local function ensure_components()
    merge_pending_components()
    if #HAnimeDetector.components == 0 then
        return discover_components()
    end
    for _, component in ipairs(HAnimeDetector.components) do
        if not component_is_live(component) then
            -- Scene changes invalidate the cache and trigger one discovery.
            -- A healthy cache must never cause periodic global enumeration:
            -- FindAllOf stalls the game thread and disturbs secondary physics.
            return discover_components()
        end
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

local function observe(allow_recovery)
    -- Exact active Montage identity is sufficient for the realtime gate. HScene
    -- snapshots remain available through explicit diagnostics, but are not
    -- used here because one snapshot performs multiple global searches.
    local current_scene_state = {}
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
        -- A healthy exact match arms one future recovery. Some action changes
        -- leave the old visible component alive with only an expression
        -- Montage while the new HAnime component is created elsewhere. The
        -- old cache therefore still looks valid and would otherwise remain
        -- stuck until the stream cache is rebuilt.
        HAnimeDetector.reentry_recovery_armed = true
        HAnimeDetector.reentry_signal_frames = 0
    elseif allow_recovery ~= false
        and HAnimeDetector.reentry_recovery_armed
        and unknown_montage_count > 0
        and unknown_assets_indicate_hanime_reentry(unknown_assets)
    then
        HAnimeDetector.reentry_signal_frames = HAnimeDetector.reentry_signal_frames + 1
        if HAnimeDetector.reentry_signal_frames >= Config.hanime_reentry_confirm_frames then
            HAnimeDetector.reentry_recovery_armed = false
            HAnimeDetector.reentry_signal_frames = 0
            local recovered, recovery_error = discover_components()
            if recovered then
                Log.info("HAnime component cache rediscovered on HAnime re-entry expression")
                return observe(false)
            end
            Log.warn("HAnime component cache rediscovery failed: " .. tostring(recovery_error))
        end
    else
        -- Keep recovery armed across the complete idle period. Exp_Idle and
        -- no-Montage gaps are not evidence that a new HAnime component exists.
        HAnimeDetector.reentry_signal_frames = 0
    end
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
            local metadata = HAnimeDetector.component_metadata[component]
            local name = metadata and metadata.name or Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(participant_components, component)
                local role = metadata and metadata.role or nil
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
                        component_name = name,
                        catalog_role = role,
                        catalog_entry = metadata.entry,
                        participant_tag = match.identity.participant_tag,
                        participant_slot = slot,
                        participant_priority = role_priority * 16 + local_priority,
                    })
                end
            end
        end
        for _, component in ipairs(HAnimeDetector.components) do
            local metadata = HAnimeDetector.component_metadata[component]
            local name = metadata and metadata.name or Safe.object_name(component)
            local role = metadata and metadata.role or nil
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
                    component_name = name,
                    catalog_role = role,
                    catalog_entry = metadata.entry,
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
        if HAnimeDetector.candidate_frames >= Config.hanime_confirm_frames then
            HAnimeDetector.active = observed
            return status("active", true, observation, nil)
        end
        if HAnimeDetector.active ~= nil
            and identity_components_are_registered(HAnimeDetector.active)
        then
            -- A different exact HAnime must remain stable for several polls
            -- before it replaces the current binding. Keep streaming the old
            -- live skeletons during that short confirmation window so an
            -- ordinary pose switch cannot look like a transport dropout and
            -- trigger the device safety return-to-center path.
            return status("holding", true, observation, "candidate_switch_hold")
        end
        return status("acquiring", false, observation, "candidate_not_stable")
    end

    HAnimeDetector.candidate_id = nil
    HAnimeDetector.candidate_frames = 0
    if observation.montage_count > 0 then
        if HAnimeDetector.active ~= nil
            and unknown_assets_indicate_active_hanime(observation.unknown_assets)
            and identity_components_are_registered(HAnimeDetector.active)
        then
            -- Preserve the exact identity and UObject bindings across the VR
            -- first-person camera swap.  Bone transforms remain live on the
            -- registered components even though their exact Montage is no
            -- longer exposed.  A subsequent Idle/In/Out expression, scene
            -- change, or invalid component still releases the gate normally.
            HAnimeDetector.empty_frames = 0
            return status("holding", true, observation, "sexing_expression_hold")
        end
        -- An explicit active Montage that is absent from TableHAnim is idle,
        -- transition, UI, or otherwise non-HAnime. Release immediately.
        HAnimeDetector.active = nil
        HAnimeDetector.empty_frames = 0
        return status("inactive", false, observation, "active_montage_not_in_table_hanim")
    end

    HAnimeDetector.empty_frames = HAnimeDetector.empty_frames + 1
    if HAnimeDetector.active ~= nil
        and identity_components_are_registered(HAnimeDetector.active)
        and identity_has_hidden_component(HAnimeDetector.active)
    then
        -- Playtest VR display filters can hide the full participant meshes (or
        -- leave only genital meshes visible).  In that mode every body and
        -- expression Montage disappears from GetCurrentActiveMontage even
        -- though the registered skeletons keep animating.  Preserve the last
        -- exact TableHAnim identity until the meshes are shown again, an
        -- explicit non-HAnime Montage appears, or the components are removed.
        HAnimeDetector.empty_frames = 0
        return status("holding", true, observation, "hidden_participant_montage_suppressed")
    end
    if HAnimeDetector.active ~= nil and HAnimeDetector.empty_frames <= Config.hanime_empty_hold_frames then
        return status("holding", true, observation, "short_montage_gap")
    end
    HAnimeDetector.active = nil
    return status("inactive", false, observation, "no_active_hanime_montage")
end

function HAnimeDetector.clear_cache()
    HAnimeDetector.components = {}
    HAnimeDetector.component_metadata = {}
    HAnimeDetector.candidate_id = nil
    HAnimeDetector.candidate_frames = 0
    HAnimeDetector.active = nil
    HAnimeDetector.empty_frames = 0
    -- The automatic stream may start while the room is already idle. Arm the first
    -- Exp_In/Exp_Sexing transition as well as transitions after an HAnime that
    -- was observed during this run.
    HAnimeDetector.reentry_recovery_armed = true
    HAnimeDetector.reentry_signal_frames = 0
    HAnimeDetector.pending_components = {}
end

function HAnimeDetector.queue_component(component)
    -- NotifyOnNewObject/Montage_Play callbacks provide the concrete component.
    -- Inspection is deferred to the regular game-thread sampling path.
    table.insert(HAnimeDetector.pending_components, component)
end

return HAnimeDetector
