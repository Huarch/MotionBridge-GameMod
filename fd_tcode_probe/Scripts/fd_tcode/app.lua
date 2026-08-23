local Config = require("fd_tcode.config")
local HAnimeDetector = require("fd_tcode.hanime_detector")
local Log = require("fd_tcode.log")
local PoseCatalogProbe = require("fd_tcode.pose_catalog_probe")
local ProfileStore = require("fd_tcode.profile_store")
local Runtime = require("fd_tcode.runtime")
local Safe = require("fd_tcode.safe")
local SkeletonStream = require("fd_tcode.skeleton_stream")

local App = {}

local function register_hanime_events()
    local created_ok, created_error = pcall(function()
        NotifyOnNewObject("/Script/Engine.SkeletalMeshComponent", function(component)
            HAnimeDetector.queue_component(component)
            SkeletonStream.notify_hanime_event()
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
            SkeletonStream.notify_hanime_event()
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
    SkeletonStream.start()
    Log.info(string.format("version=%s loaded", Config.version))
    Log.info("SIMULATION ONLY / DEVICE DISABLED")
    Log.info("F6 monitor on/off | F7 external F8Studio | F8 export current pose list | F10 full Lua reload via broker")
    Log.info(string.format(
        "automatic HAnime stream armed at %.1f Hz; bone output is active only for exact HAnime and idle otherwise",
        1000 / Config.skeleton_sample_interval_ms
    ))
end

return App
