local Config = require("fd_tcode.config")
local Log = require("fd_tcode.log")
local PoseCatalogProbe = require("fd_tcode.pose_catalog_probe")
local ProfileStore = require("fd_tcode.profile_store")
local Runtime = require("fd_tcode.runtime")

local App = {}

local function register_keys()
    RegisterKeyBind(Config.keys.toggle_runtime, Runtime.toggle)
    RegisterKeyBind(Config.keys.export_pose_catalog, PoseCatalogProbe.export_visible)
    RegisterKeyBind(Config.keys.skeleton_stream, Runtime.toggle_skeleton_stream)
end

function App.start()
    ProfileStore.reload()
    register_keys()
    Log.info(string.format("version=%s loaded", Config.version))
    Log.info("SIMULATION ONLY / DEVICE DISABLED")
    Log.info("F6 monitor on/off | F7 external F8Studio | F8 export current pose list | F9 start/stop 20 Hz skeleton stream | F10 full Lua reload via broker")
    Log.info("automatic Unreal object reads are disabled; F9 owns the continuous skeleton stream")
end

return App
