# Fallen Doll TCode — runtime simulator

This project is a simulation-only TCode Mod for Operation Lovecraft: Fallen Doll.
It never writes a Pak and currently has no serial, Bluetooth, or real-device output.

## Current architecture

```text
UE4SS C++ game thread -> realtime bone geometry -> normalized SR6 axes
                         -> UDP v1 (127.0.0.1:17891) -> localhost simulation bridge
```

- `cpp/FDTCodeCore`: independent, tested VaM-style reference/target geometry,
  candidate hysteresis, release smoothing, and UDP v1 serialization.
- `cpp/FDTCode`: UE4SS DLL shell with F11 simulation and F12 debug-page toggles.
  It deliberately performs no skeletal read until Fallen Doll's generated CXX/UHT
  headers verify the `GetSocketTransform` parameter layout.
- `bridge/server.mjs`: receives UDP v1 and exposes `http://127.0.0.1:17890/state`.
  `deviceOutput` is permanently `disabled`.
- `data/runtime-profiles-v2.json`: geometric Hand01/02/03 profiles. The former
  offline curve files remain regression evidence only.

## Validate without the game

```powershell
.\.toolchain\cmake-3.31.6-windows-x86_64\bin\cmake.exe --build build --config Release --target FDTCodeCoreTests
.\.toolchain\cmake-3.31.6-windows-x86_64\bin\ctest.exe --test-dir build -C Release --output-on-failure
node .\tools\validate_runtime_profiles.mjs
node .\bridge\test-server.mjs
```

## UE4SS DLL prerequisite

The installed game uses UE4SS `3.0.1 Beta`, SHA
`d7e7826d415b0332b43439a64e6c87f64019be03`. The matching source is present
under `.deps/RE-UE4SS`, but the upstream C++ SDK requires its private `UEPseudo`
submodule. After GitHub access is granted, initialize that submodule, configure
with the bundled CMake, build `FDTCode` in `Game__Shipping__Win64`, and the
post-build step deploys `main.dll` to the game's `Mods/FDTCode/dlls` directory.

Until that access exists, the standalone core and bridge are intentionally the
only buildable targets.

## Asset workflow

Runtime state comes from UE4SS. Use [解包导出流程.md](D:/zhifu/Desktop/data/mmd/docs/解包导出流程.md)
only to inspect skeletons, verify bone names/bases, and export targeted paired
animations; do not rebuild or modify Pak files.
