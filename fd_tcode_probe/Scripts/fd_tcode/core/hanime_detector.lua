local Config = require("fd_tcode.config")
local ComponentRegistry = require("fd_tcode.core.hanime_component_registry")
local HAnimeManagerEventProbe = require("fd_tcode.core.hanime_manager_event_probe")
local HSystemState = require("fd_tcode.core.hanime_hsystem_state")
local IdentityResolver = require("fd_tcode.core.hanime_identity_resolver")
local MotionContract = require("fd_tcode.core.hanime_motion_contract")
local Log = require("fd_tcode.core.log")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

-- F10 deliberately reloads only the detector to avoid UE4SS's unsafe full-Mod
-- RestartMod path.  The realtime reader is a plain Lua table already held by
-- skeleton_stream, so replace its functions in place during that hot reload.
-- The initial startup does not take this path.
if tonumber(_G.FD_TCODE_STREAM_GENERATION or 0) > 0
    and package ~= nil
    and type(package.loaded) == "table"
then
    local function hot_swap_table_module(module_name)
        local current = package.loaded[module_name]
        if type(current) == "table" then
            package.loaded[module_name] = nil
            local reload_ok, replacement = pcall(require, module_name)
            if reload_ok and type(replacement) == "table" then
                for key in pairs(current) do
                    current[key] = nil
                end
                for key, value in pairs(replacement) do
                    current[key] = value
                end
                package.loaded[module_name] = current
            else
                package.loaded[module_name] = current
            end
        end
    end
    hot_swap_table_module("fd_tcode.core.log")
    -- HAnime identity and skeleton entries are generated/deployed as separate
    -- data files.  F10 is intentionally the only safe live-reload path in
    -- UE5.7, so rebuild their dependency chain in place before replacing the
    -- long-lived probe table.  Every module here exports a plain Lua table;
    -- preserve table identity so existing stream closures retain valid refs.
    hot_swap_table_module("fd_tcode.data.ada_hanime_identity_data")
    hot_swap_table_module("fd_tcode.data.update_2026_08_28_hanime_identity_data")
    hot_swap_table_module("fd_tcode.data.playtest_ue57_playable_hanime_identity_data")
    hot_swap_table_module("fd_tcode.data.nonhuman_direct_output_profile_data")
    -- Target frames are data rather than detector code. Reload them before
    -- rebuilding the motion contract so F10 picks up corrected static-rig or
    -- ADA generated-rig bone names without restarting the game.
    hot_swap_table_module("fd_tcode.data.target_frame_catalog")
    hot_swap_table_module("fd_tcode.core.hanime_identity_catalog")
    hot_swap_table_module("fd_tcode.core.skeleton_catalog")
    -- Registry metadata contains catalog role decisions made during component
    -- discovery.  Rebuild it after SkeletonCatalog or a newly added Ada body
    -- would stay cached as role=<none> until the next game restart.
    hot_swap_table_module("fd_tcode.core.hanime_component_registry")
    hot_swap_table_module("fd_tcode.core.hanime_identity_resolver")
    hot_swap_table_module("fd_tcode.core.hanime_motion_contract")
    hot_swap_table_module("fd_tcode.core.generic_hanime_probe")
end

local hot_spool_proxy = nil

local function ensure_hot_spool_batching()
    -- The already-running skeleton_stream cannot replace its local sample_once
    -- closure through F10. Wrap only that old module's file handle. A normal
    -- restart loads the native batching implementation above and skips this.
    local stream = package ~= nil and package.loaded ~= nil
        and package.loaded["fd_tcode.core.skeleton_stream"]
        or nil
    if type(stream) ~= "table"
        or stream.flush_interval_supported == true
        or stream.spool == nil
        or stream.spool == hot_spool_proxy
    then
        return
    end
    local handle = stream.spool
    local interval = math.max(1, tonumber(Config.skeleton_spool_flush_interval_frames or 2))
    local proxy = { flush_count = 0, closed = false }
    function proxy:write(...)
        return handle:write(...)
    end
    function proxy:flush()
        self.flush_count = self.flush_count + 1
        if self.flush_count >= interval then
            self.flush_count = 0
            return handle:flush()
        end
        return true
    end
    function proxy:close()
        if not self.closed then
            self.closed = true
            pcall(function() handle:flush() end)
            return handle:close()
        end
        return true
    end
    hot_spool_proxy = proxy
    stream.spool = proxy
end
local HAnimeDetector = {
    candidate_id = nil,
    candidate_frames = 0,
    active = nil,
    empty_frames = 0,
    transition_review_requested = false,
    last_observation = nil,
    -- The first HAnime after a fresh Mod load may create its nonhuman
    -- participant after the initial component cache was built.  Treat the
    -- first verified Exp_In/Exp_Sexing transition exactly like later action
    -- re-entry, otherwise an initial nonhuman scene can never expose its
    -- companion Montage to the exact HAnime gate.
    reentry_recovery_armed = true,
    reentry_signal_frames = 0,
    contract_reference_rescan_attempts = {},
    manager_discovery_signature = nil,
    -- A freshly required detector performs one bounded acquisition. Normal
    -- startup clears this and waits for Character BeginPlay; F10 preserves it
    -- so the detector can be recovered while already inside HAnime.
    component_discovery_pending = true,
    component_discovery_delay_frames = 2,
    component_discovery_attempts = 1,
    component_discovery_classes = {},
    -- The stable runtime shell may survive an F10 detector-only reload. Keep a
    -- one-call handoff from queue_actor_components() so an older shell that
    -- still requests class discovery immediately afterwards cannot reintroduce
    -- the redundant three-pass FindFirstOf acquisition.
    direct_actor_queue_succeeded = false,
    -- UE 5.7 can resolve the exact AnimInstance class while the inverse
    -- SkeletalMeshComponent:GetAnimInstance call returns nil. Keep the
    -- game-thread acquisition pair so the low-frequency detector can use the
    -- verified class without another object search.
    discovered_anim_instances = {},
    -- Monotonic BeginPlay generation used only to rank otherwise equivalent
    -- body components during a transition. It is never polled in Active.
    actor_component_generation = 0,
}

local RECOVERY_ANIM_CLASS_PRIORITY = {
    "AMBP_Alet_HAnim_C", "AMBP_Male_C", "AMBP_ADA_C", "AMBP_Anya_H_Anim_C",
    "AMBP_Erika_C", "AMBP_Gala_C", "AMBP_Juzi_C", "AMBP_Sylph_C",
    "AMBP_Talon_C", "AMBP_Yanshi_C", "AMBP_Celia_C", "AMBP_Elizabeth_C",
    "AMBP_DeepOne_C", "AMBP_Ghast_C", "AMBP_Ghoul_C", "AMBP_Gug_C",
    "AMBP_Hound_HAnim_C", "AMBP_Hippocamp_C", "AMBP_Saaitii_C",
    "AMBP_Byakhee_C", "AMBP_Drone_C", "AMBP_ElderThing_C", "AMBP_Lloigor_C",
    "AMBP_Migo_warrior_C", "AMBP_nightgaunt_C", "AMBP_Shantak_C",
    "AMBP_Skorpios_C", "AMBP_TchoTcho_C", "AMBP_Tentacle_C",
}

local function requested_anim_classes()
    local result = {}
    local seen = {}
    for class_name in pairs(HAnimeDetector.component_discovery_classes or {}) do
        if Config.hanime_anim_blueprint_classes[class_name] == true and not seen[class_name] then
            seen[class_name] = true
            table.insert(result, class_name)
        end
    end
    if #result == 0 then
        for _, class_name in ipairs(RECOVERY_ANIM_CLASS_PRIORITY) do
            if Config.hanime_anim_blueprint_classes[class_name] == true and not seen[class_name] then
                seen[class_name] = true
                table.insert(result, class_name)
            end
        end
    end
    return result
end

local function runtime_anim_blueprint_items(visible_only, hanime_class_only)
    local result = {}
    local stale = {}
    for key, item in pairs(HAnimeDetector.discovered_anim_instances or {}) do
        local component = item.component
        local anim_instance = item.anim_instance
        if not ComponentRegistry.is_live(component) or not Safe.is_object(anim_instance) then
            table.insert(stale, key)
        else
            local role, entry, evidence = SkeletonCatalog.match_component(component)
            local class_name = tostring(item.class_name or Safe.class_name(anim_instance) or "")
            local accepted = entry ~= nil
                and SkeletonCatalog.is_primary_component(component, entry)
                and Config.hanime_anim_blueprint_classes[class_name] == true
            if accepted and hanime_class_only then
                local normalized_class = string.lower(class_name)
                accepted = string.find(normalized_class, "hanim", 1, true) ~= nil
                    or string.find(normalized_class, "h_anim", 1, true) ~= nil
            end
            if accepted and visible_only then
                local visible_ok, visible = pcall(function()
                    return component:IsVisible()
                end)
                local rendered_ok, recently_rendered = pcall(function()
                    return component:WasRecentlyRendered(0.75)
                end)
                accepted = (not visible_ok or visible ~= false)
                    and (not rendered_ok or recently_rendered == true)
            end
            if accepted then
                table.insert(result, {
                    component = component,
                    component_name = Safe.object_name(component),
                    class_name = class_name,
                    instance_name = Safe.object_name(anim_instance),
                    role = role,
                    entry = entry,
                    evidence = evidence,
                })
            end
        end
    end
    for _, key in ipairs(stale) do
        HAnimeDetector.discovered_anim_instances[key] = nil
    end
    table.sort(result, function(a, b)
        return tostring(a.component_name or "") < tostring(b.component_name or "")
    end)
    return result
end

local function merge_anim_blueprint_items(primary, supplemental)
    local result = {}
    local seen = {}
    for _, source in ipairs({ primary or {}, supplemental or {} }) do
        for _, item in ipairs(source) do
            local key = tostring(item.component_name or "") .. "|" .. tostring(item.class_name or "")
            if not seen[key] then
                seen[key] = true
                table.insert(result, item)
            end
        end
    end
    return result
end

local function targeted_bone_api_diagnostic(component, role)
    local bone_name = role == "male" and "Penis01" or "M_Gen"
    local fname_ok, socket_name = pcall(FName, bone_name)
    if not fname_ok then
        return "FName=" .. tostring(socket_name)
    end

    local index_ok, bone_index = pcall(function()
        return component:GetBoneIndex(socket_name)
    end)
    local location_ok, location = pcall(function()
        return component:GetSocketLocation(socket_name)
    end)
    local raw_transforms_ok, raw_transforms = pcall(function()
        return component.ComponentSpaceTransforms
    end)
    local transforms_ok, transform_count = pcall(function()
        return #raw_transforms
    end)
    local array_num_ok, array_num = pcall(function()
        return raw_transforms:GetArrayNum()
    end)
    local array_first_ok, array_first = pcall(function()
        return raw_transforms[1]
    end)

    local bone_transform_paths = {}
    local bone_transform_function = nil
    for _, path in ipairs({
        "/Script/Engine.SkinnedMeshComponent:GetBoneTransform",
        "/Script/Engine.SkeletalMeshComponent:GetBoneTransform",
    }) do
        local found_ok, found = pcall(StaticFindObject, path)
        if found_ok and Safe.is_object(found) then
            table.insert(bone_transform_paths, path)
            bone_transform_function = bone_transform_function or found
        end
    end
    local bone_transform_ok, bone_transform = pcall(function()
        return bone_transform_function(component, socket_name, 0)
    end)

    local explicit_ok, explicit_transform = pcall(function()
        local fn = StaticFindObject("/Script/Engine.SceneComponent:GetSocketTransform")
        if not Safe.is_object(fn) then
            error("GetSocketTransform UFunction was not found")
        end
        return fn(component, socket_name, 0)
    end)
    local explicit_text = explicit_ok
        and Safe.value_text(explicit_transform)
        or tostring(explicit_transform)
    explicit_text = string.gsub(tostring(explicit_text), "[\r\n].*", "")
    return string.format(
        "bone=%s index=%s/%s location=%s/%s transformsRaw=%s/%s len=%s/%s arrayNum=%s/%s first=%s/%s getBoneTransform=%s call=%s/%s explicitTransform=%s/%s",
        bone_name,
        tostring(index_ok),
        tostring(bone_index),
        tostring(location_ok),
        tostring(location_ok and Safe.value_text(location) or location),
        tostring(raw_transforms_ok),
        tostring(raw_transforms),
        tostring(transforms_ok),
        tostring(transform_count),
        tostring(array_num_ok),
        tostring(array_num),
        tostring(array_first_ok),
        tostring(array_first_ok and Safe.value_text(array_first) or array_first),
        #bone_transform_paths > 0 and table.concat(bone_transform_paths, ",") or "<none>",
        tostring(bone_transform_ok),
        tostring(bone_transform_ok and Safe.value_text(bone_transform) or bone_transform),
        tostring(explicit_ok),
        explicit_text
    )
end

local function refresh_requested_components()
    if HAnimeDetector.component_discovery_pending ~= true then
        return
    end
    if HAnimeDetector.component_discovery_delay_frames > 0 then
        HAnimeDetector.component_discovery_delay_frames = HAnimeDetector.component_discovery_delay_frames - 1
        return
    end

    local refreshed = type(FindFirstOf) == "function"
    local queued = 0
    local found_instances = 0
    local resolved_components = 0
    local found_labels = {}
    if refreshed then
        -- Exact class names come from the current Playtest extraction. This is
        -- a bounded acquisition after BeginPlay/F10, never a global UObject
        -- enumeration and never part of the steady 4 Hz path.
        for _, class_name in ipairs(requested_anim_classes()) do
            local find_ok, anim_instance = pcall(FindFirstOf, class_name)
            if find_ok and Safe.is_object(anim_instance) then
                found_instances = found_instances + 1
                local component_ok, component = pcall(function()
                    return anim_instance:GetOwningComponent()
                end)
                if not component_ok or not Safe.is_object(component) then
                    -- In the UE 5.7 Playtest, GetOwningComponent currently
                    -- returns nil through reflection even though the exact
                    -- AnimInstance path is nested under Mesh_Main/Mesh_MaleB.
                    -- The direct Outer is that owning SkeletalMeshComponent.
                    component = Safe.outer(anim_instance)
                    component_ok = Safe.is_object(component)
                end
                if component_ok and Safe.is_object(component) then
                    -- FindFirstOf may return the Male POV AnimInstance. Resolve
                    -- its exact sibling Mesh_MaleB from the owning actor before
                    -- the component is admitted to the primary-body registry.
                    local primary = SkeletonCatalog.resolve_primary_sibling(component)
                    if Safe.is_object(primary) then
                        component = primary
                    end
                    local component_name = Safe.object_name(component)
                    if component_name ~= nil then
                        HAnimeDetector.discovered_anim_instances[component_name .. "|" .. class_name] = {
                            component = component,
                            anim_instance = anim_instance,
                            class_name = class_name,
                        }
                    end
                    resolved_components = resolved_components + 1
                    if #found_labels < 4 then
                        local role, entry, evidence = SkeletonCatalog.match_component(component)
                        local is_primary = entry ~= nil
                            and SkeletonCatalog.is_primary_component(component, entry)
                            or false
                        table.insert(found_labels, string.format(
                            "%s=%s,role=%s,method=%s,primary=%s,live=%s",
                            class_name,
                            tostring(Safe.object_name(component) or "<unnamed>"),
                            tostring(role or "<none>"),
                            tostring(evidence and evidence.method or "<none>"),
                            tostring(is_primary),
                            tostring(ComponentRegistry.is_live(component))
                        ))
                        if Config.performance_diagnostics_enabled == true
                            and HAnimeDetector.component_discovery_attempts >= 2
                        then
                            Log.info(string.format(
                                "UE 5.7 targeted bone API %s %s",
                                tostring(role or class_name),
                                targeted_bone_api_diagnostic(component, role)
                            ))
                        end
                    end
                    ComponentRegistry.queue(component)
                    queued = queued + 1
                end
                component = nil
            end
            anim_instance = nil
            if next(HAnimeDetector.component_discovery_classes or {}) == nil
                and resolved_components >= 2
            then
                break
            end
        end
    end
    HAnimeDetector.component_discovery_attempts = HAnimeDetector.component_discovery_attempts - 1
    Log.info(string.format(
        "HAnime exact AnimBP cache refresh ok=%s found=%d components=%d queued=%d cached=%d attemptsLeft=%d labels=%s",
        tostring(refreshed),
        found_instances or 0,
        resolved_components or 0,
        queued,
        #ComponentRegistry.items(),
        math.max(0, HAnimeDetector.component_discovery_attempts),
        #found_labels > 0 and table.concat(found_labels, ";") or "<none>"
    ))
    if HAnimeDetector.component_discovery_attempts > 0 then
        -- AnimInstances can be assigned shortly after the participant Actor's
        -- BeginPlay. Retry twice at a low rate; this is not a continuous scan.
        HAnimeDetector.component_discovery_delay_frames = 2
    else
        HAnimeDetector.component_discovery_pending = false
    end
end

local function identity_components_are_registered(identity)
    local bindings = identity and identity.participant_bindings or {}
    if #bindings == 0 then
        return false
    end
    for _, binding in ipairs(bindings) do
        local component = binding.component
        if not ComponentRegistry.is_live(component) or not ComponentRegistry.contains(component) then
            return false
        end
    end
    return true
end

local function identity_bindings_are_complete(identity)
    if not identity_components_are_registered(identity) then
        return false
    end

    local expected = identity and identity.expected_catalog_roles or {}
    local actual = {}
    for _, binding in ipairs(identity and identity.participant_bindings or {}) do
        local role = binding.catalog_role
        if role ~= nil then
            actual[role] = (actual[role] or 0) + 1
        end
    end
    for role, count in pairs(expected) do
        if (actual[role] or 0) < tonumber(count or 0) then
            return false
        end
    end
    return true
end

local function finish_component_discovery_if_bound(identity)
    if HAnimeDetector.component_discovery_pending ~= true
        or not identity_bindings_are_complete(identity)
    then
        return false
    end
    -- A delayed fallback may have been armed by an actor whose primary mesh
    -- was not available directly. Exact Montage resolution or the restricted
    -- contract rescan can still complete the participant binding during that
    -- settle window. Once it does, the remaining FindFirstOf retries are stale
    -- work and must not survive into Active.
    HAnimeDetector.component_discovery_pending = false
    HAnimeDetector.component_discovery_delay_frames = 0
    HAnimeDetector.component_discovery_attempts = 0
    HAnimeDetector.component_discovery_classes = {}
    HAnimeDetector.direct_actor_queue_succeeded = false
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
        for _, component in ipairs(ComponentRegistry.binding_items()) do
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

local function select_visible_anim_blueprint_identity(items)
    local references = 0
    local targets = 0
    local participant_components = {}
    local participant_bindings = {}
    local signature_parts = {}
    for index, item in ipairs(items or {}) do
        local entry = item.entry or {}
        if entry.motion_role == "male" then
            references = references + 1
        else
            targets = targets + 1
        end
        table.insert(participant_components, item.component)
        table.insert(participant_bindings, {
            component = item.component,
            component_name = item.component_name,
            catalog_role = item.role,
            catalog_entry = entry,
            component_evidence = item.evidence,
            participant_tag = tostring(item.role or "runtime") .. "_visible",
            participant_slot = "generic",
            participant_priority = index - 1,
        })
        table.insert(signature_parts, string.format(
            "%s:%s",
            tostring(item.role or "unknown"),
            tostring(item.class_name or "unknown")
        ))
    end
    -- A single visible character is the ordinary room idle case. Requiring a
    -- reference and a target prevents that idle skeleton from opening the
    -- output gate while still supporting multi-participant scenes.
    if references == 0 or targets == 0 then
        return nil
    end
    table.sort(signature_parts)
    local runtime_id = "ue57-runtime:" .. table.concat(signature_parts, "+")
    return {
        hanime_id = runtime_id,
        asset = runtime_id,
        category = "other",
        phase = "normal",
        recognition_source = "ue57_visible_anim_blueprint_pair",
        expected_catalog_roles = {},
        expected_catalog_slots = {},
        expected_catalog_priorities = {},
        matched_components = participant_components,
        matched_participants = {},
        participant_components = participant_components,
        participant_bindings = participant_bindings,
        active_participant_montages = 0,
        runtime_bindings_complete = true,
    }
end

local function inherit_active_identity(recognition_source)
    if HAnimeDetector.active == nil then
        return nil
    end
    local selected = {}
    for key, value in pairs(HAnimeDetector.active) do
        if key ~= "matched_components"
            and key ~= "matched_participants"
            and key ~= "participant_components"
            and key ~= "participant_bindings"
        then
            selected[key] = value
        end
    end
    selected.matched_components = {}
    selected.matched_participants = {}
    selected.recognition_source = recognition_source
    return selected
end

local function observe(allow_recovery)
    -- HManager is discovered only at an HAnime entry/exact-match event. Once
    -- cached, this is a handful of property reads and performs no enumeration.
    refresh_requested_components()
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
    local discovered_anim_blueprints = runtime_anim_blueprint_items(false, true)
    local discovered_participant_anim_blueprints = runtime_anim_blueprint_items(false, false)
    local discovered_visible_anim_blueprints = runtime_anim_blueprint_items(true)
    local hanime_anim_blueprints = merge_anim_blueprint_items(
        ComponentRegistry.hanime_anim_blueprints(),
        discovered_anim_blueprints
    )
    local visible_anim_blueprints = merge_anim_blueprint_items(
        ComponentRegistry.visible_hanime_anim_blueprints(),
        discovered_visible_anim_blueprints
    )
    local visible_anim_blueprint_labels = {}
    for _, item in ipairs(visible_anim_blueprints) do
        table.insert(visible_anim_blueprint_labels, string.format(
            "%s:%s:%s",
            tostring(item.role or "unknown"),
            tostring((item.entry or {}).motion_role or "unknown"),
            tostring(item.class_name or "unknown")
        ))
    end
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
    elseif #hanime_anim_blueprints > 0 then
        -- UE 5.7 no longer exposes the HAnime state-machine animation through
        -- GetCurrentActiveMontage.  A live HAnim AnimBP is exact runtime
        -- evidence that an HAnime is active.  Use that transition to perform
        -- one manager discovery for this concrete component/class binding;
        -- subsequent 4 Hz polls read only the cached manager properties.
        local signature_parts = {}
        for _, item in ipairs(hanime_anim_blueprints) do
            table.insert(signature_parts, string.format(
                "%s=%s",
                tostring(item.component_name or "<component>"),
                tostring(item.class_name or "<class>")
            ))
        end
        local signature = table.concat(signature_parts, "|")
        local allow_manager_discovery = signature ~= HAnimeDetector.manager_discovery_signature
        if allow_manager_discovery then
            HAnimeDetector.manager_discovery_signature = signature
        end
        current_scene_state = HSystemState.read(allow_manager_discovery)
        selected = IdentityResolver.hsystem_identity(current_scene_state)
        if selected ~= nil then
            selected.recognition_source = "hmanager_exact_anim_id_hanim_anim_blueprint"
        else
            -- UE 5.7 can keep the HAnime inside an AnimBP state machine while
            -- GetCurrentActiveMontage and the manager properties expose no
        -- usable identity.  The HAnim-specific target AnimBP is still an
            -- exact action-state signal.  Pair it with the already acquired
            -- reference participant; do not use visibility, because first
            -- person/character-hide modes legitimately make either mesh
            -- invisible while the action continues.
            selected = select_visible_anim_blueprint_identity(discovered_participant_anim_blueprints)
            if selected ~= nil then
                selected.recognition_source = "ue57_hanim_state_machine_participant_pair"
            end
        end
    elseif HAnimeDetector.active ~= nil
        and IdentityResolver.assets_indicate_confirmed_session_phase(unknown_assets)
    then
        -- A confirmed humanoid HAnime can replace all preview Actors when the
        -- playable phase starts.  Keep its exact identity and rebuild only the
        -- participant bindings from the BeginPlay-queued components.  Generic
        -- Generic Touch/Sex states can never reach this path without an active
        -- exact TableHAnim session, so room/UI animations cannot open the gate.
        selected = inherit_active_identity("table_hanim_exact_confirmed_session_phase")
    elseif IdentityResolver.assets_indicate_active_hanime(unknown_assets) then
        current_scene_state = HSystemState.read(true)
        selected = IdentityResolver.hsystem_identity(current_scene_state)
        if selected == nil and HAnimeDetector.active ~= nil then
            -- UE 5.7 can replace every participant Actor after the exact
            -- TableHAnim start Montage, leaving only an active facial or
            -- interaction expression visible. Preserve the established
            -- identity but rebuild its UObject bindings from the event-queued
            -- primary components. Never use this path to open a new gate.
            selected = inherit_active_identity("table_hanim_exact_active_expression_refresh")
        end
    end
    if selected == nil then
        selected = select_visible_anim_blueprint_identity(visible_anim_blueprints)
    end
    if selected ~= nil and selected.runtime_bindings_complete ~= true then
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
    if selected ~= nil and selected.runtime_bindings_complete ~= true then
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
        for _, component in ipairs(ComponentRegistry.binding_items()) do
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
        hanime_anim_blueprint_count = #hanime_anim_blueprints,
        hanime_anim_blueprints = hanime_anim_blueprints,
        visible_anim_blueprint_count = #visible_anim_blueprints,
        visible_anim_blueprint_labels = visible_anim_blueprint_labels,
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
        hanime_anim_blueprint_count = observation.hanime_anim_blueprint_count or 0,
        hanime_anim_blueprints = observation.hanime_anim_blueprints or {},
        visible_anim_blueprint_count = observation.visible_anim_blueprint_count or 0,
        visible_anim_blueprint_labels = observation.visible_anim_blueprint_labels or {},
        scene_state = observation.scene_state or {},
    }
end

function HAnimeDetector.sample()
    ensure_hot_spool_batching()
    if HAnimeDetector.active ~= nil
        and HAnimeDetector.last_observation ~= nil
        and identity_components_are_registered(HAnimeDetector.active)
    then
        -- The verified participant binding is the steady-state gate. Reusing
        -- it does not inspect AnimBP, visibility, Montage or HManager state and
        -- therefore cannot refresh clothing/physics. A lifecycle or Montage
        -- notification adapter consumes exactly one transition review below.
        -- Component discovery is a bounded transition fallback. It remains
        -- pending only while a complete binding is still unavailable; the
        -- first successful binding cancels every unused retry. Once pending is
        -- false, steady Active returns here without any AnimBP/Montage/HManager
        -- scan.
        if HAnimeDetector.transition_review_requested ~= true
            and HAnimeDetector.component_discovery_pending ~= true
        then
            return status("active", true, HAnimeDetector.last_observation, nil)
        end
        HAnimeDetector.transition_review_requested = false
    end
    local observed, observation = observe()
    HAnimeDetector.last_observation = observation
    if observed ~= nil then
        HAnimeDetector.empty_frames = 0
        finish_component_discovery_if_bound(observed)
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
        local recognition_source = tostring(observed.recognition_source or "")
        local exact_observation = string.find(recognition_source, "exact", 1, true) ~= nil
        local required_confirm_frames = exact_observation
            and math.max(1, tonumber(Config.hanime_switch_confirm_frames or 1))
            or math.max(1, tonumber(Config.hanime_confirm_frames or 2))
        if HAnimeDetector.candidate_frames >= required_confirm_frames then
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
    HAnimeDetector.transition_review_requested = false
    HAnimeDetector.last_observation = nil
    -- The automatic stream may start while the room is already idle. Arm the first
    -- Exp_In/Exp_Sexing transition as well as transitions after an HAnime that
    -- was observed during this run.
    HAnimeDetector.reentry_recovery_armed = true
    HAnimeDetector.reentry_signal_frames = 0
    HAnimeDetector.contract_reference_rescan_attempts = {}
    HAnimeDetector.manager_discovery_signature = nil
    HAnimeDetector.component_discovery_pending = false
    HAnimeDetector.component_discovery_delay_frames = 0
    HAnimeDetector.component_discovery_attempts = 0
    HAnimeDetector.component_discovery_classes = {}
    HAnimeDetector.direct_actor_queue_succeeded = false
    HAnimeDetector.discovered_anim_instances = {}
    HAnimeDetector.actor_component_generation = 0
    HSystemState.clear()
end

function HAnimeDetector.request_component_discovery(class_names)
    local actor_scoped_request = type(class_names) == "table" and #class_names > 0
    if actor_scoped_request and HAnimeDetector.direct_actor_queue_succeeded == true then
        -- BeginPlay supplied the exact Actor and its primary component was
        -- already queued. The normal transition review will drain that queue;
        -- searching an AnimInstance class three more times adds no information
        -- and visibly hitches UE 5.7 clothing/physics.
        HAnimeDetector.direct_actor_queue_succeeded = false
        HAnimeDetector.transition_review_requested = true
        return false
    end
    HAnimeDetector.direct_actor_queue_succeeded = false
    HAnimeDetector.component_discovery_pending = true
    -- Wait roughly 500 ms after the most recent participant BeginPlay so its
    -- AnimInstance and owning component have completed assignment.
    HAnimeDetector.component_discovery_delay_frames = 2
    HAnimeDetector.component_discovery_attempts = 3
    -- Participant creation or an explicit F10 recovery is a state-transition
    -- signal. Do not let the active fast path defer its next observation.
    HAnimeDetector.transition_review_requested = true
    for _, class_name in ipairs(type(class_names) == "table" and class_names or {}) do
        HAnimeDetector.component_discovery_classes[tostring(class_name)] = true
    end
    return true
end

function HAnimeDetector.queue_component(component)
    -- A verified lifecycle/Montage adapter may provide a concrete component.
    -- Inspection is deferred to the regular game-thread sampling path.
    ComponentRegistry.queue(component)
    HAnimeDetector.transition_review_requested = true
end

function HAnimeDetector.queue_actor_components(actor)
    -- BeginPlay supplies the concrete actor, so read its extracted primary-mesh
    -- properties immediately. This captures every same-class participant
    -- (Male_A/Male_B/etc.) without FindAllOf or a steady-state object scan.
    local actor_role = SkeletonCatalog.role_for_actor(actor)
    local expected_count = actor_role ~= nil
        and tonumber(((HAnimeDetector.active or {}).expected_catalog_roles or {})[actor_role] or 0)
        or 0
    if expected_count == 1 then
        -- Some UE 5.7 actions replace both participant Actors after their
        -- exact start Montage. The old wrappers can remain IsValid while all
        -- bone transforms return zero. Remove only a single expected role;
        -- multi-participant roles (for example two Male actors) stay intact.
        ComponentRegistry.drop_role(actor_role)
        HAnimeDetector.contract_reference_rescan_attempts = {}
    end
    local items = SkeletonCatalog.primary_components_from_actor(actor)
    HAnimeDetector.actor_component_generation = HAnimeDetector.actor_component_generation + 1
    local actor_generation = HAnimeDetector.actor_component_generation
    for _, item in ipairs(items) do
        ComponentRegistry.queue(item.component, {
            actor_generation = actor_generation,
            queued_by = "actor_begin_play",
        })
    end
    HAnimeDetector.direct_actor_queue_succeeded = #items > 0
    if #items > 0 then
        HAnimeDetector.transition_review_requested = true
    end
    return #items
end

function HAnimeDetector.observe_montage_play(anim_instance, montage)
    local component, full_name = ComponentRegistry.observe_montage_play(anim_instance, montage)
    HAnimeDetector.transition_review_requested = true
    return component, full_name
end

function HAnimeDetector.observe_montage_stop(anim_instance, montage)
    ComponentRegistry.observe_montage_stop(anim_instance, montage)
    HAnimeDetector.transition_review_requested = true
end

return HAnimeDetector
