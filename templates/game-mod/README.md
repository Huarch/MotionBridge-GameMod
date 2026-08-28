# New game Mod checklist

Create a game-named branch from `master`, then keep these items inside that branch:

1. The UE4SS Mod name, target process and installation layout.
2. Exact runtime object/component discovery for that game.
3. Skeleton, pose, participant and motion-contract data validated for that game only.
4. The MotionBridge runtime file contract and a safe no-signal behavior.
5. A branch-specific installer, bilingual user guide, package name, tag and GitHub Release.

Do not copy Fallen Doll identities, bone names, paths, or Release assets into another game's branch. Shared helpers must remain generic and must be verified against each game's UE4SS runtime before being promoted back to `master`.

## 中文

新游戏从 `master` 创建独立分支。游戏专属的进程、安装目录、运行时对象、骨架/姿势/参与者数据、MotionBridge 文件协议、安装器和 Release 都只能存放在该游戏分支。

不要把 Fallen Doll 的身份数据、骨骼名、路径或 Release 文件复制到其他游戏分支。仅在新旧游戏的 UE4SS 运行时均验证通过后，才将真正通用的工具逻辑回收至 `master`。
