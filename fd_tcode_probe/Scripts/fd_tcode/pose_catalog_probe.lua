local Config = require("fd_tcode.config")
local HScene = require("fd_tcode.hscene")
local Log = require("fd_tcode.log")
local Safe = require("fd_tcode.safe")

local PoseCatalogProbe = {}

-- Confirmed from the unpacked DataHAnim struct. Keep this static contract as
-- the primary path: FProperty wrappers in this UE4SS build are not UObjects
-- and must not be filtered through UObject:IsValid().
local DATA_HANIM_FIELDS = {
    "ID",
    "Name",
    "Position",
    "Group",
    "Type",
    "AnimType",
    "AnimState",
    "RoomID",
    "FemaleAnimNOR",
    "FemaleAnimSQ",
    "FemaleAnimMIN",
    "FemaleAnimMAX",
    "TargetAAnimNOR",
    "TargetAAnimSQ",
    "TargetAAnimMIN",
    "TargetAAnimMAX",
    "TargetBAnimNOR",
    "TargetBAnimSQ",
    "TargetBAnimMIN",
    "TargetBAnimMAX",
    "TargetCAnimNOR",
    "TargetCAnimSQ",
    "TargetCAnimMIN",
    "TargetCAnimMAX",
    "SpeedRate",
    "ItemClass",
    "AttachSocktes",
    "HitParts",
}

local function property_name(property)
    local ok, name = pcall(function()
        return property:GetFName():ToString()
    end)
    return ok and tostring(name) or "<unknown>"
end

local function property_type_name(property)
    local ok, name = pcall(function()
        return property:GetClass():GetFName():ToString()
    end)
    return ok and tostring(name) or "<unknown-property-type>"
end

local function struct_fields(return_property)
    if return_property == nil then
        return {}
    end

    local ok_inner, inner = pcall(function()
        return return_property:GetInner()
    end)
    if not ok_inner or not Safe.is_object(inner) then
        return {}
    end

    local ok_struct, struct = pcall(function()
        return inner:GetStruct()
    end)
    if not ok_struct or not Safe.is_object(struct) then
        return {}
    end

    local fields = {}
    struct:ForEachProperty(function(property)
        table.insert(fields, property_name(property))
    end)
    table.sort(fields)
    return fields
end

local function clean_cell(value)
    local text = Safe.value_text(value)
    text = tostring(text or "<nil>")
    text = string.gsub(text, "\t", " ")
    text = string.gsub(text, "\r", " ")
    text = string.gsub(text, "\n", " ")
    return text
end

local function read_field(value, field)
    local ok, result = pcall(function()
        return value[field]
    end)
    if not ok then
        return "<unreadable>"
    end
    return clean_cell(result)
end

local function payload(value)
    local ok, result = pcall(function()
        return value:get()
    end)
    return ok and result or value
end

local function container_type(container, property_kind)
    local ok, result = pcall(function()
        return container:type()
    end)
    if ok then
        return tostring(result), nil
    end
    local inferred = {
        ArrayProperty = "TArray",
        MapProperty = "TMap",
        SetProperty = "TSet",
    }
    return inferred[property_kind] or type(container), tostring(result)
end

local function append_entry(entries, index, value, fields, catalog_key)
    value = payload(value)
    local row = { index = tonumber(index) or (#entries + 1) }
    if catalog_key ~= nil then
        row.CatalogKey = clean_cell(payload(catalog_key))
    end
    for _, field in ipairs(fields) do
        row[field] = read_field(value, field)
    end
    table.insert(entries, row)
end

local function collect_entries(container, fields, property_kind)
    local entries = {}
    local kind, type_error = container_type(container, property_kind)

    if kind == "TArray" then
        local length_ok, length = pcall(function()
            return container:GetArrayNum()
        end)
        if not length_ok then
            return nil, "TArray length was unreadable: " .. tostring(length), kind, fields
        end
        for index = 1, length do
            local value_ok, value = pcall(function()
                return container[index]
            end)
            if value_ok then
                append_entry(entries, index, value, fields, nil)
            end
        end
        return entries, nil, kind, fields
    end

    if kind == "TMap" then
        local output_fields = { "CatalogKey" }
        for _, field in ipairs(fields) do
            table.insert(output_fields, field)
        end
        local ok, map_error = pcall(function()
            container:ForEach(function(key, value)
                append_entry(entries, #entries + 1, value, fields, key)
            end)
        end)
        if not ok then
            return nil, tostring(map_error), kind, output_fields
        end
        return entries, nil, kind, output_fields
    end

    if kind == "TSet" then
        local ok, set_error = pcall(function()
            container:ForEach(function(value)
                append_entry(entries, #entries + 1, value, fields, nil)
            end)
        end)
        if not ok then
            return nil, tostring(set_error), kind, fields
        end
        return entries, nil, kind, fields
    end

    return nil, "unsupported container type " .. tostring(kind)
        .. "; wrapperTypeError=" .. tostring(type_error), kind, fields
end

local function write_tsv(snapshot, source_name, session_state, reported_count, fields, entries)
    local path = Config.pose_catalog_path
    local file, open_error = io.open(path, "w")
    if file == nil then
        return false, "cannot open " .. tostring(path) .. ": " .. tostring(open_error)
    end

    file:write("# FD-TCode visible pose catalog\n")
    file:write("# source=", clean_cell(source_name), "\n")
    file:write("# sessionState=", clean_cell(session_state), "\n")
    file:write("# manager=", clean_cell(snapshot and snapshot.manager_name), "\n")
    file:write("# animManager=", clean_cell(snapshot and snapshot.anim_manager_name), "\n")
    file:write("# reportedCount=", clean_cell(reported_count), "\n")
    file:write("# exportedEntries=", tostring(#entries), "\n")
    file:write("index")
    local output_fields = fields
    if #output_fields == 0 then
        output_fields = { "Value" }
    end
    for _, field in ipairs(output_fields) do
        file:write("\t", field)
    end
    file:write("\n")

    for _, row in ipairs(entries) do
        file:write(tostring(row.index))
        for _, field in ipairs(output_fields) do
            file:write("\t", tostring(row[field] or "<nil>"))
        end
        file:write("\n")
    end
    file:close()
    return true, nil
end

local function get_sp_anim_count(hmanager)
    local output = {}
    local ok, call_error = pcall(function()
        hmanager:GetSPAnimCount(output)
    end)
    if not ok then
        return nil, tostring(call_error)
    end
    if type(output.Num) == "number" then
        return output.Num, nil
    end
    for _, value in pairs(output) do
        if type(value) == "number" then
            return value, nil
        end
    end
    return nil, "GetSPAnimCount completed but its Num output was absent"
end

local function function_signature(object, wanted_name)
    if not Safe.is_object(object) then
        return "<invalid-object>"
    end
    local class = object:GetClass()
    local depth = 0
    while Safe.is_object(class) and depth < 8 do
        local signature = nil
        class:ForEachFunction(function(func)
            local ok_name, name = pcall(function()
                return func:GetFName():ToString()
            end)
            if ok_name and tostring(name) == wanted_name then
                local params = {}
                func:ForEachProperty(function(property)
                    table.insert(params, property_name(property) .. ":" .. property_type_name(property))
                end)
                signature = wanted_name .. "(" .. table.concat(params, ",") .. ")"
                return true
            end
        end)
        if signature ~= nil then
            return signature
        end
        class = class:GetSuperStruct()
        depth = depth + 1
    end
    return wanted_name .. "(<not-reflected>)"
end

local function find_hmanager(snapshot)
    local outer = snapshot and snapshot.manager or nil
    local depth = 0
    while Safe.is_object(outer) and depth < 6 do
        if Safe.class_name(outer) == "HManager_C" then
            return outer, "selected manager outer " .. tostring(depth)
        end
        outer = Safe.outer(outer)
        depth = depth + 1
    end

    local ok, object = pcall(FindFirstOf, "HManager_C")
    if ok and Safe.is_object(object) then
        local name = Safe.object_name(object) or ""
        if not string.find(name, "Default__", 1, true) then
            return object, "FindFirstOf(HManager_C)"
        end
    end
    return nil, nil
end

local function find_property(object, wanted_name)
    if not Safe.is_object(object) then
        return nil, nil
    end
    local class = object:GetClass()
    local depth = 0
    while Safe.is_object(class) and depth < 8 do
        local found = nil
        local found_name = nil
        class:ForEachProperty(function(property)
            local name = property_name(property)
            if name == wanted_name
                or string.find(name, wanted_name .. "_", 1, true) == 1 then
                found = property
                found_name = name
                return true
            end
        end)
        if found ~= nil then
            return found, found_name
        end
        class = class:GetSuperStruct()
        depth = depth + 1
    end
    return nil, nil
end

function PoseCatalogProbe.export_visible()
    local snapshot = HScene.snapshot()
    local hmanager, source_name = find_hmanager(snapshot)
    if not Safe.is_object(hmanager) then
        Log.warn("F8 pose export skipped: no live HManager_C; state="
            .. tostring(snapshot.reason or "uninitialized"))
        return
    end

    local reported_count, count_error = get_sp_anim_count(hmanager)
    if reported_count == nil then
        Log.warn("F8 GetSPAnimCount failed safely: " .. tostring(count_error))
        return
    end

    local local_hdatas_property = find_property(hmanager, "LocalHDatas")
    local property_kind = local_hdatas_property and property_type_name(local_hdatas_property)
        or "<property-not-found>"

    local ok_array, pose_list = Safe.read(hmanager, "LocalHDatas")
    if local_hdatas_property == nil or not ok_array or pose_list == nil then
        local session_state = snapshot.valid and "session-count-only" or "main-menu-count-only"
        local wrote, write_error = write_tsv(
            snapshot,
            source_name .. " " .. tostring(Safe.object_name(hmanager)),
            session_state,
            reported_count,
            {},
            {}
        )
        if not wrote then
            Log.warn("F8 count-only export failed safely: " .. tostring(write_error))
            return
        end
        Log.info(string.format(
            "F8 HManager state=%s reportedCount=%s LocalHDatas=blueprint-local signature=%s path=%s",
            session_state,
            clean_cell(reported_count),
            function_signature(hmanager, "GetDatabyCardID"),
            Config.pose_catalog_path
        ))
        return
    end

    local fields = DATA_HANIM_FIELDS
    local entries, collect_error, container_kind, output_fields = collect_entries(
        pose_list,
        fields,
        property_kind
    )
    if entries == nil then
        local struct_field_text = "<not-struct>"
        if local_hdatas_property ~= nil and property_kind == "StructProperty" then
            local ok_struct, struct = pcall(function()
                return local_hdatas_property:GetStruct()
            end)
            if ok_struct and struct ~= nil then
                local names = {}
                pcall(function()
                    struct:ForEachProperty(function(field)
                        table.insert(names, property_name(field) .. ":" .. property_type_name(field))
                    end)
                end)
                struct_field_text = table.concat(names, ",")
            end
        end
        Log.warn("F8 LocalHDatas export failed safely: propertyType=" .. tostring(property_kind)
            .. " wrapperType=" .. tostring(container_kind)
            .. " structFields=" .. tostring(struct_field_text)
            .. " error=" .. tostring(collect_error))
        return
    end

    local session_state = "session-loaded"
    if #entries == 0 then
        session_state = snapshot.valid and "session-empty" or "main-menu-uninitialized"
    elseif not snapshot.valid then
        session_state = "catalog-loaded-no-active-hscene"
    end

    local wrote, write_error = write_tsv(
        snapshot,
        source_name .. " " .. tostring(Safe.object_name(hmanager)),
        session_state,
        reported_count,
        output_fields,
        entries
    )
    if not wrote then
        Log.warn("F8 pose export failed safely: " .. tostring(write_error))
        return
    end
    Log.info(string.format(
        "F8 HManager state=%s reportedCount=%s container=%s exportedEntries=%d path=%s",
        session_state,
        clean_cell(reported_count),
        tostring(container_kind),
        #entries,
        Config.pose_catalog_path
    ))
end

return PoseCatalogProbe
