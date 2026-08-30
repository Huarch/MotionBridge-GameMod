# Third-party notices

This repository and release package do not include Operation Lovecraft: Fallen Doll game assets, firmware, or device drivers.

## UE4SS

The Playtest release package is based on the official experimental RE-UE4SS build `zDEV-UE4SS_v3.0.1-1093-gba2efd55.zip` from [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Its `UE4SS.dll` is replaced by a locally built compatibility fork that rejects stale Unreal object return values before exposing them to Lua and avoids process-detach teardown. RE-UE4SS is licensed under the MIT License; the upstream `ue4ss/LICENSE` file is retained in the packaged runtime.

Compatibility source: [Huarch/RE-UE4SS commit `4ff35953`](https://github.com/Huarch/RE-UE4SS/commit/4ff3595375a7f6949179b19d4aa7ea7031a4aa21), published on branch [`codex/fix-ue57-struct-return`](https://github.com/Huarch/RE-UE4SS/tree/codex/fix-ue57-struct-return). The matching [Huarch/UEPseudo commit `a3c0881`](https://github.com/Huarch/UEPseudo/commit/a3c0881c5abdbc31b81e53c9ce50ce451e5ad06b) supplies the corrected UE 5.7 reflected-property layout.

## Game and device names

Operation Lovecraft: Fallen Doll and hardware/product names belong to their respective owners. Their names are used only to describe compatibility. This is an unofficial community project and is not endorsed by the game developer or device vendors.
