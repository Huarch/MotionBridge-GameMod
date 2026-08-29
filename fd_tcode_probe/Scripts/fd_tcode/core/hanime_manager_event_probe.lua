-- Development-only HAnime manager event probe for the UE 5.7 Playtest.
--
-- The callbacks synchronously convert their parameters to plain strings and
-- never retain a UObject/RemoteUnrealParam.  Until a complete enter/switch/
-- idle/exit trace has been verified, these hooks only log evidence and do not
-- change the production HAnime gate.

local Config = require("fd_tcode.config")
local Log = require("fd_tcode.core.log")

local Probe = {
    started = false,
    counts = {},
    register_attempts = 0,
}

local EVENT_HOOKS = {
    {
        label = "HAnimManager.EventAnimStateChange",
        path = "/Game/BP/HAnimManager.HAnimManager_C:EventAnimStateChange",
    },
    {
        label = "HAnimManager.EventAnimStateComplete",
        path = "/Game/BP/HAnimManager.HAnimManager_C:EventAnimStateComplete",
    },
    {
        label = "HAnimManager.EventBlendToComplete",
        path = "/Game/BP/HAnimManager.HAnimManager_C:EventBlendToComplete",
    },
    {
        label = "HAnimManager.EventStateChange",
        path = "/Game/BP/HAnimManager.HAnimManager_C:EventStateChange",
    },
    {
        label = "HAnimManager.PlayAnim",
        path = "/Game/BP/HAnimManager.HAnimManager_C:PlayAnim",
    },
    {
        label = "HAnimManager.StopMontage",
        path = "/Game/BP/HAnimManager.HAnimManager_C:StopMontage",
    },
    {
        label = "HSceneManager.EventActivateAnimID",
        path = "/Game/BP/HSceneManager.HSceneManager_C:EventActivateAnimID",
    },
    {
        label = "HSceneManager.EventChangeAnimState",
        path = "/Game/BP/HSceneManager.HSceneManager_C:EventChangeAnimState",
    },
}

local MANAGER_CLASSES = {
    "/Game/BP/HAnimManager.HAnimManager_C",
    "/Game/BP/HSceneManager.HSceneManager_C",
}

local function unwrap(value)
    if value == nil then
        return nil
    end
    local ok, unwrapped = pcall(function()
        return value:get()
    end)
    return ok and unwrapped or value
end

local function value_text(value)
    value = unwrap(value)
    if value == nil then
        return "<nil>"
    end
    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    local full_ok, full_name = pcall(function()
        return value:GetFullName()
    end)
    if full_ok and full_name ~= nil then
        return tostring(full_name)
    end
    local text_ok, text = pcall(function()
        return value:ToString()
    end)
    if text_ok and text ~= nil then
        return tostring(text)
    end
    return "<unreadable>"
end

local function event_callback(label)
    return function(...)
        local argument_count = select("#", ...)
        local fields = {}
        for index = 1, math.min(argument_count, 6) do
            fields[index] = value_text(select(index, ...))
        end
        local count = tonumber(Probe.counts[label] or 0) + 1
        Probe.counts[label] = count
        Log.info(string.format(
            "HAnime manager event=%s count=%d args=%s",
            label,
            count,
            #fields > 0 and table.concat(fields, " | ") or "<none>"
        ))

        -- Reserved for the validated event-driven gate.  Dispatch receives
        -- plain strings only; no Unreal wrapper is allowed to escape.
        local dispatch = _G.FD_TCODE_HANIME_MANAGER_EVENT_DISPATCH
        if type(dispatch) == "function" then
            local dispatch_ok, dispatch_error = xpcall(function()
                dispatch(label, fields)
            end, debug.traceback)
            if not dispatch_ok then
                Log.error("HAnime manager event dispatch failed: " .. tostring(dispatch_error))
            end
        end
        fields = nil
    end
end

function Probe.try_register()
    if Config.hanime_manager_event_probe_enabled ~= true or type(RegisterHook) ~= "function" then
        return 0
    end
    _G.FD_TCODE_HANIME_MANAGER_EVENT_HOOKS = _G.FD_TCODE_HANIME_MANAGER_EVENT_HOOKS or {}
    Probe.register_attempts = Probe.register_attempts + 1
    local registered = 0
    for _, hook in ipairs(EVENT_HOOKS) do
        if not _G.FD_TCODE_HANIME_MANAGER_EVENT_HOOKS[hook.path] then
            local hook_ok, pre_id, post_id = pcall(function()
                return RegisterHook(hook.path, event_callback(hook.label))
            end)
            if hook_ok and (pre_id ~= nil or post_id ~= nil) then
                _G.FD_TCODE_HANIME_MANAGER_EVENT_HOOKS[hook.path] = {
                    pre_id = pre_id,
                    post_id = post_id,
                }
                registered = registered + 1
                Log.info("HAnime manager hook registered=" .. hook.path)
            elseif Probe.register_attempts == 1 then
                Log.info(string.format(
                    "HAnime manager hook pending path=%s reason=%s",
                    hook.path,
                    tostring(pre_id or post_id or "function-not-loaded")
                ))
            end
        end
    end
    return registered
end

local function register_manager_creation_notifications()
    if type(NotifyOnNewObject) ~= "function" then
        return
    end
    _G.FD_TCODE_HANIME_MANAGER_CLASS_NOTIFIERS = _G.FD_TCODE_HANIME_MANAGER_CLASS_NOTIFIERS or {}
    for _, class_path in ipairs(MANAGER_CLASSES) do
        if not _G.FD_TCODE_HANIME_MANAGER_CLASS_NOTIFIERS[class_path] then
            local notify_ok, notify_error = pcall(function()
                NotifyOnNewObject(class_path, function(manager)
                    Probe.try_register()
                    manager = nil
                end)
            end)
            if notify_ok then
                _G.FD_TCODE_HANIME_MANAGER_CLASS_NOTIFIERS[class_path] = true
                Log.info("HAnime manager creation notifier registered=" .. class_path)
            else
                Log.info(string.format(
                    "HAnime manager creation notifier pending path=%s reason=%s",
                    class_path,
                    tostring(notify_error)
                ))
            end
        end
    end
end

function Probe.start()
    if Probe.started or Config.hanime_manager_event_probe_enabled ~= true then
        return
    end
    Probe.started = true
    Probe.try_register()
    register_manager_creation_notifications()
    Log.info("HAnime manager event probe active; events remain log-only during validation")
end

return Probe
