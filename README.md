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
2. Extract the **entire** Mod ZIP. Do not run files from inside the ZIP preview.
3. Double-click **`Install Mod.cmd`**, then choose **Demo Desktop**, **Demo VR**, or **Legacy 0.49**. The installer searches the Steam libraries, shows the detected destination, checks runtime-folder write access, installs the Mod, and verifies the required files. If automatic detection fails, select the top-level game folder when prompted.
4. Wait for **Installation verified successfully**. If installation fails, keep the window open and attach `Install-Mod.log` when requesting help.
5. Start MotionBridge, then start the selected Fallen Doll edition and enter an HAnime.
6. Confirm that MotionBridge reports the Fallen Doll data stream as **Online**. Open the 3D preview to check direction and range before enabling real output.

Run the installer, the game, and MotionBridge as the same Windows user. Administrator mode is not normally required. The advanced `Install-Mod.ps1` interface remains available for scripted deployment, but ordinary users should use `Install Mod.cmd`.

### Manual installation (fallback only)

1. Close Fallen Doll completely and extract the entire downloaded Mod ZIP.
2. Choose the destination inside the top-level game folder:

| Edition | Destination |
|---|---|
| Demo Desktop | `Desktop\WindowsNoEditor\Paralogue\Binaries\Win64` |
| Demo VR | `VR\WindowsNoEditor\Paralogue\Binaries\Win64` |
| Legacy 0.49 | `Paralogue\Binaries\Win64` |

3. Open the package's `Game` folder. Copy the **contents inside it**—`dwmapi.dll` and the `ue4ss` folder—into the destination above. Do not copy the outer `Game` folder itself. Allow Windows to merge `ue4ss` and replace the packaged Mod files when prompted.
4. Confirm that the selected destination contains:

```text
<destination>
├─ dwmapi.dll
└─ ue4ss
   ├─ UE4SS.dll
   └─ Mods
      └─ fd_tcode_probe
         └─ Scripts
            └─ main.lua
```

5. Start MotionBridge, then start the selected game edition and enter an HAnime. A working installation is shown by MotionBridge changing from **STREAM WAITING** to **STREAM ONLINE** after fresh motion frames arrive.
6. If the stream stays waiting, open `<destination>\ue4ss\UE4SS.log` and check whether `%USERPROFILE%\.f8\studio\games\fallen-doll\runtime\fd-skeleton.ndjson` exists and continues updating during the HAnime.

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
