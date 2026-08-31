-- Low-frequency HAnime gate for the Demo runtime.
--
-- Menu and room-idle states run only this 4 Hz identity watcher. The 50 Hz
-- functional-bone loop is created after an exact HAnime is confirmed and
-- destroys itself when that gate becomes inactive.

local Config = require("fd_tcode.config")
local HAnimeDetector = require("fd_tcode.core.hanime_detector")
local Log = require("fd_tcode.core.log")
local SkeletonStream = require("fd_tcode.core.skeleton_stream")

local Gate = {
    running = false,
    loop_handle = nil,
    generation = 0,
    last_state_key = nil,
}

local function clear_runtime_stream()
    local ok, handle_or_error = pcall(io.open, Config.skeleton_spool_path, "w")
    if not ok or handle_or_error == nil then
        Log.warn("could not clear inactive skeleton stream: " .. tostring(handle_or_error))
        return false
    end
    pcall(function()
        handle_or_error:close()
    end)
    return true
end

local function state_key(status)
    local identity = status.identity or {}
    return table.concat({
        tostring(status.state or "inactive"),
        tostring(status.active == true),
        tostring(identity.hanime_id or "<none>"),
        tostring(status.reason or "<none>"),
    }, "|")
end

local function review_once()
    if not Gate.running
        or tonumber(_G.FD_TCODE_DEMO_GATE_GENERATION or 0) ~= Gate.generation
    then
        return
    end
    if SkeletonStream.is_running() then
        return
    end

    local status = HAnimeDetector.sample()
    local key = state_key(status)
    if key ~= Gate.last_state_key then
        Gate.last_state_key = key
        Log.info(string.format(
            "HAnime low-frequency gate state=%s active=%s id=%s reason=%s",
            tostring(status.state),
            tostring(status.active),
            tostring((status.identity or {}).hanime_id or "<none>"),
            tostring(status.reason or "<none>")
        ))
    end
    if status.active then
        SkeletonStream.start({
            initial_hanime = status,
            preserve_detector_cache = true,
            stop_when_inactive = true,
        })
    end
end

function Gate.notify_hanime_event()
    -- Events never read bones. If the high-rate stream is active they only
    -- request its next bounded identity review; otherwise the 4 Hz watcher
    -- will consume the queued component/Montage evidence.
    if SkeletonStream.is_running() then
        SkeletonStream.notify_hanime_event()
    end
end

function Gate.start()
    if type(LoopInGameThreadWithDelay) ~= "function" then
        Log.error("LoopInGameThreadWithDelay is unavailable in this UE4SS build")
        return
    end
    local previous_handle = _G.FD_TCODE_DEMO_GATE_HANDLE
    if previous_handle ~= nil and type(CancelDelayedAction) == "function" then
        pcall(CancelDelayedAction, previous_handle)
    end
    _G.FD_TCODE_DEMO_GATE_GENERATION = tonumber(_G.FD_TCODE_DEMO_GATE_GENERATION or 0) + 1
    Gate.generation = _G.FD_TCODE_DEMO_GATE_GENERATION
    Gate.running = true
    Gate.last_state_key = nil
    HAnimeDetector.clear_cache()
    clear_runtime_stream()
    Gate.loop_handle = LoopInGameThreadWithDelay(Config.hanime_poll_interval_ms, review_once)
    _G.FD_TCODE_DEMO_GATE_HANDLE = Gate.loop_handle
    ExecuteInGameThread(review_once)
    Log.info(string.format(
        "HAnime gate armed at %.1f Hz; 50 Hz skeleton sampling starts only after exact HAnime activation",
        1000 / Config.hanime_poll_interval_ms
    ))
end

return Gate
