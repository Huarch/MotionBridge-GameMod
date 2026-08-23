# Operation Lovecraft: Fallen Doll TCode Mod

Version: `0.16.5-event-driven-switch`

This unofficial mod reads live HAnime skeleton transforms through UE4SS Lua and
uses F8Studio for L0, 3D/OSR viewers, and OSR2/SR6 TCode output. Idle, ordinary
transitions, and unidentified animations are not treated as active output. On a
stream loss, the graph holds the last value for 250 ms and smoothly returns to
`L05000` over 600 ms.

## Installation

1. Close the game and copy everything under `Game` into the matching directory:
   - Playtest: `Paralogue/Binaries/Win64`
   - Demo desktop: `Desktop/WindowsNoEditor/Paralogue/Binaries/Win64`
   - Demo VR: `VR/WindowsNoEditor/Paralogue/Binaries/Win64`
   Alternatively run `Install-Mod.ps1 -GameRoot "game root"`. UE4SS is included.
2. In an F8Studio build containing `Fallen Doll Source`, import
   `F8Studio/fallen-doll-skeleton-preview-v16.json`, then Deploy.
3. Confirm that `studio`, `fd_pyengine`, and `fd_source` are running. Studio should
   start the latter two automatically; do not launch three separate applications.
4. Start the game, enter HAnime, and first verify motion with the 3D Skeleton Viewer
   or SR6/OSR Viewer.
5. After checking direction and range, enable either USB or Wi-Fi output, never both.

Wi-Fi defaults to `tcode.local:8000`. USB requires the correct serial port at
115200 baud. Both physical-output nodes are disabled by default, and the USB port
is blank.

## Hotkeys

- `F6`: toggle low-frequency diagnostics
- `F8`: export the current pose list once
- `F10`: safely hot-reload the Lua mod

Detection is automatically armed. Viewers are separate F8Studio windows, not an
in-game overlay.

## Current status

- Playtest, Demo desktop, and Demo VR layouts are supported; the main Playtest
  desktop/VR paths have been exercised.
- Playtest catalog: 508 HAnime families and 3,081 exact Montage identities.
- Demo catalog: 217 families and 1,160 exact Montage identities.
- Physical-device support is currently limited to L0.
- Some left/right or dual-limb priorities, special actions, multiplayer scenes,
  and non-human poses still need annotation.
- The other five axes are future work.

For startup failures or missing services, read `startup-and-troubleshooting-en.md`.

F8Studio Source PR:
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

This package does not include game assets, F8Studio binaries, or device drivers.
