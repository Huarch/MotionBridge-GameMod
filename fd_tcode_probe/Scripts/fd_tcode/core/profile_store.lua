local Log = require("fd_tcode.core.log")
local Config = require("fd_tcode.config")

local ProfileStore = {
    generation = 0,
    data = {
        schema_version = 1,
        revision = "builtin-fallback",
        profiles = {},
    },
}

-- Static-formal sidecars are edition-isolated.  Demo and Playtest can reuse
-- an exact HAnime ID, so an absent/invalid edition is a refusal rather than a
-- cross-build fallback.
local static_sidecars_by_edition = {
    ["demo-ue4.25"] = {
        { file = "demo_static_formal_profile_data.lua", edition = "demo-ue4.25" },
    },
    ["playtest-ue5"] = {
        { file = "female_female_provisional_profile_data.lua", edition = "playtest-ue5" },
        { file = "nonhuman_static_formal_profile_data.lua", edition = "playtest-ue5" },
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

local function profile_path(file_name)
    local directory = source_directory()
    if directory == nil then
        return nil, "cannot resolve profile_store.lua source directory"
    end
    -- Runtime logic lives in core/, while generated rule tables live in the
    -- adjacent data/ layer. Keep loadfile sandboxing without flattening them.
    return directory .. "../data/" .. tostring(file_name or "profile_data.lua")
end

local function load_data_file(path)
    local load_ok, chunk, load_error = pcall(loadfile, path, "t", {})
    if not load_ok or chunk == nil then
        return nil, tostring(load_ok and load_error or chunk)
    end
    local ok, candidate = pcall(chunk)
    if not ok then
        return nil, tostring(candidate)
    end
    local valid, reason = validate(candidate)
    if not valid then
        return nil, tostring(reason)
    end
    return candidate, nil
end

function ProfileStore.reload()
    local path, path_error = profile_path("profile_data.lua")
    if path == nil then
        Log.error("rule refresh failed: " .. path_error)
        return false
    end
    if type(loadfile) ~= "function" then
        Log.error("rule refresh failed: loadfile is unavailable")
        return false
    end

    -- The empty environment permits table literals but prevents profile data
    -- from calling UE4SS or Unreal functions.
    local candidate, load_error = load_data_file(path)
    if candidate == nil then
        Log.error("rule refresh rejected; keeping previous rules: " .. tostring(load_error))
        return false
    end

    local game_edition = Config.game_edition
    local sidecar_names = static_sidecars_by_edition[game_edition]
    if sidecar_names == nil then
        Log.warn("static formal sidecars skipped: installed edition_local.lua (or FD_TCODE_GAME_EDITION fallback) must be demo-ue4.25 or playtest-ue5; got " .. tostring(game_edition))
    else
        for _, sidecar_spec in ipairs(sidecar_names) do
            local sidecar_name = sidecar_spec.file
            local sidecar_path = profile_path(sidecar_name)
            local sidecar, sidecar_error = load_data_file(sidecar_path)
            if sidecar ~= nil then
                for id, profile in pairs(sidecar.profiles or {}) do
                    local profile_edition = profile.edition
                    if profile_edition == nil and type(profile.staticEvidence) == "table" then
                        profile_edition = profile.staticEvidence.edition
                    end
                    if profile_edition ~= sidecar_spec.edition then
                        Log.warn("static formal profile skipped because sidecar edition does not match configured game: " .. tostring(id))
                    else
                        local existing = candidate.profiles[id]
                        if existing == nil or existing.status ~= "enabled_for_simulation_validation" then
                            candidate.profiles[id] = profile
                        else
                            Log.warn("static formal profile skipped because a calibrated profile already exists: " .. tostring(id))
                        end
                    end
                end
                candidate.revision = tostring(candidate.revision) .. "+" .. tostring(sidecar.revision)
                candidate.profile_count = count_entries(candidate.profiles)
            elseif sidecar_error ~= nil and string.find(tostring(sidecar_error), "cannot open", 1, true) == nil then
                Log.warn("static formal sidecar rejected (" .. tostring(sidecar_name) .. "); retaining loaded profiles: " .. tostring(sidecar_error))
            end
        end
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
