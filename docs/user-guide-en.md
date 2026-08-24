# Operation Lovecraft: Fallen Doll TCode Mod

Version: `0.17.0`

Game pages: [Operation Lovecraft: Fallen Doll on Steam](https://store.steampowered.com/app/1685960/) ·
[Steam Demo](https://store.steampowered.com/app/1811180/)

This unofficial mod reads the current HAnime skeleton in real time through UE4SS Lua.
F8Studio converts a compact functional-bone stream into multi-axis motion: SR6 uses
`L0/L1/L2/R0/R1/R2`, while OSR2 uses `L0` from the same stream. It follows the live
pose and animation speed rather than replaying a pre-made Funscript.

## Installation

1. Close the game and copy everything under `Game` into the matching directory:
   - Playtest: `Paralogue/Binaries/Win64`
   - Demo desktop: `Desktop/WindowsNoEditor/Paralogue/Binaries/Win64`
   - Demo VR: `VR/WindowsNoEditor/Paralogue/Binaries/Win64`
   Alternatively run `Install-Mod.ps1 -GameRoot "game root"`. UE4SS is included.
2. Use an F8Studio build containing the changes from
   [feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3). Import
   `F8Studio/fallen-doll-skeleton-preview-v17.json`, then Deploy.
3. Confirm that `studio`, `fd_pyengine`, and `fd_source` are running. Studio should
   start the latter two automatically; do not launch three separate applications.
4. Enter HAnime and enable `Live Preview` to check the SR6 model and six-axis waveform.
5. In the Safety section, set the minimum and maximum slider for each axis to suit your
   device. Then enable either USB or Wi-Fi output, never both.

Wi-Fi defaults to `tcode.local:8000`. USB requires the correct serial port at
115200 baud. Both physical-output nodes are disabled by default, and the USB port
is blank.

Idle, ordinary transitions, and unidentified animations are not active output. On
stream loss, the graph holds the last value for 250 ms and smoothly returns to center
over 600 ms.

## Hotkeys

- `F6`: toggle low-frequency diagnostics
- `F8`: export the current pose list once
- `F10`: safely hot-reload the Lua mod

Detection is automatically armed. Viewers are F8Studio windows, not an in-game overlay.

## Current status

- Playtest, Demo desktop, and Demo VR layouts are supported.
- Playtest catalog: 508 HAnime families and 3,081 exact Montage identities.
- Demo catalog: 217 families and 1,160 exact Montage identities.
- SR6 real-time six-axis output and OSR2 L0 output are available at 50 Hz.
- Some left/right and dual-limb priorities, special actions, multiplayer scenes, and
  non-human poses still need per-animation calibration. Multi-axis support does not
  mean every HAnime has been manually verified.

For startup failures or missing services, read `Startup-and-Troubleshooting-English.md`.
The package does not include game assets, F8Studio binaries, or device drivers.
