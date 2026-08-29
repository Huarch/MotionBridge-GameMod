local Config = require("fd_tcode.config")
local HAnimeManagerEventProbe = require("fd_tcode.core.hanime_manager_event_probe")
local HAnimeRuntime = require("fd_tcode.core.hanime_runtime")
local Log = require("fd_tcode.core.log")
local ProfileStore = require("fd_tcode.core.profile_store")

local App = {}
local PrecisionCapture = nil

local function load_precision_capture()
    if Config.precision_capture_enabled ~= true then
        return nil
    end
    if PrecisionCapture ~= nil then
        return PrecisionCapture
    end
    local ok, module = pcall(require, "fd_tcode.core.precision_capture")
    if not ok or type(module) ~= "table" then
        Log.warn("precision capture module is not included in this runtime package")
        return nil
    end
    PrecisionCapture = module
    return PrecisionCapture
end

local function register_hanime_events()
    -- Do not retain participant UObjects across world transitions. UE 5.7 can
    -- destroy menu/preview components before the next delayed Lua tick, and a
    -- later reflected call on one of those wrappers can crash inside
    -- UObject::IsA before Lua pcall gets a chance to handle it.
    local world_ok, world_error = pcall(function()
        NotifyOnNewObject("/Script/Engine.World", function()
            HAnimeManagerEventProbe.try_register()
            HAnimeRuntime.world_changed()
        end)
    end)
    if not world_ok then
        Log.warn("World transition notification unavailable: " .. tostring(world_error))
    end

    -- The normal UE 5.7 path never subscribes to every skeletal component:
    -- some construction notifications carry a pointer that is stale before
    -- Lua can wrap it. Precision capture is explicitly opt-in and isolated.
    local precision_capture = load_precision_capture()
    if precision_capture ~= nil then
        local created_ok, created_error = pcall(function()
            NotifyOnNewObject("/Script/Engine.SkeletalMeshComponent", function(component)
                precision_capture.queue_component(component)
            end)
        end)
        if not created_ok then
            Log.warn("SkeletalMeshComponent event unavailable: " .. tostring(created_error))
        end
    end

end

local function register_keys()
    -- F6 is documented as diagnostics. Keep it as a one-shot game-thread
    -- capture; a continuous monitor is neither needed nor desirable here.
    RegisterKeyBind(Config.keys.toggle_runtime, function()
        ExecuteInGameThread(function()
            Log.warn("F6 runtime reflection diagnostics are disabled on UE 5.7")
        end)
    end)
end

function App.start()
    ProfileStore.reload()
    register_keys()
    register_hanime_events()
    HAnimeManagerEventProbe.start()
    HAnimeRuntime.start()
    if PrecisionCapture ~= nil then
        PrecisionCapture.start()
    end
    Log.info(string.format("version=%s loaded", Config.version))
    Log.info("SIMULATION ONLY / DEVICE DISABLED")
    Log.info("F6 diagnostics | F7 reserved | F10 probe hot reload")
    Log.info(string.format(
        "HAnime state watcher active at %.1f Hz; native HAnime event hooks disabled",
        1000 / Config.hanime_poll_interval_ms
    ))
end

return App
