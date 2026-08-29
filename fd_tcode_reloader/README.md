# FD-TCode reload broker

Legacy helper for pre-UE 5.7 builds. It is disabled by default.

The current `fd_tcode_probe` owns F10 and reloads only its HAnime detector
module. Do not enable this helper on the UE 5.7 Playtest: `RestartMod` replaces
the complete Lua state and can invalidate delayed UObject wrappers.
