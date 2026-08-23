local Config = require("fd_tcode.config")
local Diagnostics = require("fd_tcode.diagnostics")
local HScene = require("fd_tcode.hscene")
local Log = require("fd_tcode.log")
local PoseResolver = require("fd_tcode.pose_resolver")
local SkeletonStream = require("fd_tcode.skeleton_stream")

local Runtime = {
    monitoring = false,
    loop_handle = nil,
    last_fingerprint = nil,
}

local function monitor_once()
    if not Runtime.monitoring then
        return
    end
    local snapshot = HScene.snapshot()
    local pose, resolution = PoseResolver.resolve(snapshot)
    local fingerprint = HScene.fingerprint(snapshot)
        .. "|pose=" .. tostring(pose and pose.id or "<unmapped>")
        .. "|poseStatus=" .. tostring(pose and pose.status or resolution.reason)
    if fingerprint ~= Runtime.last_fingerprint then
        Runtime.last_fingerprint = fingerprint
        local lines = HScene.lines(snapshot, false)
        Log.info("HScene state changed")
        for _, line in ipairs(lines) do
            Log.info(line)
        end
        for _, line in ipairs(PoseResolver.lines(pose, resolution)) do
            Log.info(line)
        end
    end
end

function Runtime.start()
    if Runtime.monitoring then
        return
    end
    if type(LoopInGameThreadWithDelay) ~= "function" then
        Log.error("LoopInGameThreadWithDelay is unavailable in this UE4SS build")
        return
    end

    Runtime.monitoring = true
    Runtime.last_fingerprint = nil
    Runtime.loop_handle = LoopInGameThreadWithDelay(Config.monitor_interval_ms, monitor_once)
    Log.info("runtime monitor enabled; simulation and device output remain disabled")
    ExecuteInGameThread(monitor_once)
end

function Runtime.stop()
    if not Runtime.monitoring then
        return
    end
    Runtime.monitoring = false
    if Runtime.loop_handle ~= nil and type(CancelDelayedAction) == "function" then
        CancelDelayedAction(Runtime.loop_handle)
    end
    Runtime.loop_handle = nil
    Runtime.last_fingerprint = nil
    Log.info("runtime monitor disabled")
end

function Runtime.toggle()
    if Runtime.monitoring then
        Runtime.stop()
    else
        Runtime.start()
    end
end

function Runtime.snapshot()
    ExecuteInGameThread(function()
        Diagnostics.snapshot(true)
    end)
end

function Runtime.toggle_skeleton_stream()
    SkeletonStream.toggle()
end

return Runtime
