# Runtime and device design

## Boundaries

The game-side C++ Mod owns only discovery, bone sampling, geometric motion
calculation, a copied UI snapshot, and localhost UDP telemetry. It must perform
all Unreal access on the game thread. The ImGui render callback and bridge never
receive a UObject pointer.

The bridge owns diagnostics and future device safety. Its current implementation
is simulation-only: it imports neither serial libraries nor a TCode sender, and
reports `deviceOutput: "disabled"` at every endpoint.

## Runtime read sequence

1. Load the C++ DLL and verify hotkeys/UI without object access.
2. Generate Fallen Doll CXX/UHT headers in the running UE4SS session.
3. Confirm `GetSocketTransform` parameter properties and use reflection-backed
   parameter storage; do not hand-write the function's parameter layout.
4. Sample one transform at 5 Hz, then the Hand02 three-bone set, then increase
   to the configured cadence.
5. Only compare an optional transform-array fast path after it agrees with the
   reflected result for 300 frames. It is never the default path.

Any missing object, invalid transform, scene transition, idle Montage, or failed
function call produces an invalid sample and enters the release state. It never
reuses a stale UObject pointer.

## Geometry and safety states

`FDTCodeCore` calculates canonical axes from a Reference origin/tip and Target
pose. L0 is depth from origin to tip; L1/L2 are local planar offsets; R0/R1/R2
are relative orientation. Device direction and limits are profile/device-layer
settings rather than hidden geometry rules.

The state machine requires three contact samples, holds a target through a 1.25x
release radius, requires a 20% improvement sustained for 250 ms before switching,
and returns to neutral after a 100 ms hold plus 400 ms release. Montage position
is not used as a synthetic motion phase.

## Future device gate

Actual OSR2/SR6 output is out of scope until simulation captures have passed
single-person, multi-person, non-human, speed-change, loop, ESC, bridge timeout,
and game-exit verification. A future device layer must add explicit arming,
per-axis calibration and limits, velocity/acceleration limits, an emergency stop,
and a dead-man timeout. It must not be enabled by changing the current bridge.
