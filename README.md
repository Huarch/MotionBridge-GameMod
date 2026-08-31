# MotionBridge Game Mod — Fallen Doll Demo / Legacy 0.49

[简体中文](README-ZH.md) | English

This branch contains the UE4SS Mod for the **Operation Lovecraft: Fallen Doll Demo** and the legacy **0.49** game build. It recognizes the active HAnime and streams the required functional-bone data to [MotionBridge](https://github.com/Huarch/MotionBridge).

MotionBridge is required: it provides the desktop interface, 3D preview, motion tuning, USB/Wi-Fi device connection, TCode output, and safe return to center. This Mod does not control a device by itself, does not create an in-game overlay, and does not modify game Pak files.

## Supported game versions

- Steam Demo: Desktop and VR editions
- Legacy standalone build: `0.49`

These are game compatibility versions. The separate `0.17.x` number identifies the Mod package itself and is not a Fallen Doll game version.

## Before you start

- Install either the Steam Demo of Operation Lovecraft: Fallen Doll or the legacy `0.49` build.
- Download and run the current [MotionBridge release](https://github.com/Huarch/MotionBridge/releases).
- Download the Mod package built from the `fallen-doll-demo` branch or its matching [release](https://github.com/Huarch/MotionBridge-GameMod/releases).

## Install and use

1. Close the game.
2. Extract the Mod package. Run `Install-Mod.ps1` and select the Demo or legacy `0.49` game folder. The installer detects Demo Desktop, Demo VR, and Legacy 0.49 layouts separately. Manual copying remains available through the package's `Game` directory.
3. Start MotionBridge. Configure USB or Wi-Fi only if you plan to use a physical device.
4. Start the Fallen Doll Demo and enter an HAnime.
5. Confirm that MotionBridge reports the Fallen Doll data stream as **Online**. Open the 3D preview to check direction and range before enabling real output.
6. When leaving an HAnime or when the data stream stops, MotionBridge safely returns the device to center.

Example installer command:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\Games\Fallen Doll Demo"
```

Legacy 0.49 example:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\Games\Fallen Doll Operation Lovecraft (0.49)"
```

The Mod package includes its matching UE4SS files. MotionBridge and the game Mod are separate downloads and can be updated independently.

## Shortcuts

- `F6`: toggle low-frequency diagnostics
- `F8`: export the current pose list once
- `F10`: safely reload the Lua Mod

## Development layout

- `fd_tcode_probe/` and `fd_tcode_reloader/` are the only deployable UE4SS Mod sources.
- `fd_tcode_probe/Scripts/fd_tcode/core/` contains hand-written runtime logic.
- `fd_tcode_probe/Scripts/fd_tcode/data/` contains generated and Demo-specific tables.
- `tools/` contains validation, installer, and release scripts; release builds run the module-layout check first.

## Support

Report game detection, missing poses, participant binding, functional-bone mapping, and Mod installation issues in this repository. Report MotionBridge UI, preview, device connection, or output-tuning issues in the [MotionBridge issue tracker](https://github.com/Huarch/MotionBridge/issues).

Game page: [Fallen Doll Demo on Steam](https://store.steampowered.com/app/1811180/)

This is an unofficial community project. It does not include game assets or device drivers.
