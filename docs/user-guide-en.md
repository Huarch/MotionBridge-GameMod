# Operation Lovecraft: Fallen Doll TCode Mod

Version: `0.15.0-l0-preview`

This preview uses UE4SS Lua to read live HAnime skeleton transforms and sends L0
through F8Studio. Idle and normal transitions are excluded. Leaving HAnime,
closing the game, or losing the stream activates the safe state.

## Installation

1. Close the game. Copy everything inside the package's `Game` directory to:
   `Operation Lovecraft Fallen Doll Playtest/Paralogue/Binaries/Win64`.
   The tested UE4SS runtime is already included.
2. Use an F8Studio build containing `Fallen Doll Source`, then import
   `F8Studio/fallen-doll-skeleton-preview-v15.json`.
3. Start the F8Studio graph, launch the game, and enter HAnime.
4. Verify motion with the 3D Skeleton Viewer or SR6/OSR Viewer.
5. After checking direction and range, enable either USB or Wi-Fi output—not both.

USB and Wi-Fi are disabled by default, and the USB port is blank. Use a Viewer
before enabling a physical device.

## Hotkeys

- `F6`: toggle low-frequency diagnostics;
- `F8`: export the current pose list once;
- `F10`: safely reload the Lua mod.

## Limitations

Physical-device output currently uses L0 only. Some left/right and dual-limb
actions, special actions, multiplayer scenes, and non-human poses still need
annotation. The remaining five axes and VR Viewer support are planned.

F8Studio Source PR:
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

This is an unofficial community project. The package does not include game
assets, F8Studio binaries, or device drivers.
