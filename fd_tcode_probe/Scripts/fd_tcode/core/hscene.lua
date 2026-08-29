local Config = require("fd_tcode.config")
local Safe = require("fd_tcode.core.safe")

local HScene = {}

local function contains(value, text)
    return string.find(value or "", text, 1, true) ~= nil
end

local function append_unique(target, seen, object)
    if not Safe.is_object(object) then
        return
    end
    local name = Safe.object_name(object)
    if name == nil or seen[name] then
        return
    end
    seen[name] = true
    table.insert(target, object)
end

local function find_managers()
    local managers = {}
    local seen = {}
    for _, class_name in ipairs(Config.manager_classes) do
        local ok, objects = pcall(FindAllOf, class_name)
        if ok and objects ~= nil then
            for _, object in pairs(objects) do
                append_unique(managers, seen, object)
            end
        end
    end
    return managers
end

local function manager_score(manager)
    local name = Safe.object_name(manager) or ""
    local class_name = Safe.class_name(manager) or ""
    if string.find(name, "Default__", 1, true) then
        return -1000
    end

    local score = 0
    if contains(class_name, "HSceneManager") then
        score = score + 200
    elseif class_name == "HManager_C" or class_name == "HManager" then
        -- The single-player room uses HManager_C itself as the authoritative
        -- H-system owner. Its AnimID/CardID properties are more useful than a
        -- detached HSceneManager default or component instance.
        score = score + 240
    elseif contains(class_name, "HAnimManager") then
        score = score + 120
    elseif contains(class_name, "HStateManager") then
        score = score + 80
    elseif contains(class_name, "HSceneContorller") then
        score = score + 40
    elseif contains(class_name, "HSceneMode") then
        score = score + 20
    end
    if string.find(name, ":PersistentLevel", 1, true) then
        score = score + 100
    end
    local ok, anim_manager = Safe.read(manager, "AnimManager")
    if ok and Safe.is_object(anim_manager) then
        score = score + 10
    end
    return score
end

function HScene.find_manager()
    local best = nil
    local best_score = -10000
    for _, manager in ipairs(find_managers()) do
        local score = manager_score(manager)
        if score > best_score then
            best = manager
            best_score = score
        end
    end
    return best, best_score
end

local function first_object_property(object, names)
    for _, property_name in ipairs(names) do
        local ok, value = Safe.read(object, property_name)
        if ok and Safe.is_object(value) then
            return value, property_name
        end
    end
    return nil, nil
end

local function object_chain(object)
    local chain = {}
    local seen = {}
    local current = object
    local depth = 0
    while Safe.is_object(current) and depth < 6 do
        local name = Safe.object_name(current)
        if name == nil or seen[name] then
            break
        end
        seen[name] = true
        table.insert(chain, current)
        current = Safe.outer(current)
        depth = depth + 1
    end
    return chain
end

local function first_object_property_in_chain(chain, names)
    for _, object in ipairs(chain) do
        local value, property_name = first_object_property(object, names)
        if Safe.is_object(value) then
            return value, property_name, object
        end
    end
    return nil, nil, nil
end

local function collect_properties(object, names)
    local values = {}
    if not Safe.is_object(object) then
        return values
    end
    for _, property_name in ipairs(names) do
        local text = Safe.property_text(object, property_name)
        -- UE4SS represents some unreadable Blueprint-local/enum storage as a
        -- transient TrivialObject pointer. It is neither a stable value nor a
        -- UObject identity and must not enter fingerprints or logs.
        if text ~= nil and not string.find(text, "TrivialObject:", 1, true) then
            values[property_name] = text
        end
    end
    return values
end

function HScene.snapshot()
    local manager, score = HScene.find_manager()
    if not Safe.is_object(manager) then
        return {
            valid = false,
            reason = "no live HSceneManager instance",
        }
    end

    local manager_class = Safe.class_name(manager) or ""
    local chain = object_chain(manager)
    local host = manager
    local anim_manager = nil
    local anim_property = nil
    local anim_source = nil
    if contains(manager_class, "HAnimManager") then
        anim_manager = manager
        anim_property = "<self>"
        anim_source = manager
    else
        anim_manager, anim_property, anim_source = first_object_property_in_chain(chain, {
            "AnimManager",
            "HAnimManager",
        })
    end

    local state_manager = nil
    local state_property = nil
    local state_source = nil
    if contains(manager_class, "HStateManager") then
        state_manager = manager
        state_property = "<self>"
        state_source = manager
    else
        state_manager, state_property, state_source = first_object_property_in_chain(chain, {
            "StateManager",
            "HStateManager",
        })
    end

    local objects = {}
    local object_refs = {}
    for _, source in ipairs(chain) do
        for _, property_name in ipairs(Config.manager_object_properties) do
            local ok, value = Safe.read(source, property_name)
            if ok and Safe.is_object(value) then
                objects[property_name] = Safe.object_name(value)
                object_refs[property_name] = value
            end
        end
    end

    return {
        valid = true,
        manager = manager,
        manager_name = Safe.object_name(manager),
        manager_class = manager_class,
        manager_score = score,
        host_name = Safe.object_name(host),
        manager_values = collect_properties(host, Config.manager_properties),
        objects = objects,
        object_refs = object_refs,
        anim_manager = anim_manager,
        anim_manager_name = Safe.object_name(anim_manager),
        anim_manager_property = anim_property,
        anim_manager_source = Safe.object_name(anim_source),
        animation_values = collect_properties(anim_manager or manager, Config.animation_properties),
        state_manager = state_manager,
        state_manager_name = Safe.object_name(state_manager),
        state_manager_property = state_property,
        state_manager_source = Safe.object_name(state_source),
    }
end

function HScene.binding_key(snapshot)
    if not snapshot or not snapshot.valid then
        return "offline"
    end
    local parts = {
        tostring(snapshot.manager_name or "<manager>"),
        tostring(snapshot.animation_values and snapshot.animation_values.AnimID or "<anim>"),
    }
    local keys = {}
    for key in pairs(snapshot.objects or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(parts, key .. "=" .. tostring(snapshot.objects[key]))
    end
    return table.concat(parts, "|")
end

local function sorted_pairs(values)
    local keys = {}
    for key in pairs(values or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    local index = 0
    return function()
        index = index + 1
        local key = keys[index]
        if key ~= nil then
            return key, values[key]
        end
    end
end

function HScene.lines(snapshot, detailed)
    if not snapshot.valid then
        return { "state=offline", "reason=" .. tostring(snapshot.reason) }
    end

    local lines = {
        "state=bound",
        "manager=" .. tostring(snapshot.manager_name),
        "animManager=" .. tostring(snapshot.anim_manager_name or "<unresolved>"),
    }

    for key, value in sorted_pairs(snapshot.manager_values) do
        table.insert(lines, "manager." .. key .. "=" .. value)
    end
    for key, value in sorted_pairs(snapshot.animation_values) do
        table.insert(lines, "anim." .. key .. "=" .. value)
    end

    if detailed then
        for key, value in sorted_pairs(snapshot.objects) do
            table.insert(lines, "object." .. key .. "=" .. value)
        end
        table.insert(lines, "host=" .. tostring(snapshot.host_name or "<unresolved>"))
        table.insert(lines, "animManagerSource=" .. tostring(snapshot.anim_manager_source or "<unresolved>"))
        table.insert(lines, "stateManager=" .. tostring(snapshot.state_manager_name or "<unresolved>"))
        table.insert(lines, "stateManagerSource=" .. tostring(snapshot.state_manager_source or "<unresolved>"))
        table.insert(lines, "managerScore=" .. tostring(snapshot.manager_score))
    end
    return lines
end

function HScene.fingerprint(snapshot)
    return table.concat(HScene.lines(snapshot, false), "|")
end

return HScene
