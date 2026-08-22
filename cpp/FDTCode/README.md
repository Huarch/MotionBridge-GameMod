# FDTCode UE4SS DLL

The source is pinned to UE4SS `d7e7826d415b0332b43439a64e6c87f64019be03`.
It is intentionally not built until the private `UEPseudo` submodule is
available. The standalone `FDTCodeCore` target remains buildable and tested
without it.

The DLL's first load stage only verifies ABI compatibility, F11/F12 keybinds,
and the FDTCode ImGui tab. It contains no skeletal UFunction calls. A later
collector stage must be generated from the actual Fallen Doll CXX/UHT dump and
must remain game-thread-only.
