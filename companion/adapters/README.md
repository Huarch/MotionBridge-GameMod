# Adapter packages

Motion Bridge does not load game-specific DLLs. A game adapter declares an input transport and default skeleton/contact mapping; the game-side Mod or plugin emits `motion-frame/v1`.

`fallen-doll/adapter.json` is the first full adapter. It consumes the existing UE4SS NDJSON stream without modifying the game Mod. New games should start with either complete `motion-frame/v1` NDJSON records or local UDP datagrams containing the same JSON object.

`motion-frame-v1.example.ndjson` is a complete single-frame fixture. Producers must use metres for positions and `[w, x, y, z]` for normalized quaternions. A producer sends only functional bones needed by the chosen contact profile; it must not repeatedly enumerate a complete game skeleton merely to satisfy Motion Bridge.

Game-specific code remains outside the Motion Bridge process: UE4SS Lua for Unreal, BepInEx for Unity, or an official game API when available. This keeps a bad adapter from crashing the device output process.
