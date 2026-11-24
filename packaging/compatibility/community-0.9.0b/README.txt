MotionBridge Mod 0.18.1 — Fallen Doll Community 0.9.0b compatibility

Scope / 支持范围
- Community 0.9.0b, tested build 7313, desktop and VR single-player rooms.
- 社区版 0.9.0b，已实测构建 7313、桌面及 VR 单人房。
- Requires base Playtest Mod 0.18.1 and its supplied UE4SS DLL.
- 先安装基础 Playtest Mod 0.18.1，保留包内配套的 UE4SS DLL。
- Community multiplayer, physical-device movement and other executable
  layouts remain unverified. 社区版多人、其他构建及真实设备动作尚未验证。

Install / 安装
1. Close the game. 关闭游戏。
2. Install base Mod 0.18.1 with Install Mod.cmd. 先安装基础 Mod 0.18.1。
3. Extract this entire ZIP and run Install Compatibility.cmd.
   完整解压本兼容补丁，运行 Install Compatibility.cmd。
4. Select the game root containing Paralogue. 选择包含 Paralogue 的游戏根目录。
5. Start MotionBridge and the game, then enter a laboratory animation.
   启动 MotionBridge 和游戏，进入实验室动画；正常冷启动无需按 F10。

The full Mod ZIP also provides Install Community Compatibility.cmd, which runs
this same add-on after base installation. 完整 Mod ZIP 也提供此补丁的独立安装入口。

Changes / 修复内容
- Three signatures: StaticConstructObject_Internal, FUObjectHashTables::Get,
  GNatives. 补充三个 UE4SS 扫描符号的签名。
- Read native PlayerAction.Type only in the PC/VR single-room maps after verifying the
  local controller and LocalPlayer backlink. 仅在确认的本地单人房读取动作状态。
- Character BeginPlay rearms one acquisition after title-world startup;
  steady sampling does not repeatedly scan all objects. 修复菜单冷启动后的房间获取。
- The installer checks the tested EXE layout and detector, and backs up all five
  affected files. 安装前核对代码布局及检测器，备份五个受影响文件。
- Preserve UE4SS.dll, settings, FName signature, local config and edition marker.
  保留原有 DLL、设置、FName 签名、本地配置和版本标记。
- No game EXE, Pak file or launcher is included or modified by this add-on.
  此补丁不包含或修改游戏 EXE、Pak 文件及启动器。

Validation / 验证
- 37 action-gate, cold-start and VR assertions passed. 37 项门控、冷启动及 VR 检查通过。
- Install/reinstall/restore, configuration preservation, and rejection of unknown
  builds/detectors checked. 安装、重装、回滚、保留配置和拒绝未知代码检查通过。
- A fresh launch through the locally tested Dollhouse compatibility launcher,
  without F10, reached MotionBridge Online with two participants streaming.
  使用实测的本地 Dollhouse 兼容启动器冷启动后，无需 F10 即恢复在线及双参与者数据。
- Launchers and content backports are separate and are not included here.
  启动器及内容回移补丁独立提供，不包含在本包内。

Rollback / 回滚
Close the game, then run Install-Compatibility.ps1 with -GameRoot and
-RestoreBackup, using the backup path printed during installation.
关闭游戏后，使用安装器显示的备份目录运行 -RestoreBackup，恢复本补丁涉及的五个文件。
