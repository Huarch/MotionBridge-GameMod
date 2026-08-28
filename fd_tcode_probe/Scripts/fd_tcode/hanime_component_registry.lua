-- Cached HAnime participant components.
--
-- Global discovery is restricted to an empty/stale cache or an explicit
-- event-driven recovery.  A healthy realtime path only validates cached
-- objects and reads their current Montage.

local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

local Registry = {
    components = {},
    metadata = {},
    pending = {},
}

local function sort_components()
    table.sort(Registry.components, function(a, b)
        return (Safe.object_name(a) or "") < (Safe.object_name(b) or "")
    end)
end

function Registry.is_live(component)
    if not Safe.is_object(component) then
        return false
    end
    local registered_ok, registered = pcall(function()
        return component:IsRegistered()
    end)
    return not registered_ok or registered ~= false
end

function Registry.discover()
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
                metadata[component] = {
                    role = role,
                    entry = entry,
                    name = Safe.object_name(component),
                    evidence = evidence,
                }
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
    for _, component in ipairs(Registry.components) do
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
                -- Object creation may precede registration. Keep the event
                -- payload until the component becomes usable.
                table.insert(Registry.pending, component)
            else
                local role, entry, evidence = SkeletonCatalog.match_component(component)
                local name = Safe.object_name(component)
                if entry ~= nil
                    and name ~= nil
                    and not seen[name]
                    and SkeletonCatalog.is_primary_component(component, entry)
                then
                    seen[name] = true
                    table.insert(Registry.components, component)
                    Registry.metadata[component] = {
                        role = role,
                        entry = entry,
                        name = name,
                        evidence = evidence,
                    }
                end
            end
        end
    end
    sort_components()
end

function Registry.ensure()
    merge_pending()
    if #Registry.components == 0 then
        return Registry.discover()
    end
    for _, component in ipairs(Registry.components) do
        if not Registry.is_live(component) then
            -- Scene changes invalidate the cache and allow one rediscovery.
            return Registry.discover()
        end
    end
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
    if not montage_ok or not Safe.is_object(montage) then
        return nil
    end
    return Safe.object_name(montage)
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
                        Registry.metadata[component] = {
                            role = role,
                            entry = entry,
                            name = name,
                            evidence = evidence,
                        }
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

function Registry.info(component)
    return Registry.metadata[component]
end

function Registry.queue(component)
    if Safe.is_object(component) then
        table.insert(Registry.pending, component)
    end
end

function Registry.clear()
    Registry.components = {}
    Registry.metadata = {}
    Registry.pending = {}
end

return Registry
