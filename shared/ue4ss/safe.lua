-- Generic defensive helpers for UE4SS game Mods.
-- Keep game-specific object names and bone choices in the game branch.

local Safe = {}

function Safe.call(callback, ...)
    local args = { ... }
    return pcall(function()
        return callback(table.unpack(args))
    end)
end

function Safe.is_object(value)
    if value == nil or type(value) ~= "userdata" then
        return false
    end
    local ok, valid = pcall(function()
        return value:IsValid()
    end)
    return ok and valid == true
end

function Safe.object_name(value)
    if not Safe.is_object(value) then
        return nil
    end
    local ok, name = pcall(function()
        return value:GetFullName()
    end)
    return ok and tostring(name) or nil
end

function Safe.read(object, property_name)
    if not Safe.is_object(object) then
        return false, nil
    end
    return pcall(function()
        return object[property_name]
    end)
end

local function number_field(value, name)
    local ok, result = pcall(function()
        return value[name]
    end)
    return ok and type(result) == "number" and result or nil
end

function Safe.transform_values(value)
    if value == nil then
        return nil
    end
    local ok, translation, rotation = pcall(function()
        return value.Translation, value.Rotation
    end)
    if not ok then
        return nil
    end

    local position = {
        number_field(translation, "X"),
        number_field(translation, "Y"),
        number_field(translation, "Z"),
    }
    local quaternion = {
        number_field(rotation, "X"),
        number_field(rotation, "Y"),
        number_field(rotation, "Z"),
        number_field(rotation, "W"),
    }
    for _, component in ipairs(position) do
        if type(component) ~= "number" then
            return nil
        end
    end
    for _, component in ipairs(quaternion) do
        if type(component) ~= "number" then
            return nil
        end
    end
    return { position = position, rotation = quaternion }
end

return Safe
