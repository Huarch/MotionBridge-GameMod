local Config = require("fd_tcode.config")
local Log = require("fd_tcode.log")
local PoseCatalogProbe = require("fd_tcode.pose_catalog_probe")
local ProfileStore = require("fd_tcode.profile_store")
local Runtime = require("fd_tcode.runtime")
local SkeletonStream = require("fd_tcode.skeleton_stream")

local App = {}

local function register_keys()
    RegisterKeyBind(Config.keys.toggle_runtime, Runtime.toggle)
    RegisterKeyBind(Config.keys.export_pose_catalog, PoseCatalogProbe.export_visible)
end

function App.start()
    ProfileStore.reload()
    register_keys()
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
