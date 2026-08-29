-- Event-armed HManager state cache.
--
-- Discovery is allowed only when requested by the detector.  Ordinary reads
-- touch a few properties on cached objects and never perform a global scan.

local Config = require("fd_tcode.config")
local HScene = require("fd_tcode.core.hscene")
local Safe = require("fd_tcode.core.safe")

local State = {
    manager = nil,
    anim_manager = nil,
}

function State.observe(object)
    if not Safe.is_object(object) then
        return false
    end
    local class_name = Safe.class_name(object) or ""
    if string.find(class_name, "HAnimManager", 1, true) then
        State.anim_manager = object
        if not Safe.is_object(State.manager) then
            State.manager = object
        end
        return true
    end
    if string.find(class_name, "HSceneManager", 1, true)
        or class_name == "HManager_C"
        or class_name == "HManager"
    then
        State.manager = object
        return true
    end
    return false
end

local function bind_objects()
    if Safe.is_object(State.manager) then
        return true
    end
    local snapshot = HScene.snapshot()
    if snapshot.valid ~= true or not Safe.is_object(snapshot.manager) then
        State.manager = nil
        State.anim_manager = nil
        return false
    end
    State.manager = snapshot.manager
    State.anim_manager = Safe.is_object(snapshot.anim_manager)
        and snapshot.anim_manager
        or nil
    return true
end

function State.read(allow_discovery)
    if not Safe.is_object(State.manager) then
        if allow_discovery ~= true or not bind_objects() then
            return {}
        end
    end

    local values = {}
    for _, property_name in ipairs(Config.animation_properties or {}) do
        -- Demo HManager_C owns AnimID/CurrAnimState. HAnimManager is only a
        -- fallback for fields absent from the authoritative manager.
        local text = Safe.property_text(State.manager, property_name)
        if text == nil and Safe.is_object(State.anim_manager) then
            text = Safe.property_text(State.anim_manager, property_name)
        end
        if text ~= nil and not string.find(text, "TrivialObject:", 1, true) then
            values[property_name] = text
        end
    end
    return {
        valid = true,
        manager = Safe.object_name(State.manager),
        anim_id = values.AnimID or values.CurrentAnimID or values.AnimationID,
        current_state = values.CurrAnimState or values.CurrentState or values.AnimState,
        current_animation = values.CurrentAnimation or values.AnimName or values.AnimationName,
        current_montage = values.CurrentMontage,
        current_section = values.CurrentSection,
        values = values,
    }
end

function State.clear()
    State.manager = nil
    State.anim_manager = nil
end

return State
