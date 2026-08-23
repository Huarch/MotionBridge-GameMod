local TARGET_MOD = "fd_tcode_probe"

RegisterKeyBind(Key.F10, function()
    print(string.format("[FD-TCode-Reload] reloading %s\n", TARGET_MOD))
    RestartMod(TARGET_MOD)
end)

print(string.format("[FD-TCode-Reload] F10 broker ready for %s\n", TARGET_MOD))
