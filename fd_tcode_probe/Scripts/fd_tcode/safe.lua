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
    if ok then
        return name
    end
    return nil
end

function Safe.class_name(value)
    if not Safe.is_object(value) then
        return nil
    end
    local ok, name = pcall(function()
        return value:GetClass():GetFName():ToString()
    end)
    if ok then
        return name
    end
    return nil
end

function Safe.outer(value)
    if not Safe.is_object(value) then
        return nil
    end
    local ok, outer = pcall(function()
        return value:GetOuter()
    end)
    if ok and Safe.is_object(outer) then
        return outer
    end
    return nil
end

function Safe.read(object, property_name)
    if not Safe.is_object(object) then
        return false, nil
    end
    return pcall(function()
        return object[property_name]
    end)
end

function Safe.value_text(value)
    if value == nil then
        return "<nil>"
    end

    local lua_type = type(value)
    if lua_type == "string" or lua_type == "number" or lua_type == "boolean" then
        return tostring(value)
    end

    local object_name = Safe.object_name(value)
    if object_name ~= nil then
        return object_name
    end

    if lua_type == "userdata" then
        local vector_ok, x, y, z = pcall(function()
            return value.X, value.Y, value.Z
        end)
        if vector_ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            return string.format("(%.3f, %.3f, %.3f)", x, y, z)
        end

        local string_ok, text = pcall(function()
            return value:ToString()
        end)
        if string_ok and text ~= nil then
            return tostring(text)
        end
    end

    local ok, text = pcall(tostring, value)
    if ok then
        return text
    end
    return "<" .. lua_type .. ">"
end

local function number_field(value, name)
    local ok, result = pcall(function()
        return value[name]
    end)
    if ok and type(result) == "number" then
        return result
    end
    return nil
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
    local px = number_field(translation, "X")
    local py = number_field(translation, "Y")
    local pz = number_field(translation, "Z")
    local qx = number_field(rotation, "X")
    local qy = number_field(rotation, "Y")
    local qz = number_field(rotation, "Z")
    local qw = number_field(rotation, "W")
    if px == nil or py == nil or pz == nil or qx == nil or qy == nil or qz == nil or qw == nil then
        return nil
    end
    return {
        position = { px, py, pz },
        rotation = { qx, qy, qz, qw },
    }
end

function Safe.is_finite_number(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Safe.is_valid_transform(value)
    if type(value) ~= "table" or type(value.position) ~= "table" or type(value.rotation) ~= "table" then
        return false, "transform structure is incomplete"
    end
    for index = 1, 3 do
        if not Safe.is_finite_number(value.position[index]) then
            return false, "position is not finite"
        end
    end
    local rotation_norm_squared = 0
    for index = 1, 4 do
        local component = value.rotation[index]
        if not Safe.is_finite_number(component) then
            return false, "rotation is not finite"
        end
        rotation_norm_squared = rotation_norm_squared + component * component
    end
    -- GetSocketTransform may succeed on an inactive/unregistered component
    -- while returning the all-zero FTransform. A real quaternion is unit
    -- length, so this catches that state without rejecting a valid origin.
    if rotation_norm_squared < 0.25 then
        return false, "rotation quaternion is zero"
    end
    return true, nil
end

local function vector_text(value)
    if value == nil then
        return nil
    end
    local x = number_field(value, "X")
    local y = number_field(value, "Y")
    local z = number_field(value, "Z")
    if x == nil or y == nil or z == nil then
        return nil
    end
    return string.format("(%.3f,%.3f,%.3f)", x, y, z)
end

local function quaternion_text(value)
    if value == nil then
        return nil
    end
    local x = number_field(value, "X")
    local y = number_field(value, "Y")
    local z = number_field(value, "Z")
    local w = number_field(value, "W")
    if x == nil or y == nil or z == nil or w == nil then
        return nil
    end
    return string.format("(X=%.6f,Y=%.6f,Z=%.6f,W=%.6f)", x, y, z, w)
end

function Safe.transform_text(value)
    if value == nil then
        return "<nil>"
    end
    local ok, translation, rotation, scale = pcall(function()
        return value.Translation, value.Rotation, value.Scale3D
    end)
    if ok then
        local translation_text = vector_text(translation)
        local rotation_text = quaternion_text(rotation)
        local scale_text = vector_text(scale)
        if translation_text ~= nil and rotation_text ~= nil then
            return string.format(
                "T=%s Q=%s S=%s",
                translation_text,
                rotation_text,
                tostring(scale_text or "<unreadable>")
            )
        end
    end
    return Safe.value_text(value)
end

function Safe.property_text(object, property_name)
    local ok, value = Safe.read(object, property_name)
    if not ok then
        return nil
    end
    return Safe.value_text(value), value
end

return Safe
