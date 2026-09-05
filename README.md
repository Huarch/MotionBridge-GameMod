# MotionBridge Game Mod — Fallen Doll Playtest

[简体中文](README-ZH.md) | English

This branch contains the UE4SS Mod for the **Operation Lovecraft: Fallen Doll Playtest**. It recognizes the active HAnime and streams the required functional-bone data to [MotionBridge](https://github.com/Huarch/MotionBridge).

MotionBridge is required: it provides the desktop interface, 3D preview, motion tuning, USB/Wi-Fi device connection, TCode output, and safe return to center. This Mod does not control a device by itself, does not create an in-game overlay, and does not modify game Pak files.

In multiplayer, the outer action gate follows only the local player's HAnime state, so a remote player's action cannot open or reopen the output stream. This gate does not read, store, log, or transmit a player ID.

## Supported game version

- Fallen Doll Playtest `0.9.0` (desktop and VR)

This is the supported game version. The separate `0.17.x` number identifies the Mod package itself and is not a Fallen Doll game version.

## Before you start

- Install Fallen Doll Playtest `0.9.0` (desktop or VR).
- Download and run the current [MotionBridge release](https://github.com/Huarch/MotionBridge/releases).
- Download the Mod package built from the `fallen-doll-playtest` branch or its matching [release](https://github.com/Huarch/MotionBridge-GameMod/releases).

## Install and use

1. Close the game.
2. Extract the **entire** Mod ZIP. Do not run files from inside the ZIP preview.
3. Double-click **`Install Mod.cmd`**. It searches the Steam libraries for the Playtest, shows the detected destination, checks runtime-folder write access, installs the Mod, and verifies the required files. If automatic detection fails, select the top-level Fallen Doll Playtest folder when prompted.
4. Wait for **Installation verified successfully**. If installation fails, keep the window open and attach `Install-Mod.log` when requesting help.
5. Start MotionBridge, then start the Fallen Doll Playtest and enter an HAnime.
6. Confirm that MotionBridge reports the Fallen Doll data stream as **Online**. Open the 3D preview to check direction and range before enabling real output.

Run the installer, the game, and MotionBridge as the same Windows user. Administrator mode is not normally required. The advanced `Install-Mod.ps1` interface remains available for scripted deployment, but ordinary users should use `Install Mod.cmd`.

### Manual installation (fallback only)

1. Close Fallen Doll completely.
2. Extract the entire downloaded Mod ZIP. Open its `Game` folder.
3. Copy the **contents inside** `Game`—`dwmapi.dll` and the `ue4ss` folder—into the game's `Paralogue\Binaries\Win64` folder. Do not copy the outer `Game` folder itself. Allow Windows to merge the `ue4ss` folder and replace the packaged Mod files when prompted.
4. Confirm that the resulting game installation contains all three paths:

```text
Paralogue\Binaries\Win64
├─ dwmapi.dll
└─ ue4ss
   ├─ UE4SS.dll
   └─ Mods
      └─ fd_tcode_probe
         └─ Scripts
            └─ main.lua
```

5. Start MotionBridge, then start Fallen Doll and enter an HAnime. The Mod intentionally has no in-game menu, overlay, or debug console. Its visible result is MotionBridge changing from **STREAM WAITING** to **STREAM ONLINE** after fresh motion frames arrive.
6. If the stream stays waiting, open `Paralogue\Binaries\Win64\ue4ss\UE4SS.log` and check whether `%USERPROFILE%\.f8\studio\games\fallen-doll\runtime\fd-skeleton.ndjson` exists and continues updating during the HAnime.

The Mod package includes its matching UE4SS files. MotionBridge and the game Mod are separate downloads and can be updated independently.

## Shortcuts

- `F6`: report that unsafe UE 5.7 runtime diagnostics are disabled
- `F10`: hot-reload only the HAnime detector logic; UE4SS callbacks stay registered

## Development layout

- `fd_tcode_probe/` is the enabled UE4SS Mod. `fd_tcode_reloader/` is retained only as a disabled legacy helper for older builds.
- `fd_tcode_probe/Scripts/fd_tcode/core/` contains hand-written runtime logic.
- `fd_tcode_probe/Scripts/fd_tcode/data/` contains generated and edition-specific tables.
- `tools/` contains the Playtest installer, validation, and release builder; release builds run the module-layout check first.
- Release ZIPs use a runtime allowlist and exclude UE4SS symbols, developer Mods, bundled documentation, and game templates.
- Generated exports, research data, local dependencies, build packages, and `.artifacts/` stay ignored and are not part of this branch.
- Cross-game helpers and new-game templates belong in the repository's `master` branch. Keep Fallen Doll-specific runtime names, skeleton mappings, and package assets in this branch.

## Support

Report game detection, missing poses, participant binding, functional-bone mapping, and Mod installation issues in this repository. Report MotionBridge UI, preview, device connection, or output-tuning issues in the [MotionBridge issue tracker](https://github.com/Huarch/MotionBridge/issues).

Game page: [Fallen Doll Playtest on Steam](https://store.steampowered.com/app/1685960/)

This is an unofficial community project. It does not include game assets or device drivers.
