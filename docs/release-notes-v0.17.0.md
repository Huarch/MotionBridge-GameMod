# FallenDollTCode v0.17.0 — Real-Time Multi-Axis

This release promotes the v17 motion graph to the default Fallen Doll integration.

## Highlights

- Real-time SR6 `L0/L1/L2/R0/R1/R2` output; OSR2 uses `L0`.
- 50 Hz compact functional-bone stream and contact-motion calculation.
- Stabilized pitch/rotation continuity and target-specific hand/foot/breast handling.
- Event-driven recovery across HAnime changes, idle transitions, character visibility,
  desktop, and VR layouts.
- Reorganized F8Studio project with four documented sections.
- Working Live Preview for the SR6 model, 3D skeleton, and six-axis waveforms.
- Compact per-axis minimum/maximum range sliders.
- Updated Playtest and Demo HAnime identity data.
- Twist is now relative to the active contact binding instead of the pose's
  absolute anatomical orientation.
- Single-foot scenes select the active foot by proximity to the contact axis;
  corrected foot-local axes prevent false Twist, Roll, and Pitch saturation.

## Safety and scope

USB and Wi-Fi device nodes are disabled by default and must not be enabled together.
Multi-axis support does not mean every HAnime has been manually calibrated. Check new
poses in Live Preview and set safe ranges for every axis before connecting a device.

The archive includes UE4SS and the game-side Lua mods. It does not include game assets,
F8Studio binaries, or device drivers. F8Studio integration is tracked in
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3).
