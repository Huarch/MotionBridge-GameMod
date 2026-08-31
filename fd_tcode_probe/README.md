# FD-TCode Lua development mod

This is the live Lua development path for Fallen Doll runtime discovery. It
does not send TCode and does not control a physical device. Full code reload is
owned by a separate broker mod so the target never destroys itself from inside
its own key callback.

## Current stage

- Follow the mandatory static-first workflow in
  `docs/unpacked-data-first.md` and cache confirmed H-system relationships in
  `data/unpacked-hsystem-contract-v1.json` before designing runtime probes.
- Keep `HSceneManager` and animation-manager inspection behind the explicit
  F6/F8 diagnostic path; the automatic stream does not depend on an HScene snapshot.
- Keep compact monitoring to primitive state fields and verified UObject links;
  array/struct containers are deferred until a manual diagnostic requires them.
- Log only when the compact HScene state changes.
- Keep expensive schema and inventory dumps behind manual diagnostics.
- Start only the compact HAnime detector automatically; keep the expensive
  HScene/schema diagnostics manual.
- Reject inactive components that return zero quaternions. The automatic stream binds exact
  TableHAnim Montage owners plus the unpacked family participant roles rather
  than guessing participants from arbitrary skeletal meshes.
- Recognize seven unpacked skeleton catalogs independently: Alet, MaleB,
  Erika, Galatea, Juzi, yanshi, and Anya. Bone names are never shared across
  catalogs merely because two characters are humanoid.
- Match active Montage assets exactly against the generated TableHAnim family
  allowlist. The older 102-pose catalog remains a manual annotation worklist;
  it is not the realtime identity gate and does not imply that limb side or contact
  priority has been verified.
- Keep two read-only static indexes with deliberately limited meanings. The
  `TableHAnim` reference index finds primary pose directories imported by the
  cooked table, including disabled, unreleased, legacy, test, or otherwise
  filtered content; it can also omit shared or redirected poses. The loose Pak
  normal-cycle index is only an animation-asset coverage aid. Neither count nor
  either index's relative size may be presented as the number of HAnime entries
  visible in game. `GetSPAnimCount` is called with UE4SS's required Blueprint
  output table, but its value is only the current SP/session count. The cooked
  `LocalHDatas` name is a Blueprint-local graph symbol, not a reflected live
  property. Full runtime entries therefore use the Card ID accessors, beginning
  with `GetDatabyCardID`.
- Legacy profile and pose-resolver probes remain available for manual
  diagnostics, but the automatic stream never enables an unknown animation from a path/category
  guess. Combined-contact, unknown-partner, and unannotated limb poses remain
  non-driving.
- After the exact HAnime gate opens, stream the currently active registered
  primary participants as a compact functional contact-bone stream at the configured
  20 ms target interval (50 Hz). Pose geometry profiles are not an
  output prerequisite and F8Studio owns no Fallen Doll matching rules.
- Keep the unpacked common skeleton and functional-bone catalog available for
  diagnostics, but emit only the compact functional contact set on the realtime
  path.
  Participants receive deterministic indices within the generic `male/female`
  motion role and separate stable keys, including multiplayer scenes.
- Derive participant candidates and their A/B/C priority from the unpacked
  TableHAnim participant tags. Runtime Montage ownership binds those static
  slots to live components; F8Studio may disable any participant and fall back
  to the next enabled ranked slot, or disable all output.
- Treat modular meshes as one character: only the catalog's confirmed primary
  component is eligible. The exact HAnime family supplies per-role participant
  counts, preventing shared body/clothing SkinnedAssets from multiplying one
  actor into dozens of streams.
- Emit generic `male/female` motion identities for F8Studio selectors while
  preserving the exact playable-character catalog as `characterRole` and
  `catalogId` trailer metadata.
- Keep full-body debug skeletons out of the realtime path. Each participant
  contributes only the compact candidates required by the current interaction
  category: left/right hands, left/right feet, mouth/tongue, one vaginal/anal
  contact point, or the penetration-axis origin/tip. Unrelated categories are
  not sampled in the same frame. The packet trailer ranks verified candidates;
  F8Studio may disable
  any candidate and falls back to the next enabled ranked bone. Alet/Male
  Hand02 is currently annotated right-hand primary and left-hand secondary.
  Other hand/foot poses remain recognized but have no automatic ranked output
  until left/right, combined-limb, and primary/secondary annotations exist.
  Special actions do not change the selected bone in this milestone. Montage
  discovery is polled separately at 250 ms, so speed changes are represented
  by current transforms rather than a fixed-rate animation phase.
- Perform global skeletal-component discovery only when the Mod stream starts, a cached
  component becomes invalid, or a dormant stream observes a confirmed
  `Exp_In`/`Exp_Sexing` HAnime re-entry. `Exp_Idle` never performs discovery or
  consumes the one-shot re-entry recovery. The realtime gate does not call
  `HScene.snapshot`; its multi-class searches remain explicit F6/F8 diagnostics.
- Write F8Studio-compatible skeleton JSON lines to
  `%USERPROFILE%/.f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson`.
  `F8STUDIO_GAMES_DIR` may relocate the shared games directory and
  `FD_TCODE_RUNTIME_DIR` may override only Fallen Doll's runtime directory.
  The game Mod and F8Studio must inherit the same override when one is used.
  Positions are converted from Unreal centimetres to metres; rotations are
  reordered from Unreal XYZW to F8 WXYZ. Coordinate handedness is intentionally
  unchanged until the first 3D Viz comparison.
- Do not calculate axes or control devices in Lua.
- Treat HAnime identity as a hard game-side output gate. `TableHAnim` defines
  477 authoritative HAnime families; the read-only full Pak index expands
  those families to 3,081 exact primary, companion-character, and item Montage
  assets. Three consecutive frames confirm a new HAnime. Unrelated idle and
  expression Montages remain outside the allowlist.
- Never use category words, geometry proximity, Montage position, or the old
  Hand fallback to classify an unknown animation as HAnime. Idle and transition
  animation therefore produce no skeleton packets for F8Studio. HManager/Card
  access remains diagnostic data; realtime identity comes only from exact active
  Montage assets in the generated allowlist.
- Include `hanimeActive`, `hanimeId`, `hanimeAsset`, `hanimeCategory`,
  `hanimePhase`, `hanimeState`, and `recognitionSource` in the ordinary skeleton
  trailer. F8Studio remains a generic receiver and owns no Fallen Doll rules.

## Keys

- `F6`: start/stop the HScene state monitor.
- `F7`: reserved for the external F8Studio preview launcher; it is not
  registered by Lua yet.
- `F8`: export the current runtime-filtered pose list once to
  `runtime/fd-visible-poses.tsv`. It does not start a recorder.
- The functional contact-bone stream is armed automatically. Exact HAnime opens
  the output gate; idle/exit closes it while low-frequency
  re-entry detection remains active.
- `F10`: fully reload `fd_tcode_probe` through the separate reload broker.

UE4SS global hot reload and automatic file watching remain disabled. The broker
uses `RestartMod("fd_tcode_probe")`; do not call `RestartCurrentMod()` from a
callback owned by `fd_tcode_probe`. Invalid rule files are rejected and the
last valid in-memory rules remain active until the next successful reload.

The Lua mod does not build an Unreal/Canvas UI. Visualization is owned by
F8Studio. Its managed `Fallen Doll Source` incrementally reads the spool file;
the legacy localhost UDP relay is not required by the current v15 project.

## Layout

- `Scripts/main.lua`: minimal protected entry point.
- `fd_tcode/app.lua`: minimal lifecycle entry point.
- `fd_tcode/config.lua` and `fd_tcode/edition_local.lua`: runtime and edition configuration.
- `fd_tcode/core/`: hand-written runtime logic.
- `fd_tcode/data/`: generated identity, profile, calibration, and body-plane tables.
- `fd_tcode/core/runtime.lua`: change-only monitor.
- `fd_tcode/core/hscene.lua`: HScene discovery and plain snapshot construction.
- `fd_tcode/core/bone_probe.lua`: active-participant binding and compatibility Hand
  sampler.
- `fd_tcode/core/profile_probe.lua`: profile-selected primary/reference binding for
  all registered playable skeletons.
- `fd_tcode/core/pose_resolver.lua`: HScene/Montage matching against the hot pose
  catalog.
- `fd_tcode/core/hanime_detector.lua`: exact active-Montage HAnime gate,
  acquisition/release state, and idle-to-HAnime component-cache recovery.
- `fd_tcode/core/generic_hanime_probe.lua`: profile-free active-participant skeleton
  sampler used only while the exact HAnime gate is open.
- `fd_tcode/data/hanime_identity_data.lua`: generated `TableHAnim` Montage allowlist.
- `fd_tcode/core/pose_catalog_probe.lua`: safe, one-shot active `HManager_C`
  `LocalHDatas` reflection and TSV export.
- `data/hanim-table-index-v1.json`: direct primary-character asset references
  from `/Game/Data/TableHAnim`; not a visible pose count or count bound.
- `data/character-pose-index-v1.json`: loose Pak normal-cycle asset coverage;
  not an in-game pose count.
- `fd_tcode/core/diagnostics.lua`: manual detailed diagnostics.
- `fd_tcode/core/safe.lua`: protected Unreal reads and value formatting.
- `fd_tcode/data/profile_data.lua`: legacy/manual geometry rules; not consumed by
  the automatic functional contact stream.
- `fd_tcode/core/profile_store.lua`: validated refresh/fallback for those manual
  diagnostics.

## Static-formal profile sidecars

The game-side profile store can read table-ready static formal records without
turning them into calibrated geometry. Before launching the Mod, set exactly
one edition value in its environment:

```powershell
$env:FD_TCODE_GAME_EDITION = "demo-ue4.25" # Demo
# or
$env:FD_TCODE_GAME_EDITION = "playtest-ue5" # Playtest
```

With `demo-ue4.25`, only `demo_static_formal_profile_data.lua` is merged.
With `playtest-ue5`, only the Playtest F/F and nonhuman static sidecars are
merged. Missing or invalid values load no static-formal sidecar, rather than
mixing editions with potentially colliding HAnime IDs. A sidecar never replaces
an existing `enabled_for_simulation_validation` calibrated profile. Static rows
remain `static_formal_pending_runtime_calibration`; they have no geometry or
local-axis calibration. These files are generated in the workspace only—this
repository does not deploy or overwrite an external game installation.
