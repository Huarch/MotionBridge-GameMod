local Config = require("fd_tcode.config")
local ComponentRegistry = require("fd_tcode.hanime_component_registry")
local HSystemState = require("fd_tcode.hanime_hsystem_state")
local IdentityResolver = require("fd_tcode.hanime_identity_resolver")
local MotionContract = require("fd_tcode.hanime_motion_contract")
local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")
local HAnimeDetector = {
    candidate_id = nil,
    candidate_frames = 0,
    active = nil,
    empty_frames = 0,
    -- The first HAnime after a fresh Mod load may create its nonhuman
    -- participant after the initial component cache was built.  Treat the
    -- first verified Exp_In/Exp_Sexing transition exactly like later action
    -- re-entry, otherwise an initial nonhuman scene can never expose its
    -- companion Montage to the exact HAnime gate.
    reentry_recovery_armed = true,
    reentry_signal_frames = 0,
    contract_reference_rescan_attempts = {},
}

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

local function bind_exact_direct_reference(component, directory, participant_components, participant_bindings, seen, bound, priority)
    local name = Safe.object_name(component)
    if name == nil or seen[name] or bound[directory] then
        return false, priority
    end
    local role, entry, evidence = SkeletonCatalog.match_component_for_monster_directory(component, directory)
    if entry == nil or not SkeletonCatalog.is_primary_component(component, entry) then
        return false, priority
    end
    seen[name] = true
    bound[directory] = true
    table.insert(participant_components, component)
    table.insert(participant_bindings, {
        component = component,
        component_name = name,
        catalog_role = role,
        catalog_entry = entry,
        component_evidence = evidence,
        participant_tag = "direct_" .. string.lower(directory),
        participant_slot = "generic",
        participant_priority = 32 + priority,
    })
    return true, priority + 1
end

local function restricted_contract_reference_rescan(selected, directories)
    table.sort(directories)
    local signature = tostring(selected.hanime_id or "") .. "|" .. table.concat(directories, ",")
    if HAnimeDetector.contract_reference_rescan_attempts[signature] then
        return false, "already attempted for this exact HAnime"
    end
    HAnimeDetector.contract_reference_rescan_attempts[signature] = true
    return ComponentRegistry.rescan_directories(directories)
end

local function append_motion_contract_references(selected, participant_components, participant_bindings, seen)
    -- Some Demo TableHAnim rows expose only the primary character's Montage
    -- and omit their monster participant tag.  The direct profile is the
    -- authoritative companion declaration for these exact HAnime IDs.  Bind
    -- only a cached component whose verified SkinnedAsset catalog has the
    -- exact declared monster directory; never select a nearby mesh or probe
    -- arbitrary bones.
    local wanted = {}
    local directories = MotionContract.reference_directories(selected)
    for _, directory in ipairs(directories) do
        wanted[directory] = true
    end
    if #directories == 0 then
        return
    end
    local bound = {}
    local priority = 0
    for _, binding in ipairs(participant_bindings) do
        local entry = binding.catalog_entry
        local directory = entry and tostring(entry.monster_directory or "") or ""
        if wanted[directory] then
            bound[directory] = true
        end
    end
    local function bind_from_cache()
        for _, component in ipairs(ComponentRegistry.items()) do
            for _, directory in ipairs(directories) do
                if not bound[directory] then
                    local did_bind
                    did_bind, priority = bind_exact_direct_reference(
                        component, directory, participant_components, participant_bindings, seen, bound, priority
                    )
                    if did_bind then
                        break
                    end
                end
            end
        end
    end
    bind_from_cache()

    local missing = {}
    for _, directory in ipairs(directories) do
        if not bound[directory] then
            table.insert(missing, directory)
        end
    end
    if #missing > 0 then
        local refreshed, detail = restricted_contract_reference_rescan(selected, missing)
        if refreshed then
            Log.info(string.format(
                "motion contract reference rescan id=%s directories=%s added=%d",
                tostring(selected.hanime_id or "<none>"), table.concat(missing, ","), tonumber(detail) or 0
            ))
            bind_from_cache()
        else
            Log.warn(string.format(
                "motion contract reference rescan unavailable id=%s directories=%s reason=%s",
                tostring(selected.hanime_id or "<none>"), table.concat(missing, ","), tostring(detail)
            ))
        end
    end
    missing = {}
    for _, directory in ipairs(directories) do
        if not bound[directory] then
            table.insert(missing, directory)
        end
    end
    selected.motion_reference_missing = #missing > 0 and missing or nil
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
    selected.expected_catalog_roles = IdentityResolver.family_roles(best_id)
    selected.expected_catalog_slots = IdentityResolver.family_slots(best_id)
    selected.expected_catalog_priorities = IdentityResolver.family_priorities(best_id)
    -- Runtime-only UObject references. They never enter the wire payload; the
    -- generic skeleton probe uses them to avoid another global enumeration.
    selected.matched_components = best.components
    selected.matched_participants = best.matches
    return selected
end

local function observe(allow_recovery)
    -- HManager is discovered only at an HAnime entry/exact-match event. Once
    -- cached, this is a handful of property reads and performs no enumeration.
    local current_scene_state = HSystemState.read(false)
    local ready, discovery_error = ComponentRegistry.ensure()
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
    for _, component in ipairs(ComponentRegistry.items()) do
        local full_name = ComponentRegistry.active_montage(component)
        if full_name ~= nil then
            montage_count = montage_count + 1
            local asset = IdentityResolver.montage_asset_name(full_name)
            local identity = IdentityResolver.montage_identity(asset)
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
        -- Bind HManager once while exact TableHAnim evidence is available. Its
        -- exact AnimID then carries identity across body Montage/state-machine
        -- gaps without another global search.
        current_scene_state = HSystemState.read(true)
    elseif IdentityResolver.assets_indicate_active_hanime(unknown_assets) then
        current_scene_state = HSystemState.read(true)
        selected = IdentityResolver.hsystem_identity(current_scene_state)
    end
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
        and IdentityResolver.assets_indicate_reentry(unknown_assets)
    then
        HAnimeDetector.reentry_signal_frames = HAnimeDetector.reentry_signal_frames + 1
        if HAnimeDetector.reentry_signal_frames >= Config.hanime_reentry_confirm_frames then
            HAnimeDetector.reentry_recovery_armed = false
            HAnimeDetector.reentry_signal_frames = 0
            local recovered, recovery_error = ComponentRegistry.discover()
            if recovered then
                HSystemState.read(true)
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
            local metadata = ComponentRegistry.info(component)
            local name = metadata and metadata.name or Safe.object_name(component)
            if name ~= nil and not seen[name] then
                seen[name] = true
                table.insert(participant_components, component)
                local role = metadata and metadata.role or nil
                if role ~= nil then
                    role_counts[role] = (role_counts[role] or 0) + 1
                    local slot = IdentityResolver.participant_slot(match.identity.participant_tag)
                    local local_priority = IdentityResolver.slot_priority(selected.expected_catalog_slots[role], slot)
                        or (role_counts[role] - 1)
                    used_priorities[role] = used_priorities[role] or {}
                    used_priorities[role][local_priority] = true
                    local role_priority = selected.expected_catalog_priorities[role] or 0
                    table.insert(participant_bindings, {
                        component = component,
                        component_name = name,
                        catalog_role = role,
                        catalog_entry = metadata.entry,
                        component_evidence = metadata.evidence,
                        participant_tag = match.identity.participant_tag,
                        participant_slot = slot,
                        participant_priority = role_priority * 16 + local_priority,
                    })
                end
            end
        end
        for _, component in ipairs(ComponentRegistry.items()) do
            local metadata = ComponentRegistry.info(component)
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
                    component_evidence = metadata.evidence,
                    participant_tag = role .. "_" .. tostring(local_priority + 1),
                    participant_slot = slots[local_priority + 1] or "generic",
                    participant_priority = role_priority * 16 + local_priority,
                })
            end
        end
        append_motion_contract_references(selected, participant_components, participant_bindings, seen)
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
            and IdentityResolver.assets_indicate_active_hanime(observation.unknown_assets)
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
    ComponentRegistry.clear()
    HAnimeDetector.candidate_id = nil
    HAnimeDetector.candidate_frames = 0
    HAnimeDetector.active = nil
    HAnimeDetector.empty_frames = 0
    -- The automatic stream may start while the room is already idle. Arm the first
    -- Exp_In/Exp_Sexing transition as well as transitions after an HAnime that
    -- was observed during this run.
    HAnimeDetector.reentry_recovery_armed = true
    HAnimeDetector.reentry_signal_frames = 0
    HAnimeDetector.contract_reference_rescan_attempts = {}
    HSystemState.clear()
end

function HAnimeDetector.queue_component(component)
    -- NotifyOnNewObject/Montage_Play callbacks provide the concrete component.
    -- Inspection is deferred to the regular game-thread sampling path.
    ComponentRegistry.queue(component)
end

return HAnimeDetector
