-- Hot-reloadable, synchronous event probe.
--
-- UObject arguments are inspected only while the native call still owns them.
-- The probe returns plain strings and never stores an Unreal wrapper for a
-- later tick; this is required for the UE 5.7 Playtest.

local Log = require("fd_tcode.core.log")

local Probe = {
    counts = {},
}

-- RegisterCustomEvent only observes global Blueprint custom events.  The
-- unpacked UE 5.7 Alet AnimBP shows StateComplete as a generated-class
-- UFunction, so it must be hooked by its full function path instead.  Keep
-- this list tiny while validating the event and never retain callback
-- parameters outside the synchronous invocation.
local DIRECT_BLUEPRINT_HOOKS = {
    {
        label = "AMBP_Alet_HAnim.AnimNotify_StateComplete",
        path = "/Game/Characters/Alet/Anim/AMBP_Alet_HAnim.AMBP_Alet_HAnim_C:AnimNotify_StateComplete",
    },
    {
        label = "AMBP_Alet_HAnim.EventStateComplete",
        path = "/Game/Characters/Alet/Anim/AMBP_Alet_HAnim.AMBP_Alet_HAnim_C:EventStateComplete",
    },
}

local CHARACTER_ACTOR_TOKENS = {
    "CharacterADA",
    "CharacterAlet",
    "CharacterAnya",
    "CharacterByakhee",
    "CharacterCelia",
    "CharacterDeepOne",
    "CharacterDrone",
    "CharacterElderThing",
    "CharacterElizabeth",
    "CharacterErika",
    "CharacterGalatea",
    "CharacterGala",
    "CharacterGhast",
    "CharacterGhoul",
    "CharacterGug",
    "CharacterHippocamp",
    "CharacterHound",
    "CharacterJuzi",
    "CharacterJuzhi",
    "CharacterLloigor",
    "CharacterMale",
    "CharacterMigo",
    "CharacterNightgaunt",
    "CharacterSaaitii",
    "CharacterShantak",
    "CharacterSkorpion",
    "CharacterSkorpios",
    "CharacterSylph",
    "CharacterTalon",
    "CharacterTchoTcho",
    "CharacterTentacle",
    "CharacterYanshi",
}

-- Exact generated classes confirmed by the current Playtest extraction. Keep
-- this list deliberately small: FindFirstOf is used only by the development
-- probe, never by the eventual 50 Hz motion path.
local HUMAN_ANIM_BLUEPRINT_CLASSES = {
    "AMBP_ADA_C",
    "AMBP_Alet_HAnim_C",
    "AMBP_Anya_H_Anim_C",
    "AMBP_Celia_C",
    "AMBP_Elizabeth_C",
    "AMBP_Erika_C",
    "AMBP_Gala_C",
    "AMBP_Juzi_C",
    "AMBP_Male_C",
    "AMBP_Sylph_C",
    "AMBP_Talon_C",
    "AMBP_Yanshi_C",
}

local MANAGER_CLASSES = {
    "HManager_C",
    "HSceneManager_C",
    "HAnimManager_C",
    "HStateManager_C",
    "HSceneContorller_C",
    "HSceneMode_C",
}

local MANAGER_STATE_PROPERTIES = {
    "AnimID",
    "CurrentAnimID",
    "AnimationID",
    "AnimName",
    "CurrentAnimName",
    "AnimationName",
    "CurrAnimState",
    "CurrentState",
    "AnimState",
    "AnimSpeed",
}

local ANIM_INSTANCE_STATE_PROPERTIES = {
    "BaseSequence",
    "Sequence",
    "Group",
    "GroupIndex",
    "GroupName",
    "bLoopAnimation",
    "BlendBreath_Sex",
}

local function unwrap(remote)
    if remote == nil then
        return nil
    end
    local ok, value = pcall(function()
        return remote:get()
    end)
    if ok then
        return value
    end
    -- RegisterBeginPlayPostHook supplies the actor directly in some UE4SS
    -- builds rather than wrapping it as a RemoteUnrealParam.
    local name_ok = pcall(function()
        return remote:GetFullName()
    end)
    if name_ok then
        return remote
    end
    return nil
end

local function full_name(object)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object:GetFullName()
    end)
    if ok and value ~= nil then
        return tostring(value)
    end
    return nil
end

local function class_full_name(object)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object:GetClass()
    end)
    if not ok or value == nil then
        return nil
    end
    return full_name(value)
end

local function relevant_character_actor(object)
    local name = full_name(object)
    if name == nil then
        return false
    end
    for _, token in ipairs(CHARACTER_ACTOR_TOKENS) do
        if string.find(name, token, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function reflection_name(value)
    if value == nil then
        return nil
    end
    local full_ok, full = pcall(function()
        return value:GetFullName()
    end)
    if full_ok and full ~= nil then
        return tostring(full)
    end
    local fname_ok, fname = pcall(function()
        return value:GetFName():ToString()
    end)
    if fname_ok and fname ~= nil then
        return tostring(fname)
    end
    return nil
end

local function state_related_name(value)
    local normalized = string.lower(tostring(value or ""))
    return string.find(normalized, "anim", 1, true) ~= nil
        or string.find(normalized, "state", 1, true) ~= nil
        or string.find(normalized, "sequence", 1, true) ~= nil
        or string.find(normalized, "group", 1, true) ~= nil
        or string.find(normalized, "blend", 1, true) ~= nil
        or string.find(normalized, "play", 1, true) ~= nil
        or string.find(normalized, "curve", 1, true) ~= nil
        or string.find(normalized, "mutable", 1, true) ~= nil
end

local function introspect_anim_class(object)
    local class_ok, class = pcall(function()
        return object:GetClass()
    end)
    if not class_ok or class == nil then
        return
    end
    local class_name = full_name(class)
    if class_name == nil then
        return
    end
    _G.FD_TCODE_INTROSPECTED_ANIM_CLASSES = _G.FD_TCODE_INTROSPECTED_ANIM_CLASSES or {}
    if _G.FD_TCODE_INTROSPECTED_ANIM_CLASSES[class_name] then
        return
    end
    _G.FD_TCODE_INTROSPECTED_ANIM_CLASSES[class_name] = true

    local properties = {}
    local functions = {}
    local current = class
    local depth = 0
    while current ~= nil and depth < 4 do
        pcall(function()
            current:ForEachProperty(function(property)
                local name = reflection_name(property)
                if name ~= nil and state_related_name(name) and #properties < 96 then
                    table.insert(properties, name)
                end
            end)
        end)
        pcall(function()
            current:ForEachFunction(function(func)
                local name = reflection_name(func)
                if name ~= nil and state_related_name(name) and #functions < 96 then
                    table.insert(functions, name)
                end
            end)
        end)
        local super_ok, super = pcall(function()
            return current:GetSuperStruct()
        end)
        current = super_ok and super or nil
        depth = depth + 1
    end
    table.sort(properties)
    table.sort(functions)
    Log.info(string.format(
        "AnimBP reflection class=%s properties=%s functions=%s",
        class_name,
        #properties > 0 and table.concat(properties, "|") or "<none>",
        #functions > 0 and table.concat(functions, "|") or "<none>"
    ))
    current = nil
    class = nil
end

local function owning_component(anim_instance)
    if anim_instance == nil then
        return nil
    end
    local ok, value = pcall(function()
        return anim_instance:GetOwningComponent()
    end)
    if ok then
        return value
    end
    return nil
end

local function primitive_property_text(object, property_name)
    local ok, value = pcall(function()
        return object[property_name]
    end)
    if not ok or value == nil then
        return nil
    end
    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    local text_ok, text = pcall(function()
        return value:ToString()
    end)
    if text_ok and text ~= nil then
        return tostring(text)
    end
    return nil
end

local function state_property_text(object, property_name)
    local ok, value = pcall(function()
        return object[property_name]
    end)
    if not ok or value == nil then
        return nil
    end
    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    local name = full_name(value)
    if name ~= nil then
        return name
    end
    local text_ok, text = pcall(function()
        return value:ToString()
    end)
    if text_ok and text ~= nil then
        return tostring(text)
    end
    return nil
end

local function find_live_human_anim_blueprints()
    if type(FindFirstOf) ~= "function" then
        return "<FindFirstOf-unavailable>"
    end
    local names = {}
    for _, class_name in ipairs(HUMAN_ANIM_BLUEPRINT_CLASSES) do
        local ok, object = pcall(FindFirstOf, class_name)
        if ok and object ~= nil then
            local name = full_name(object)
            if name ~= nil then
                introspect_anim_class(object)
                local fields = {
                    class_name .. "=" .. name,
                    "generatedClass=" .. tostring(class_full_name(object) or "<none>"),
                }
                for _, property_name in ipairs(ANIM_INSTANCE_STATE_PROPERTIES) do
                    local value = state_property_text(object, property_name)
                    if value ~= nil then
                        table.insert(fields, property_name .. "=" .. value)
                    end
                end
                table.insert(names, table.concat(fields, ","))
            end
        end
        object = nil
    end
    if #names == 0 then
        return "<none>"
    end
    return table.concat(names, ";")
end

local function find_hanime_manager_state()
    if type(FindFirstOf) ~= "function" then
        return "<FindFirstOf-unavailable>"
    end
    for _, class_name in ipairs(MANAGER_CLASSES) do
        local ok, object = pcall(FindFirstOf, class_name)
        if ok and object ~= nil then
            local name = full_name(object)
            if name ~= nil and not string.find(name, "Default__", 1, true) then
                local fields = { class_name .. "=" .. name }
                for _, property_name in ipairs(MANAGER_STATE_PROPERTIES) do
                    local value = primitive_property_text(object, property_name)
                    if value ~= nil then
                        table.insert(fields, property_name .. "=" .. value)
                    end
                end
                object = nil
                return table.concat(fields, ",")
            end
        end
        object = nil
    end
    return "<none>"
end

function Probe.on_event(label, context, first_parameter, ...)
    label = tostring(label or "<unknown>")
    local count = tonumber(Probe.counts[label] or 0) + 1
    Probe.counts[label] = count

    local instance = unwrap(context)
    local first_object = unwrap(first_parameter)
    local component = owning_component(instance)
    local live_hanime_classes = label == "AnimInstance.Montage_Play"
        and find_live_human_anim_blueprints()
        or "<not-sampled>"
    local manager_state = label == "AnimInstance.Montage_Play"
        and find_hanime_manager_state()
        or "<not-sampled>"
    local message = string.format(
        "HAnime synchronous probe fired=%s count=%d instance=%s component=%s firstObject=%s liveHAnim=%s manager=%s",
        label,
        count,
        full_name(instance) or "<none>",
        full_name(component) or "<none>",
        full_name(first_object) or "<none>",
        live_hanime_classes,
        manager_state
    )

    -- Do not allow any UObject or RemoteUnrealParam wrapper to escape this
    -- callback. Only the formatted string is retained by the logger.
    instance = nil
    first_object = nil
    component = nil
    live_hanime_classes = nil
    manager_state = nil
    context = nil
    first_parameter = nil
    return message
end

function Probe.reset()
    Probe.counts = {}
end

local function register_direct_blueprint_hooks()
    _G.FD_TCODE_DIRECT_BLUEPRINT_HOOKS = _G.FD_TCODE_DIRECT_BLUEPRINT_HOOKS or {}
    _G.FD_TCODE_EVENT_PROBE_DISPATCH = function(label, ...)
        local message = Probe.on_event(label, ...)
        if message ~= nil then
            Log.info(tostring(message))
        end
    end

    for _, hook in ipairs(DIRECT_BLUEPRINT_HOOKS) do
        if not _G.FD_TCODE_DIRECT_BLUEPRINT_HOOKS[hook.path] then
            local hook_ok, pre_id, post_id = pcall(function()
                return RegisterHook(hook.path, function(...)
                    local args = { ... }
                    local dispatch = _G.FD_TCODE_EVENT_PROBE_DISPATCH
                    local ok, message = xpcall(function()
                        if type(dispatch) == "function" then
                            dispatch(hook.label, table.unpack(args))
                        end
                    end, debug.traceback)
                    args = nil
                    dispatch = nil
                    if not ok then
                        Log.error("direct Blueprint probe failed: " .. tostring(message))
                    end
                end)
            end)
            if hook_ok and (pre_id ~= nil or post_id ~= nil) then
                _G.FD_TCODE_DIRECT_BLUEPRINT_HOOKS[hook.path] = {
                    pre_id = pre_id,
                    post_id = post_id,
                }
                Log.info("HAnime direct Blueprint hook registered=" .. hook.path)
            else
                Log.warn(string.format(
                    "HAnime direct Blueprint hook unavailable path=%s reason=%s",
                    hook.path,
                    tostring(pre_id or post_id or "RegisterHook returned no ids")
                ))
            end
        end
    end
end

local function register_actor_lifecycle_hooks()
    if not _G.FD_TCODE_BEGIN_PLAY_PROBE_REGISTERED then
        local begin_ok, begin_error = pcall(function()
            RegisterBeginPlayPostHook(function(actor_parameter)
                local actor = unwrap(actor_parameter)
                if relevant_character_actor(actor) then
                    local dispatch = _G.FD_TCODE_EVENT_PROBE_DISPATCH
                    if type(dispatch) == "function" then
                        dispatch("Actor.BeginPlay", actor_parameter)
                    end
                    dispatch = nil
                end
                actor = nil
                actor_parameter = nil
            end)
        end)
        if begin_ok then
            _G.FD_TCODE_BEGIN_PLAY_PROBE_REGISTERED = true
            Log.info("HAnime character Actor BeginPlay probe registered")
        else
            Log.warn("HAnime character Actor BeginPlay probe unavailable: " .. tostring(begin_error))
        end
    end

    local end_path = "/Script/Engine.Actor:ReceiveEndPlay"
    _G.FD_TCODE_ACTOR_END_PLAY_HOOKS = _G.FD_TCODE_ACTOR_END_PLAY_HOOKS or {}
    if not _G.FD_TCODE_ACTOR_END_PLAY_HOOKS[end_path] then
        local end_ok, pre_id, post_id = pcall(function()
            return RegisterHook(end_path, function(context, ...)
                local actor = unwrap(context)
                if relevant_character_actor(actor) then
                    local args = { ... }
                    local dispatch = _G.FD_TCODE_EVENT_PROBE_DISPATCH
                    if type(dispatch) == "function" then
                        dispatch("Actor.ReceiveEndPlay", context, table.unpack(args))
                    end
                    args = nil
                    dispatch = nil
                end
                actor = nil
                context = nil
            end)
        end)
        if end_ok and (pre_id ~= nil or post_id ~= nil) then
            _G.FD_TCODE_ACTOR_END_PLAY_HOOKS[end_path] = {
                pre_id = pre_id,
                post_id = post_id,
            }
            Log.info("HAnime character Actor EndPlay hook registered=" .. end_path)
        else
            Log.warn(string.format(
                "HAnime character Actor EndPlay hook unavailable path=%s reason=%s",
                end_path,
                tostring(pre_id or post_id or "RegisterHook returned no ids")
            ))
        end
    end
end

register_direct_blueprint_hooks()
register_actor_lifecycle_hooks()

return Probe
