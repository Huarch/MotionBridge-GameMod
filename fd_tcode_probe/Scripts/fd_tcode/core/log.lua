local Config = require("fd_tcode.config")

local Log = {}
local seen = {}

local function emit(level, message)
    print(string.format("[%s][%s] %s\n", Config.name, level, tostring(message)))
end

function Log.info(message)
    -- Older hot-loaded stream loops may still call this every 20 frames. Keep
    -- the filter here as well as in skeleton_stream so F10 can remove that
    -- periodic UE4SS console/file write without a full Mod restart.
    local sample_number = tonumber(string.match(tostring(message or ""), "^skeleton sample=(%d+)"))
    local interval = math.max(1, tonumber(Config.skeleton_log_interval_frames or 500))
    if sample_number ~= nil and sample_number ~= 1 and sample_number % interval ~= 0 then
        return
    end
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
