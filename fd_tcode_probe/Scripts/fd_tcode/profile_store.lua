local Log = require("fd_tcode.log")

local ProfileStore = {
    generation = 0,
    data = {
        schema_version = 1,
        revision = "builtin-fallback",
        profiles = {},
    },
}

local function source_directory()
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
        return nil
    end
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""
    if string.sub(source, 1, 1) == "@" then
        source = string.sub(source, 2)
    end
    return string.match(source, "^(.*[\\/])")
end

local function count_entries(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function validate_plain_value(value, seen, depth)
    local value_type = type(value)
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return false, "profile numbers must be finite"
        end
        return true
    end
    if value_type == "string" or value_type == "boolean" then
        return true
    end
    if value_type ~= "table" then
        return false, "unsupported value type: " .. value_type
    end
    if depth > 16 then
        return false, "profile data nesting exceeds 16 levels"
    end
    if getmetatable(value) ~= nil then
        return false, "metatables are not allowed in profile data"
    end
    if seen[value] then
        return false, "cyclic tables are not allowed in profile data"
    end

    seen[value] = true
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type ~= "string" and key_type ~= "number" then
            seen[value] = nil
            return false, "profile keys must be strings or numbers"
        end
        local ok, reason = validate_plain_value(child, seen, depth + 1)
        if not ok then
            seen[value] = nil
            return false, reason
        end
    end
    seen[value] = nil
    return true
end

local function validate(data)
    if type(data) ~= "table" then
        return false, "profile file must return a table"
    end
    if data.schema_version ~= 1 then
        return false, "unsupported schema_version: " .. tostring(data.schema_version)
    end
    if type(data.revision) ~= "string" and type(data.revision) ~= "number" then
        return false, "revision must be a string or number"
    end
    if type(data.profiles) ~= "table" then
        return false, "profiles must be a table"
    end
    return validate_plain_value(data, {}, 0)
end

local function profile_path()
    local directory = source_directory()
    if directory == nil then
        return nil, "cannot resolve profile_store.lua source directory"
    end
    return directory .. "profile_data.lua"
end

function ProfileStore.reload()
    local path, path_error = profile_path()
    if path == nil then
        Log.error("rule refresh failed: " .. path_error)
        return false
    end
    if type(loadfile) ~= "function" then
        Log.error("rule refresh failed: loadfile is unavailable")
        return false
    end

    -- The empty environment permits table literals but prevents the data file
    -- from calling UE4SS or Unreal functions.
    local load_ok, chunk, load_error = pcall(loadfile, path, "t", {})
    if not load_ok then
        Log.error("rule refresh failed; keeping previous rules: " .. tostring(chunk))
        return false
    end
    if chunk == nil then
        Log.error("rule refresh failed; keeping previous rules: " .. tostring(load_error))
        return false
    end

    local ok, candidate = pcall(chunk)
    if not ok then
        Log.error("rule refresh failed; keeping previous rules: " .. tostring(candidate))
        return false
    end

    local valid, reason = validate(candidate)
    if not valid then
        Log.error("rule refresh rejected; keeping previous rules: " .. tostring(reason))
        return false
    end

    ProfileStore.data = candidate
    ProfileStore.generation = ProfileStore.generation + 1
    Log.info(string.format(
        "rules loaded revision=%s profiles=%d generation=%d",
        tostring(candidate.revision),
        count_entries(candidate.profiles),
        ProfileStore.generation
    ))
    return true
end

function ProfileStore.current()
    return ProfileStore.data, ProfileStore.generation
end

return ProfileStore
