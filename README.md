# Operation Lovecraft: Fallen Doll TCode Mod

English | [简体中文](README-ZH.md)

The Fallen Doll game adapter for Motion Bridge. The UE4SS Lua Mod
recognizes the active HAnime and streams a compact set of functional bones;
Motion Bridge converts that live motion into OSR2/SR6 TCode, provides the 3D
viewer and device controls, and handles safe return-to-center behavior. This is
not an offline Funscript and it does not modify or repack the game's Pak files.

Current version: `0.17.0`

Version `0.17.0` formally enables the real-time multi-axis motion engine in
`fallen-doll-skeleton-preview-v17.json`. SR6 receives all six axes
(`L0/L1/L2/R0/R1/R2`), while OSR2 uses `L0` from the same motion stream. See
[multi-axis-v17-dev.md](docs/multi-axis-v17-dev.md) for implementation and
calibration details.

Game store pages:
[Operation Lovecraft: Fallen Doll on Steam](https://store.steampowered.com/app/1685960/)
· [Demo on Steam](https://store.steampowered.com/app/1811180/)

## Supported Versions and Features

- Closed Beta / Playtest, desktop and VR
- Legacy 0.49 standalone build (`KiritoMod049.exe`, Unreal Engine 4.25)
- Legacy Demo, desktop and VR
- Playtest catalog: 508 HAnime families and 3,087 exact Montage identities
- Demo catalog: 217 HAnime families and 1,160 exact Montage identities
- 50 Hz real-time functional-bone capture with VaM-style contact geometry
- Six-axis SR6 output, OSR2 L0 output, plus a standalone SR6/OSR 3D viewer
- Independent range sliders for every axis; USB and Wi-Fi output are mutually exclusive
- Component and Montage events drive HAnime and participant switching; low-frequency polling is verification only
- On stream loss, the last value is held for 250 ms and then eased back to `L05000` over 600 ms

The multi-axis pipeline is ready for normal use, but six-axis support does not
mean that every HAnime has been manually calibrated. Some Hand/Foot side and
primary-bone choices, special actions, multiplayer scenes, and non-human scenes
still need additional annotations. For an uncalibrated pose, inspect the axes in
the viewer first and limit the physical range of each axis in Motion Bridge.

## Data Flow

```text
Operation Lovecraft: Fallen Doll
  → UE4SS Lua (exact HAnime recognition and compact functional-bone capture)
  → ~/.f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson
  → Motion Bridge Fallen Doll adapter
  → contact geometry, six axes, safe centering and range mapping
  → 3D SR6/OSR Viewer → TCode → USB, Wi-Fi or Intiface
```

The stream path remains compatible with existing installations, but F8Studio,
`fd_source`, and `fd_pyengine` are not required for normal use.

## Quick Start

1. Close the game. Copy the contents of the release package's `Game` directory
   into the matching version's `Paralogue/Binaries/Win64` directory, or run the
   included `Install-Mod.ps1` script.
2. Extract and start Motion Bridge. The Full release package already includes
   a compatible portable build.
3. Confirm that Motion Bridge reports the Fallen Doll stream as Online.
4. Select USB, Wi-Fi, or Intiface. On first use, open the 3D viewer and verify
   the motion before arming physical-device output.
5. Start the game and enter an HAnime. Leaving the action or losing the stream
   automatically returns the output to its safe center.

Detailed setup and troubleshooting:

- [Chinese user guide](docs/user-guide-zh.md)
- [English user guide](docs/user-guide-en.md)
- [Chinese startup and troubleshooting guide](docs/startup-and-troubleshooting-zh.md)
- [English startup and troubleshooting guide](docs/startup-and-troubleshooting-en.md)

## Hotkeys

- `F6`: toggle low-frequency diagnostics
- `F8`: export the current pose list once
- `F10`: safely hot-reload the Lua mod

Real-time recognition and skeleton streaming are armed automatically; there is
no detection start/stop hotkey. The Lua Mod does not create an in-game UI; the
Motion Bridge viewer runs as a separate desktop window.

## Repository Layout

- `fd_tcode_probe/`: game-side UE4SS Lua mod
- `fd_tcode_reloader/`: safe Lua hot-reload broker
- `data/`: HAnime, pose, and skeleton indexes generated from unpacked data
- `f8studio/`: optional legacy/development project exports and upstream patch
- `tools/`: data generation, installation, startup, and release scripts
- `docs/`: user documentation, release posts, and unpacking constraints

Unpacked data is consulted before runtime experiments. See
[unpacked-data-first.md](docs/unpacked-data-first.md). The runtime no longer
enumerates the entire skeleton repeatedly, avoiding game stutter and physics
resets.

## Motion Bridge

The native Motion Bridge application has moved to its own repository. It
contains the Qt desktop UI, multi-game adapter protocol, motion engine, device
outputs, SR6 preview, portable build, and F8Studio settings migration tool.
This repository now owns only the Fallen Doll game integration and its
F8Studio workflow.

Source and standalone releases:
[Huarch/MotionBridge](https://github.com/Huarch/MotionBridge)

Fallen Doll remains Motion Bridge's first bundled adapter and continues to
consume the same `fd-skeleton.ndjson` stream. Game releases provide a Full ZIP
for new users and a smaller Mod-only ZIP for existing Motion Bridge users.

## Optional F8Studio workflow

F8Studio is no longer required to run the Mod. The existing `Fallen Doll
Skeleton Preview v17` project remains available for graph editing, diagnostics,
and comparison with the standalone motion engine.

Fallen Doll Source upstream PR:
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

Wi-Fi and USB nodes are disabled by default in the shared project, and the USB
port is empty. The two outputs cannot be enabled at the same time. The default
Wi-Fi target is `tcode.local:8000`; USB uses the device's serial port at 115200
baud.

This is an unofficial community project. The repository and release packages
do not include game assets, F8Studio binaries, or device drivers.
