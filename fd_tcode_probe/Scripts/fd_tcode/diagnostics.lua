local HScene = require("fd_tcode.hscene")
local BoneProbe = require("fd_tcode.bone_probe")
local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")
local SkeletonCatalog = require("fd_tcode.skeleton_catalog")

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

return Diagnostics
