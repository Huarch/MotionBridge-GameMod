local Config = require("fd_tcode.config")

local Log = {}
local seen = {}

local function emit(level, message)
    print(string.format("[%s][%s] %s\n", Config.name, level, tostring(message)))
end

function Log.info(message)
    emit("INFO", message)
end

function Log.warn(message)
    emit("WARN", message)
end

function Log.error(message)
    emit("ERROR", message)
end

function Log.once(key, level, message)
    if seen[key] then
        return
    end
    seen[key] = true
    emit(level, message)
end

return Log
