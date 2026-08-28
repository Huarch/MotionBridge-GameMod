# Motion Bridge — Operation Lovecraft: Fallen Doll Mod

English | [简体中文](README-ZH.md)

The game-side UE4SS Lua Mod for [Motion Bridge](https://github.com/Huarch/MotionBridge). It recognizes the active HAnime and streams a compact set of functional bones in real time. Motion Bridge converts that stream into OSR2/SR6 TCode and handles the 3D viewer, tuning, device connections, and safe return to center.

This is a real-time integration, not an offline Funscript. It does not modify or repack the game's Pak files.

Current Mod version: `0.17.0`

## Supported game builds

- Closed Beta / Playtest — desktop and VR
- Legacy 0.49 standalone build
- Legacy Steam Demo — desktop and VR

The Mod uses event-driven HAnime and participant switching with 50 Hz functional-bone capture. It does not repeatedly enumerate the complete skeleton, avoiding the stutter and physics resets seen in early prototypes.

## Installation

1. Download the latest Mod ZIP from this repository's [Releases](https://github.com/Huarch/MotionBridge-FallenDoll/releases).
2. Close the game.
3. Extract the ZIP and run `Install-Mod.ps1` with the game directory, or copy everything inside `Game` to the matching `Paralogue/Binaries/Win64` directory.
4. Download and start [Motion Bridge](https://github.com/Huarch/MotionBridge/releases).
5. Enter an HAnime and confirm that Motion Bridge reports the game stream as **ONLINE**.
6. Verify the motion in the 3D viewer before enabling physical-device output.

Example installer command:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\path\to\Operation Lovecraft Fallen Doll"
```

The release includes the compatible UE4SS runtime. Motion Bridge is downloaded separately so both projects can be updated independently.

## Hotkeys

- `F6`: toggle low-frequency diagnostics
- `F8`: export the current pose list once
- `F10`: safely hot-reload the Lua Mod

Real-time recognition and streaming are enabled automatically. There is no detection start/stop hotkey and no in-game overlay.

## Repository layout

- `fd_tcode_probe/`: HAnime recognition and functional-bone streaming Mod
- `fd_tcode_reloader/`: safe Lua hot-reload helper
- `tools/Install-FallenDollTCode.ps1`: validated installer for supported game layouts
- `tools/build_release_package.ps1`: creates the UE4SS Mod release ZIP

## Reporting problems

Use this repository for game recognition, missing poses, participant selection, functional-bone mapping, and Mod installation problems. Use the [Motion Bridge issue tracker](https://github.com/Huarch/MotionBridge/issues) for the desktop interface, 3D viewer, device connection, or output tuning.

Game store pages: [Playtest](https://store.steampowered.com/app/1685960/) · [Demo](https://store.steampowered.com/app/1811180/)

This is an unofficial community project. It does not include game assets or device drivers.
