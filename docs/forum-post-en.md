# [Mod Release] Operation Lovecraft: Fallen Doll Real-Time TCode Support

This unofficial community mod reads live in-game skeleton transforms through
UE4SS Lua and sends them to F8Studio for TCode generation. It does not replay a
pre-made curve from animation progress, so output follows the current pose when
the in-game animation speed changes.

Current version: `0.15.0-l0-preview`

Download: **[Add attachment or download link here]**

SHA-256:
`9FBC601173F5213ECECD9A5D3B65E5E96BA2E15FB5FBAA6DF279519CA33AF175`

## Features

- Exact HAnime detection that excludes idle, expression, and normal transitions;
- Low-overhead sampling of required Hand, Foot, Mouth, Vaginal, and Anal bones;
- Participant and functional-bone priority selection for solo and multiplayer scenes;
- F8Studio 3D Skeleton Viewer, SR6/OSR Viewer, and an L0 signal chain;
- USB or Wi-Fi TCode output, with physical outputs disabled by default;
- Safe state when leaving HAnime, closing the game, or losing the data stream;
- F10 hot reload for the game-side Lua mod.

## Quick start

1. Install a compatible RE-UE4SS build.
2. Copy and enable both included mods in the game's `UE4SS/Mods` directory.
3. Use an F8Studio build containing `Fallen Doll Source` and import the v15 project.
4. Start the F8Studio graph and the game, enter HAnime, then verify motion in a Viewer.
5. After checking direction and range, enable either USB or Wi-Fi output—not both.

F8Studio integration PR:
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

Until the PR is merged, use its branch or the Source patch included in the release.
See the included user guide for detailed installation steps.

## Current limitations

Physical-device output currently uses L0 only. Some left/right and dual-limb
actions, special actions, multiplayer scenes, and non-human poses still need
annotation. L1/L2/R0/R1/R2 and VR Viewer support are planned for later versions.

Keep physical output disabled during first setup. Verify direction, range,
stream-loss centering, and emergency-stop behavior before connecting a device.

This project does not include game assets, UE4SS, F8Studio binaries, or device drivers.

