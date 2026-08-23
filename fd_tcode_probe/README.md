# FD-TCode Lua development mod

This is the live Lua development path for Fallen Doll runtime discovery. It
does not send TCode and does not control a physical device. Full code reload is
owned by a separate broker mod so the target never destroys itself from inside
its own key callback.

## Current stage

- Follow the mandatory static-first workflow in
  `docs/unpacked-data-first.md` and cache confirmed H-system relationships in
  `data/unpacked-hsystem-contract-v1.json` before designing runtime probes.
- Select a live `HSceneManager` instead of globally guessing skeletal meshes.
- Read known HScene and animation-manager properties safely.
- Keep compact monitoring to primitive state fields and verified UObject links;
  array/struct containers are deferred until a manual diagnostic requires them.
- Log only when the compact HScene state changes.
- Keep expensive schema and inventory dumps behind manual diagnostics.
- Do not access Unreal objects automatically during startup.
- Reject inactive components that return zero quaternions, bind components to
  the current HScene participant objects, and automatically rediscover a pair
  when an old component remains alive after an animation change.
- Recognize seven unpacked skeleton catalogs independently: Alet, MaleB,
  Erika, Galatea, Juzi, yanshi, and Anya. Bone names are never shared across
  catalogs merely because two characters are humanoid.
- Match the current HScene animation ID or active Montage against the generated
  102-pose catalog. Thirty-two Alet/Male hand, foot, mouth, anal, and vaginal
  profiles have enough verified catalog geometry to enter simulation
  validation; all other matches remain explicitly catalog-only or unmapped
  until their partner skeleton/contact axis is exported.
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
- Infer an additional profile family from a full active Montage path when an
  exact Alet catalog entry does not exist. The primary role follows the Montage
  owner (`alet/anya/erika/galatea/juzi/yanshi`) and resolves that skeleton's own
  functional bone names; combined-contact and unknown-partner poses remain
  non-driving until their participant binding is explicit.
- After the exact HAnime gate opens, stream the currently active registered
  participant skeletons directly at 20 Hz. Pose geometry profiles are not an
  output prerequisite and F8Studio owns no Fallen Doll matching rules.
- Emit a compact 22-bone common humanoid motion set plus each catalog's known
  contact bones. Same-catalog participants receive deterministic role indices
  and separate stable keys, including multiplayer scenes.
- Write F8Studio-compatible skeleton JSON lines to `runtime/fd-skeleton.ndjson`.
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
  animation therefore produce no skeleton packets for F8Studio. The active
  single-player `HManager_C` is the authoritative owner for `AnimID` and state;
  detached room components are not used in its place.
- Include `hanimeActive`, `hanimeId`, `hanimeAsset`, `hanimeCategory`,
  `hanimePhase`, `hanimeState`, and `recognitionSource` in the ordinary skeleton
  trailer. F8Studio remains a generic receiver and owns no Fallen Doll rules.

## Keys

- `F6`: start/stop the HScene state monitor.
- `F7`: reserved for the external F8Studio preview launcher; it is not
  registered by Lua yet.
- `F8`: export the current runtime-filtered pose list once to
  `runtime/fd-visible-poses.tsv`. It does not start a recorder.
- `F9`: start/stop the continuous 20 Hz skeleton stream.
- `F10`: fully reload `fd_tcode_probe` through the separate reload broker.

UE4SS global hot reload and automatic file watching remain disabled. The broker
uses `RestartMod("fd_tcode_probe")`; do not call `RestartCurrentMod()` from a
callback owned by `fd_tcode_probe`. Invalid rule files are rejected and the
last valid in-memory rules remain active until the next successful reload.

The Lua mod does not build an Unreal/Canvas UI. Visualization is owned by
F8Studio and consumes copied skeleton packets through localhost UDP.

## Layout

- `Scripts/main.lua`: minimal protected entry point.
- `fd_tcode/app.lua`: lifecycle and key registration.
- `fd_tcode/runtime.lua`: change-only monitor.
- `fd_tcode/hscene.lua`: HScene discovery and plain snapshot construction.
- `fd_tcode/bone_probe.lua`: active-participant binding and compatibility Hand
  sampler.
- `fd_tcode/profile_probe.lua`: profile-selected primary/reference binding for
  all registered playable skeletons.
- `fd_tcode/pose_resolver.lua`: HScene/Montage matching against the hot pose
  catalog.
- `fd_tcode/hanime_detector.lua`: exact active-Montage HAnime gate and short
  acquisition/release state.
- `fd_tcode/generic_hanime_probe.lua`: profile-free active-participant skeleton
  sampler used only while the exact HAnime gate is open.
- `fd_tcode/hanime_identity_data.lua`: generated `TableHAnim` Montage allowlist.
- `fd_tcode/pose_catalog_probe.lua`: safe, one-shot active `HManager_C`
  `LocalHDatas` reflection and TSV export.
- `data/hanim-table-index-v1.json`: direct primary-character asset references
  from `/Game/Data/TableHAnim`; not a visible pose count or count bound.
- `data/character-pose-index-v1.json`: loose Pak normal-cycle asset coverage;
  not an in-game pose count.
- `fd_tcode/diagnostics.lua`: manual detailed diagnostics.
- `fd_tcode/safe.lua`: protected Unreal reads and value formatting.
- `fd_tcode/config.lua`: hotkeys, polling interval, and known property names.
- `fd_tcode/profile_data.lua`: editable, pure-data runtime rules.
- `fd_tcode/profile_store.lua`: validated F10 rule refresh and fallback state.
