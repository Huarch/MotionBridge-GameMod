# Operation Lovecraft: Fallen Doll TCode Mod

English | [简体中文](README-ZH.md)

An unofficial real-time TCode integration for Operation Lovecraft: Fallen Doll.
The UE4SS Lua mod reads functional bones from the active HAnime, while F8Studio
handles participant and functional-bone selection, multi-axis motion, viewers,
safe return-to-center behavior, and USB or Wi-Fi output. This is not an offline
Funscript and it does not modify or repack the game's Pak files.

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
- Playtest catalog: 508 HAnime families and 3,081 exact Montage identities
- Demo catalog: 217 HAnime families and 1,160 exact Montage identities
- 50 Hz real-time functional-bone capture with VaM-style contact geometry
- Six-axis SR6 output, OSR2 L0 output, plus 3D skeleton, SR6/OSR, and six-axis waveform viewers
- Independent range sliders for every axis; USB and Wi-Fi output are mutually exclusive
- Component and Montage events drive HAnime and participant switching; low-frequency polling is verification only
- On stream loss, the last value is held for 250 ms and then eased back to `L05000` over 600 ms

The multi-axis pipeline is ready for normal use, but six-axis support does not
mean that every HAnime has been manually calibrated. Some Hand/Foot side and
primary-bone choices, special actions, multiplayer scenes, and non-human scenes
still need additional annotations. For an uncalibrated pose, inspect the axes in
the viewers first and limit the physical range of each axis in F8Studio.

## Data Flow

```text
Operation Lovecraft: Fallen Doll
  → UE4SS Lua (exact HAnime recognition and compact functional-bone capture)
  → ~/.f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson
  → Fallen Doll Source (fd_source)
  → PyEngine (fd_pyengine: contact geometry, six axes, safe centering, range mapping)
  → 3D / SR6 / Wave Viewer → TCode → USB or Wi-Fi
```

`studio` is the F8Studio application itself. After importing and deploying the
project, it should start `fd_pyengine` and `fd_source` automatically. Users do
not need to launch three separate terminal windows.

## Quick Start

1. Close the game. Copy the contents of the release package's `Game` directory
   into the matching version's `Paralogue/Binaries/Win64` directory, or run the
   included `Install-Mod.ps1` script.
2. Use an F8Studio build that includes `Fallen Doll Source`, import
   `f8studio/fallen-doll-skeleton-preview-v17.json`, and deploy the project.
3. Confirm that `studio`, `fd_pyengine`, and `fd_source` are all Running/Active.
4. Enable either USB or Wi-Fi output, never both. On first use, open a viewer
   and test without connecting a physical device.
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
no detection start/stop hotkey. The Lua mod does not create an in-game UI. All
viewers are separate F8Studio windows.

## Repository Layout

- `fd_tcode_probe/`: game-side UE4SS Lua mod
- `fd_tcode_reloader/`: safe Lua hot-reload broker
- `data/`: HAnime, pose, and skeleton indexes generated from unpacked data
- `f8studio/`: F8Studio project exports and the Fallen Doll Source upstream patch
- `tools/`: data generation, installation, startup, and release scripts
- `docs/`: user documentation, release posts, and unpacking constraints

Unpacked data is consulted before runtime experiments. See
[unpacked-data-first.md](docs/unpacked-data-first.md). The runtime no longer
enumerates the entire skeleton repeatedly, avoiding game stutter and physics
resets.

## F8Studio

Recommended project: `Fallen Doll Skeleton Preview v17 (real-time multi-axis)`

Fallen Doll Source upstream PR:
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

Wi-Fi and USB nodes are disabled by default in the shared project, and the USB
port is empty. The two outputs cannot be enabled at the same time. The default
Wi-Fi target is `tcode.local:8000`; USB uses the device's serial port at 115200
baud.

This is an unofficial community project. The repository and release packages
do not include game assets, F8Studio binaries, or device drivers.
