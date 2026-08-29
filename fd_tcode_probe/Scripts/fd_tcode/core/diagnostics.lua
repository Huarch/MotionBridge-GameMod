local HScene = require("fd_tcode.core.hscene")
local BoneProbe = require("fd_tcode.core.bone_probe")
local Log = require("fd_tcode.core.log")
local Safe = require("fd_tcode.core.safe")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local Diagnostics = {}

local function emit_lines(title, lines)
    Log.info("----- " .. title .. " -----")
    for _, line in ipairs(lines) do
        Log.info(line)
    end
    Log.info("----- end " .. title .. " -----")
end

function Diagnostics.snapshot(detailed)
    local snapshot = HScene.snapshot()
    emit_lines(detailed and "HScene detailed snapshot" or "HScene snapshot", HScene.lines(snapshot, detailed))
    if detailed then
        local bone_snapshot = BoneProbe.snapshot()
        emit_lines("manual bone probe", BoneProbe.lines(bone_snapshot))
    end
    return snapshot
end

local function interesting_property(name)
    local lower = string.lower(name)
    return string.find(lower, "anim", 1, true)
        or string.find(lower, "current", 1, true)
        or string.find(lower, "target", 1, true)
        or string.find(lower, "character", 1, true)
        or string.find(lower, "state", 1, true)
        or string.find(lower, "speed", 1, true)
        or string.find(lower, "group", 1, true)
end

function Diagnostics.dump_manager_schema()
    local snapshot = HScene.snapshot()
    if not snapshot.valid then
        Log.warn(snapshot.reason)
        return
    end

    local function dump_object(label, object)
        if not Safe.is_object(object) then
            Log.warn(label .. " is unresolved")
            return
        end
        Log.info("----- " .. label .. " schema: " .. tostring(Safe.object_name(object)) .. " -----")
        local class = object:GetClass()
        local depth = 0
        while Safe.is_object(class) and depth < 6 do
            Log.info("class=" .. tostring(Safe.object_name(class)))
            class:ForEachProperty(function(property)
                local name = property:GetFName():ToString()
                if interesting_property(name) then
                    local text = Safe.property_text(object, name)
                    Log.info(string.format("property.%s=%s", name, tostring(text or "<unreadable>")))
                end
            end)
            class:ForEachFunction(function(fn)
                local name = fn:GetFName():ToString()
                if interesting_property(name) then
                    Log.info("function=" .. tostring(fn:GetFullName()))
                end
            end)
            class = class:GetSuperStruct()
            depth = depth + 1
        end
    end

    dump_object("HSceneManager", snapshot.manager)
    dump_object("HAnimManager", snapshot.anim_manager)
end

function Diagnostics.runtime_inventory()
    local classes = {
        "HSceneManager_C",
        "HAnimManager_C",
        "HStateManager_C",
        "AnimInstance",
        "SkeletalMeshComponent",
    }
    local lines = {}
    for _, class_name in ipairs(classes) do
        local ok, values = pcall(FindAllOf, class_name)
        local count = 0
        if ok and values ~= nil then
            for _ in pairs(values) do
                count = count + 1
            end
        end
        table.insert(lines, string.format("%s=%d", class_name, count))
    end
    emit_lines("runtime inventory", lines)
end

local ada_probe_bones = {
    "M_Gen", "M_AnusInside", "M_Anus_Inside", "M_Anus_Inside1",
    "M_Jaw", "M_Jaw_master", "Jaw_master", "M_TongueRoot",
}

local function socket_is_valid(component, bone_name)
    local ok, transform = pcall(function()
        return component:GetSocketTransform(FName(bone_name), 0)
    end)
    if not ok then
        return false
    end
    local values = Safe.transform_values(transform)
    local valid = values ~= nil and Safe.is_valid_transform(values)
    return valid == true
end

-- Explicit, on-demand inventory for a newly added character. This is never
-- used by the sampling path: it lets us bind a new mesh from one captured
-- scene rather than guessing its skeleton from a name.
function Diagnostics.skeletal_mesh_inventory()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        Log.warn("skeletal mesh inventory failed: " .. tostring(values))
        return
    end
    local lines = {}
    for _, component in pairs(values) do
        if Safe.is_object(component) then
            local name = Safe.object_name(component) or "<unnamed>"
            if not string.find(name, "Default__", 1, true) then
                local role, entry, binding = SkeletonCatalog.match_component(component)
                local live_bones = {}
                for _, bone_name in ipairs(ada_probe_bones) do
                    if socket_is_valid(component, bone_name) then
                        table.insert(live_bones, bone_name)
                    end
                end
                table.insert(lines, string.format(
                    "component=%s catalog=%s method=%s bones=%s",
                    name,
                    tostring(entry and entry.id or "unmapped"),
                    tostring(binding and binding.method or "unmapped"),
                    #live_bones > 0 and table.concat(live_bones, ",") or "<none>"
                ))
            end
        end
    end
    table.sort(lines)
    emit_lines("on-demand skeletal mesh inventory", lines)
end

local function target_main_component(name)
    if name == nil then
        return false
    end
    return (string.find(name, "A_CharacterAlet_", 1, true)
            and string.find(name, ".Mesh_Main", 1, true))
        or (string.find(name, "A_CharacterMaleB_", 1, true)
            and string.find(name, ".Mesh_MaleB", 1, true))
end

local function animation_property(name)
    local lower = string.lower(tostring(name or ""))
    return string.find(lower, "anim", 1, true)
        or string.find(lower, "montage", 1, true)
        or string.find(lower, "sequence", 1, true)
        or string.find(lower, "state", 1, true)
        or string.find(lower, "asset", 1, true)
        or string.find(lower, "graph", 1, true)
end

local function log_selected_properties(label, object, max_depth)
    if not Safe.is_object(object) then
        Log.info(label .. "=<unresolved>")
        return
    end
    Log.info(label .. "=" .. tostring(Safe.object_name(object)))
    local class = object:GetClass()
    local depth = 0
    while Safe.is_object(class) and depth < max_depth do
        Log.info(label .. ".class=" .. tostring(Safe.object_name(class)))
        class:ForEachProperty(function(property)
            local property_name = property:GetFName():ToString()
            if animation_property(property_name) then
                local value_text = Safe.property_text(object, property_name)
                Log.info(string.format(
                    "%s.property.%s=%s",
                    label,
                    tostring(property_name),
                    tostring(value_text or "<unreadable>")
                ))
            end
        end)
        class = class:GetSuperStruct()
        depth = depth + 1
    end
end

-- UE 5.7 targeted animation-path capture. This is deliberately one-shot and
-- restricted to the two current participant body components; it never runs in
-- the realtime sampling loop.
function Diagnostics.animation_path_snapshot()
    local ok, values = pcall(FindAllOf, "SkeletalMeshComponent")
    if not ok or values == nil then
        Log.warn("animation path snapshot failed: " .. tostring(values))
        return
    end
    Log.info("----- UE 5.7 targeted animation path -----")
    local matched = 0
    for _, component in pairs(values) do
        local component_name = Safe.object_name(component)
        if target_main_component(component_name) then
            matched = matched + 1
            local prefix = "target[" .. tostring(matched) .. "]"
            Log.info(prefix .. ".component=" .. tostring(component_name))
            for _, property_name in ipairs({
                "SkinnedAsset", "SkeletalMesh", "AnimationMode", "AnimClass",
                "AnimScriptInstance", "PostProcessAnimInstance"
            }) do
                local value_text = Safe.property_text(component, property_name)
                Log.info(string.format(
                    "%s.componentProperty.%s=%s",
                    prefix,
                    property_name,
                    tostring(value_text or "<unreadable>")
                ))
            end
            local anim_ok, anim_instance = pcall(function()
                return component:GetAnimInstance()
            end)
            Log.info(prefix .. ".GetAnimInstance.ok=" .. tostring(anim_ok))
            log_selected_properties(prefix .. ".animInstance", anim_instance, 5)
            if Safe.is_object(anim_instance) then
                local montage_ok, montage = pcall(function()
                    return anim_instance:GetCurrentActiveMontage()
                end)
                Log.info(string.format(
                    "%s.GetCurrentActiveMontage.ok=%s value=%s",
                    prefix,
                    tostring(montage_ok),
                    tostring(Safe.value_text(montage))
                ))
            end
        end
    end
    Log.info("targetedComponents=" .. tostring(matched))
    Log.info("----- end UE 5.7 targeted animation path -----")
end

return Diagnostics
