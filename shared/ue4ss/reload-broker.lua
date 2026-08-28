-- Copy this helper into a separate UE4SS Mod beside the target Mod.
-- Set target_mod_name in the game branch; do not put the F10 callback inside
-- the Mod that F10 restarts.

local target_mod_name = "replace-with-game-motion-mod"

local function reload_target()
    if type(RestartMod) ~= "function" then
        print("[MotionBridge][WARN] RestartMod is unavailable in this UE4SS build\n")
        return
    end
    RestartMod(target_mod_name)
end

if type(RegisterKeyBind) == "function" and Key ~= nil and Key.F10 ~= nil then
    RegisterKeyBind(Key.F10, reload_target)
else
    print("[MotionBridge][WARN] F10 reload bind is unavailable\n")
end
