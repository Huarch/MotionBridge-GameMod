# MotionBridge Game Mod — Shared Base

This `master` branch is the shared base for MotionBridge game Mod integrations. It intentionally contains no installable game package, game assets, game-specific skeletons, pose catalogs, or GitHub Release.

## Branches

| Branch | Contents | Release policy |
| --- | --- | --- |
| `master` | Shared UE4SS utilities, templates, and adaptation notes | No game Release |
| `fallen-doll-demo` | Operation Lovecraft: Fallen Doll Demo Mod | Branch-specific Release |
| `fallen-doll-playtest` | Operation Lovecraft: Fallen Doll Playtest Mod | Branch-specific Release |

New game integrations should start from this branch and be created as a separate game-named branch. Keep all game-specific object names, skeleton maps, pose data, installer layout, and release assets in that game branch.

## Shared code

- [`shared/ue4ss/safe.lua`](shared/ue4ss/safe.lua): guarded UE4SS object and transform access.
- [`shared/ue4ss/reload-broker.lua`](shared/ue4ss/reload-broker.lua): an F10 reload helper that keeps the reload callback outside the target Mod.
- [`templates/game-mod/README.md`](templates/game-mod/README.md): the required boundary between shared logic and per-game logic.

The shared files are source templates, not a deployable UE4SS Mod. Copy them into a game branch, set the target Mod name and runtime contract, then validate with that game's installation and logs.

## 中文说明

`master` 是 MotionBridge 游戏 Mod 的共用基础分支，保留可复用的 UE4SS 工具、模板和适配约定。这里不包含可安装游戏包、游戏资源、特定游戏骨架、姿势数据，也不发布 Release。

- 新游戏从 `master` 创建以游戏命名的独立分支。
- 每个游戏分支独立维护对象名、骨架映射、姿势数据、安装器和 Release 包。
- 只把跨游戏可复用的逻辑回收到 `master`。

目前的 Fallen Doll Demo 与 Playtest 包分别由 `fallen-doll-demo`、`fallen-doll-playtest` 发布，均需配合 [MotionBridge](https://github.com/Huarch/MotionBridge) 使用。
