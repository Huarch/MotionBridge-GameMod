local App = require("fd_tcode.app")

local ok, message = xpcall(App.start, debug.traceback)
if not ok then
    print(string.format("[FD-TCode][ERROR] Lua startup failed: %s\n", tostring(message)))
end
