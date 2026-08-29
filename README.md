# MotionBridge Game Mod — Fallen Doll Playtest

[简体中文](README-ZH.md) | English

This branch contains the UE4SS Mod for the **Operation Lovecraft: Fallen Doll Playtest**. It recognizes the active HAnime and streams the required functional-bone data to [MotionBridge](https://github.com/Huarch/MotionBridge).

MotionBridge is required: it provides the desktop interface, 3D preview, motion tuning, USB/Wi-Fi device connection, TCode output, and safe return to center. This Mod does not control a device by itself, does not create an in-game overlay, and does not modify game Pak files.

## Before you start

- Install the Fallen Doll Playtest (desktop or VR).
- Download and run the current [MotionBridge release](https://github.com/Huarch/MotionBridge/releases).
- Download the Mod package built from the `fallen-doll-playtest` branch or its matching [release](https://github.com/Huarch/MotionBridge-GameMod/releases).

## Install and use

1. Close the game.
2. Extract the Mod package. Run `Install-Mod.ps1` and select the Fallen Doll Playtest game folder, or copy the package's `Game` contents to `Paralogue/Binaries/Win64` inside that game folder.
3. Start MotionBridge. Configure USB or Wi-Fi only if you plan to use a physical device.
4. Start the Fallen Doll Playtest and enter an HAnime.
5. Confirm that MotionBridge reports the Fallen Doll data stream as **Online**. Open the 3D preview to check direction and range before enabling real output.
6. When leaving an HAnime or when the data stream stops, MotionBridge safely returns the device to center.

Example installer command:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\Games\Fallen Doll Playtest"
```

The Mod package includes its matching UE4SS files. MotionBridge and the game Mod are separate downloads and can be updated independently.

## Shortcuts

- `F6`: capture one diagnostic snapshot
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
