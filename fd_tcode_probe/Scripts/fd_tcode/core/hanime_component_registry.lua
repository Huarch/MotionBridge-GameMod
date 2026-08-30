-- Cached HAnime participant components.
--
-- Global discovery is restricted to an empty/stale cache or an explicit
-- event-driven recovery.  A healthy realtime path only validates cached
-- objects and reads their current Montage.

local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")
local Config = require("fd_tcode.config")

local Registry = {
    components = {},
    metadata = {},
    pending = {},
    pending_hints = {},
    discovery_completed = false,
    montage_events = {},
}

local function sort_components()
    table.sort(Registry.components, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
end

function Registry.is_live(component)
    -- UE 5.7 exposes IsRegistered as a non-callable TrivialObject in Lua.
    -- Safe.is_object already performs the supported IsValid check, while a
    -- world transition clears this registry before wrappers can be reused.
    -- Do not reject a valid component merely because that optional reflected
    -- method is unavailable.
    return Safe.is_object(component)
end

local function current_anim_class(component)
    if not Registry.is_live(component) then
        return nil
    end
    local anim_ok, anim_instance = pcall(function()
        return component:GetAnimInstance()
    end)
    if not anim_ok or not Safe.is_object(anim_instance) then
        return nil
    end
    return Safe.class_name(anim_instance)
end

local function component_metadata(component, role, entry, evidence, previous, hint)
    local owner = Safe.outer(component)
    local metadata = {
        role = role,
        entry = entry,
        name = Safe.object_name(component),
        evidence = evidence,
        owner_name = Safe.object_name(owner),
        anim_class = current_anim_class(component),
        actor_generation = tonumber((hint or {}).actor_generation)
            or tonumber((previous or {}).actor_generation)
            or 0,
        queued_by = tostring((hint or {}).queued_by or (previous or {}).queued_by or "discovery"),
    }
    return metadata
end

function Registry.discover()
    Registry.discovery_completed = true
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        Registry.components = {}
        Registry.metadata = {}
        return false, tostring(values or "FindAllOf returned nil")
    end
    local components = {}
    local metadata = {}
    for _, component in pairs(values) do
        if Registry.is_live(component) then
            local role, entry, evidence = SkeletonCatalog.match_component(component)
            if entry ~= nil and SkeletonCatalog.is_primary_component(component, entry) then
                table.insert(components, component)
                metadata[component] = component_metadata(
                    component, role, entry, evidence, nil, nil
                )
            end
        end
    end
    Registry.components = components
    Registry.metadata = metadata
    sort_components()
    return true, nil
end

local function merge_pending()
    if #Registry.pending == 0 then
        return
    end
    local pending = Registry.pending
    Registry.pending = {}
    local seen = {}
    local components_by_name = {}
    for _, component in ipairs(Registry.components) do
        local name = Safe.object_name(component)
        if name ~= nil then
            seen[name] = true
            components_by_name[name] = component
        end
    end
    for _, component in ipairs(pending) do
        local hint = Registry.pending_hints[component]
        Registry.pending_hints[component] = nil
        if Registry.is_live(component) then
            local role, entry, evidence = SkeletonCatalog.match_component(component)
            local name = Safe.object_name(component)
            if entry ~= nil and name ~= nil and SkeletonCatalog.is_primary_component(component, entry) then
                local existing = components_by_name[name]
                if existing ~= nil then
                    Registry.metadata[existing] = component_metadata(
                        existing,
                        role,
                        entry,
                        evidence,
                        Registry.metadata[existing],
                        hint
                    )
                elseif not seen[name] then
                    seen[name] = true
                    components_by_name[name] = component
                    table.insert(Registry.components, component)
                    Registry.metadata[component] = component_metadata(
                        component, role, entry, evidence, nil, hint
                    )
                end
            end
        end
    end
    sort_components()
end

function Registry.ensure()
    merge_pending()
    if #Registry.components == 0 then
        -- Normal runtime discovery is event-driven. In particular, never run
        -- FindAllOf from the main-menu delayed loop: UE4SS can encounter an
        -- invalid tail entry while iterating the UE 5.7 UObject array.
        return true, nil
    end

    local live_components = {}
    local live_metadata = {}
    for _, component in ipairs(Registry.components) do
        if Registry.is_live(component) then
            table.insert(live_components, component)
            live_metadata[component] = Registry.metadata[component]
        end
    end
    Registry.components = live_components
    Registry.metadata = live_metadata
    return true, nil
end

function Registry.active_montage(component)
    if not Registry.is_live(component) then
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
    if montage_ok and Safe.is_object(montage) then
        return Safe.object_name(montage)
    end

    -- UE 5.7 no longer exposes Fallen Doll's HAnime through
    -- GetCurrentActiveMontage on the owning component. Montage_Play still
    -- supplies the exact asset, so use that event-backed identity until a
    -- matching stop event or object invalidation clears it.
    local component_name = Safe.object_name(component)
    local event = component_name and Registry.montage_events[component_name] or nil
    if event == nil
        or not Safe.is_object(event.component)
        or not Safe.is_object(event.anim_instance)
        or not Safe.is_object(event.montage)
    then
        if component_name ~= nil then
            Registry.montage_events[component_name] = nil
        end
        return nil
    end
    return event.full_name
end

local function is_hanime_anim_class(class_name)
    local normalized = string.lower(tostring(class_name or ""))
    -- The UE 5.7 Playtest moved HAnime playback into character AnimBP state
    -- machines.  The unpacked build currently uses both `_HAnim` (Alet,
    -- Hound) and `_H_Anim` (Anya) spellings.
    return string.find(normalized, "hanim", 1, true) ~= nil
        or string.find(normalized, "h_anim", 1, true) ~= nil
end

function Registry.hanime_anim_blueprints()
    local result = {}
    for _, component in ipairs(Registry.components) do
        if Registry.is_live(component) then
            local anim_ok, anim_instance = pcall(function()
                return component:GetAnimInstance()
            end)
            if anim_ok and Safe.is_object(anim_instance) then
                local class_name = Safe.class_name(anim_instance)
                if is_hanime_anim_class(class_name) then
                    table.insert(result, {
                        component = component,
                        component_name = Safe.object_name(component),
                        class_name = class_name,
                        instance_name = Safe.object_name(anim_instance),
                    })
                end
            end
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.component_name or "") < tostring(b.component_name or "")
    end)
    return result
end

function Registry.visible_hanime_anim_blueprints()
    local result = {}
    for _, component in ipairs(Registry.components) do
        if Registry.is_live(component) then
            local visible_ok, visible = pcall(function()
                return component:IsVisible()
            end)
            local rendered_ok, recently_rendered = pcall(function()
                return component:WasRecentlyRendered(0.75)
            end)
            local anim_ok, anim_instance = pcall(function()
                return component:GetAnimInstance()
            end)
            local visible_now = (not visible_ok or visible ~= false)
                and (not rendered_ok or recently_rendered == true)
            if visible_now and anim_ok and Safe.is_object(anim_instance) then
                local class_name = Safe.class_name(anim_instance)
                local metadata = Registry.metadata[component]
                if Config.hanime_anim_blueprint_classes[class_name] == true and metadata ~= nil then
                    table.insert(result, {
                        component = component,
                        component_name = metadata.name or Safe.object_name(component),
                        class_name = class_name,
                        instance_name = Safe.object_name(anim_instance),
                        role = metadata.role,
                        entry = metadata.entry,
                        evidence = metadata.evidence,
                    })
                end
            end
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.component_name or "") < tostring(b.component_name or "")
    end)
    return result
end

function Registry.observe_montage_play(anim_instance, montage)
    if not Safe.is_object(anim_instance) or not Safe.is_object(montage) then
        return nil, nil
    end
    local component_ok, component = pcall(function()
        return anim_instance:GetOwningComponent()
    end)
    if not component_ok or not Safe.is_object(component) then
        return nil, nil
    end
    Registry.queue(component)
    local component_name = Safe.object_name(component)
    local montage_name = Safe.object_name(montage)
    if component_name == nil or montage_name == nil then
        return component_name, montage_name
    end
    Registry.montage_events[component_name] = {
        component = component,
        anim_instance = anim_instance,
        montage = montage,
        full_name = montage_name,
    }
    return component_name, montage_name
end

function Registry.observe_montage_stop(anim_instance, montage)
    if not Safe.is_object(anim_instance) then
        return
    end
    local component_ok, component = pcall(function()
        return anim_instance:GetOwningComponent()
    end)
    if not component_ok or not Safe.is_object(component) then
        return
    end
    local component_name = Safe.object_name(component)
    if component_name == nil then
        return
    end
    local event = Registry.montage_events[component_name]
    if event == nil then
        return
    end
    if not Safe.is_object(montage) or event.montage == montage then
        Registry.montage_events[component_name] = nil
    end
end

function Registry.rescan_directories(directories)
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        return false, tostring(values or "FindAllOf returned nil")
    end
    local known = {}
    for _, component in ipairs(Registry.components) do
        local name = Safe.object_name(component)
        if name ~= nil then
            known[name] = true
        end
    end
    local added = 0
    for _, component in pairs(values) do
        if Registry.is_live(component) then
            local name = Safe.object_name(component)
            if name ~= nil and not known[name] then
                for _, directory in ipairs(directories or {}) do
                    local role, entry, evidence = SkeletonCatalog.match_component_for_monster_directory(component, directory)
                    if entry ~= nil and SkeletonCatalog.is_primary_component(component, entry) then
                        known[name] = true
                        table.insert(Registry.components, component)
                        Registry.metadata[component] = component_metadata(
                            component, role, entry, evidence, nil, nil
                        )
                        added = added + 1
                        break
                    end
                end
            end
        end
    end
    sort_components()
    return true, added
end

function Registry.items()
    return Registry.components
end

local function preferred_anim_class(metadata)
    local class_name = tostring((metadata or {}).anim_class or "")
    if class_name == "" then
        return false
    end
    for _, preferred in ipairs((((metadata or {}).entry or {}).preferred_anim_blueprint_classes) or {}) do
        if class_name == tostring(preferred) then
            return true
        end
    end
    return false
end

local function has_exact_montage_event(component, metadata)
    local name = (metadata or {}).name or Safe.object_name(component)
    local event = name and Registry.montage_events[name] or nil
    return event ~= nil
        and Safe.is_object(event.component)
        and Safe.is_object(event.anim_instance)
        and Safe.is_object(event.montage)
end

-- Return a transition-time binding order without changing the stable registry
-- order. Exact Montage ownership wins, then the component currently carrying
-- the catalog's expected AnimBP, then the newest actor generation. This lets
-- display-mode swaps choose Mesh_TchoTcho or Mesh_TchoTcho_opacity correctly
-- without visibility tests or a continuous skeleton scan.
function Registry.binding_items()
    merge_pending()
    local result = {}
    for _, component in ipairs(Registry.components) do
        if Registry.is_live(component) then
            local metadata = Registry.metadata[component]
            if metadata ~= nil then
                metadata.anim_class = current_anim_class(component) or metadata.anim_class
                metadata.owner_name = Safe.object_name(Safe.outer(component)) or metadata.owner_name
            end
            table.insert(result, component)
        end
    end
    table.sort(result, function(a, b)
        local a_metadata = Registry.metadata[a] or {}
        local b_metadata = Registry.metadata[b] or {}
        local a_montage = has_exact_montage_event(a, a_metadata)
        local b_montage = has_exact_montage_event(b, b_metadata)
        if a_montage ~= b_montage then
            return a_montage
        end
        local a_anim = preferred_anim_class(a_metadata)
        local b_anim = preferred_anim_class(b_metadata)
        if a_anim ~= b_anim then
            return a_anim
        end
        local a_generation = tonumber(a_metadata.actor_generation or 0)
        local b_generation = tonumber(b_metadata.actor_generation or 0)
        if a_generation ~= b_generation then
            return a_generation > b_generation
        end
        return tostring(a_metadata.name or Safe.object_name(a) or "")
            < tostring(b_metadata.name or Safe.object_name(b) or "")
    end)
    return result
end

function Registry.info(component)
    return Registry.metadata[component]
end

function Registry.contains(component)
    return Registry.metadata[component] ~= nil
end

function Registry.drop_role(role)
    if role == nil then
        return 0
    end
    local kept = {}
    local removed = 0
    for _, component in ipairs(Registry.components) do
        local metadata = Registry.metadata[component]
        if metadata ~= nil and metadata.role == role then
            local name = metadata.name or Safe.object_name(component)
            if name ~= nil then
                Registry.montage_events[name] = nil
            end
            Registry.metadata[component] = nil
            removed = removed + 1
        else
            table.insert(kept, component)
        end
    end
    Registry.components = kept

    -- A UE 5.7 action can spawn the playable actor while an earlier
    -- AnimBP-recovery pass still has the preview actor queued. Purging only
    -- the merged registry lets that stale pending wrapper be re-added on the
    -- next ensure(), and the stream then binds the preview skeleton after the
    -- game has replaced it. Apply the same single-role boundary to pending
    -- components; multi-participant roles call this function only when their
    -- exact family count is one.
    local kept_pending = {}
    for _, component in ipairs(Registry.pending) do
        local pending_role = nil
        if Registry.is_live(component) then
            pending_role = select(1, SkeletonCatalog.match_component(component))
        end
        if pending_role == role then
            Registry.pending_hints[component] = nil
            local name = Safe.object_name(component)
            if name ~= nil then
                Registry.montage_events[name] = nil
            end
            removed = removed + 1
        else
            table.insert(kept_pending, component)
        end
    end
    Registry.pending = kept_pending
    return removed
end

function Registry.queue(component, hint)
    if Safe.is_object(component) then
        table.insert(Registry.pending, component)
        if type(hint) == "table" then
            Registry.pending_hints[component] = hint
        end
    end
end

function Registry.clear()
    Registry.components = {}
    Registry.metadata = {}
    Registry.pending = {}
    Registry.pending_hints = {}
    Registry.discovery_completed = false
    Registry.montage_events = {}
end

return Registry
