# FDTCode UDP Telemetry v1

The UE4SS C++ mod sends one UTF-8 JSON object per UDP datagram to `127.0.0.1:17891`.
It never sends a device command.

Required fields are `version: 1`, a monotonic `sequence`, `monotonicUs`, a supported
motion `state`, and normalized `L0/L1/L2/R0/R1/R2` axes. Optional diagnostics are
`scene`, `montage`, `section`, `profileId`, `binding`, `contact`, `rawGeometry`, and `reason`.

The bridge rejects invalid, stale, non-loopback, or unknown-version packets. A 250 ms timeout
sets Bridge Offline and returns simulated axes to neutral. `deviceOutput` is permanently disabled.
