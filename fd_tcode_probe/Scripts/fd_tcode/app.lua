local Config = require("fd_tcode.config")
local HAnimeDetector = require("fd_tcode.core.hanime_detector")
local HAnimeStreamGate = require("fd_tcode.core.hanime_stream_gate")
local Log = require("fd_tcode.core.log")
local PoseCatalogProbe = require("fd_tcode.core.pose_catalog_probe")
local ProfileStore = require("fd_tcode.core.profile_store")
local Runtime = require("fd_tcode.core.runtime")
local Safe = require("fd_tcode.core.safe")

local App = {}
local precision_capture = nil
local precision_capture_attempted = false

local function optional_precision_capture()
    if Config.precision_capture_enabled ~= true then
        return nil
    end
    if precision_capture_attempted then
        return precision_capture
    end
    precision_capture_attempted = true

    local ok, module_or_error = pcall(require, "fd_tcode.core.precision_capture")
    if not ok then
        Log.error("precision capture module failed to load: " .. tostring(module_or_error))
        return nil
    end
    precision_capture = module_or_error
    return precision_capture
end

local function register_hanime_events()
    local created_ok, created_error = pcall(function()
        NotifyOnNewObject("/Script/Engine.SkeletalMeshComponent", function(component)
            HAnimeDetector.queue_component(component)
            local capture = optional_precision_capture()
            if capture ~= nil then
                capture.queue_component(component)
            end
            HAnimeStreamGate.notify_hanime_event()
        end)
    end)
    if not created_ok then
        Log.warn("SkeletalMeshComponent event unavailable: " .. tostring(created_error))
    end

    local montage_ok, montage_error = pcall(function()
        RegisterHook("/Script/Engine.AnimInstance:Montage_Play", function(self)
            local instance_ok, instance = pcall(function()
                return self:get()
            end)
            if instance_ok and Safe.is_object(instance) then
                local component_ok, component = pcall(function()
                    return instance:GetOwningComponent()
                end)
                if component_ok and component ~= nil then
                    HAnimeDetector.queue_component(component)
                end
            end
            HAnimeStreamGate.notify_hanime_event()
        end)
    end)
    if not montage_ok then
        Log.warn("Montage_Play event unavailable: " .. tostring(montage_error))
    end
end

local function register_keys()
    RegisterKeyBind(Config.keys.toggle_runtime, Runtime.toggle)
    RegisterKeyBind(Config.keys.export_pose_catalog, PoseCatalogProbe.export_visible)
end

function App.start()
    ProfileStore.reload()
    register_keys()
    register_hanime_events()
    HAnimeStreamGate.start()
    local capture = optional_precision_capture()
    if capture ~= nil then
        capture.start()
    end
    Log.info(string.format("version=%s loaded", Config.version))
    Log.info("SIMULATION ONLY / DEVICE DISABLED")
    Log.info("F6 monitor on/off | F7 external F8Studio | F8 export current pose list | F10 full Lua reload via broker")
    Log.info(string.format(
        "idle HAnime gate armed at %.1f Hz; functional bones sample at %.1f Hz only during exact HAnime",
        1000 / Config.hanime_poll_interval_ms,
        1000 / Config.skeleton_sample_interval_ms
    ))
end

return App
