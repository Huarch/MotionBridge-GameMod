# MotionBridge 游戏 Mod — Fallen Doll Demo / Legacy 0.49

[English](README.md) | 简体中文

本分支提供 **Operation Lovecraft: Fallen Doll Demo** 与旧版 **0.49** 游戏的 UE4SS Mod。它识别当前 HAnime，并将所需功能骨数据实时发送给 [MotionBridge](https://github.com/Huarch/MotionBridge)。

必须配合 MotionBridge 使用：桌面界面、3D 预览、动作调节、USB/Wi-Fi 设备连接、TCode 输出和安全回中均由 MotionBridge 负责。此 Mod 本身不直接控制设备、不创建游戏内浮层，也不会修改游戏 Pak 文件。

## 支持的游戏版本

- Steam Demo：桌面版与 VR 版
- Legacy 独立旧版：`0.49`

以上是游戏兼容版本。单独的 `0.17.x` 是 Mod 安装包自身版本，不是 Fallen Doll 的游戏版本。

## 使用前准备

- 安装 Steam Demo，或 Legacy `0.49` 旧版游戏。
- 下载并启动最新的 [MotionBridge](https://github.com/Huarch/MotionBridge/releases)。
- 下载由 `fallen-doll-demo` 分支构建的 Mod 包，或下载匹配的 [Release](https://github.com/Huarch/MotionBridge-GameMod/releases)。

## 安装与使用

1. 关闭游戏。
2. **完整解压** Mod ZIP，不要直接在 ZIP 预览窗口中运行文件。
3. 双击 **`Install Mod.cmd`**，然后选择 **Demo Desktop**、**Demo VR** 或 **Legacy 0.49**。安装器会搜索 Steam 库，显示检测到的目标位置，检查 runtime 目录写入权限，安装 Mod，并验证必需文件。自动检测失败时，按提示选择游戏最外层目录。
4. 等待出现 **Installation verified successfully**。如果失败，请保持窗口打开，并在反馈时附上 `Install-Mod.log`。
5. 启动 MotionBridge，再启动所选 Fallen Doll 版本并进入 HAnime。
6. 确认 MotionBridge 显示 Fallen Doll 数据流为 **Online**。开启真实设备输出前，先打开 3D 预览检查方向和行程。

安装器、游戏和 MotionBridge 应使用同一个 Windows 用户运行，通常不需要管理员权限。`Install-Mod.ps1` 仍保留给脚本化部署使用，普通用户只需运行 `Install Mod.cmd`。

### 手动安装（仅作备用）

1. 完全关闭 Fallen Doll，并完整解压下载的 Mod ZIP。
2. 根据版本选择游戏最外层目录内的目标路径：

| 游戏版本 | 目标路径 |
|---|---|
| Demo Desktop | `Desktop\WindowsNoEditor\Paralogue\Binaries\Win64` |
| Demo VR | `VR\WindowsNoEditor\Paralogue\Binaries\Win64` |
| Legacy 0.49 | `Paralogue\Binaries\Win64` |

3. 打开解压包内的 `Game` 文件夹，将其中的**内容**——`dwmapi.dll` 和 `ue4ss` 文件夹——复制到上方对应的目标目录。不要把外层 `Game` 文件夹本身复制进去。Windows 提示时，允许合并 `ue4ss` 并替换安装包提供的 Mod 文件。
4. 确认所选目标目录最终包含：

```text
<目标目录>
├─ dwmapi.dll
└─ ue4ss
   ├─ UE4SS.dll
   └─ Mods
      └─ fd_tcode_probe
         └─ Scripts
            └─ main.lua
```

5. 先启动 MotionBridge，再启动所选游戏版本并进入 HAnime。收到新动作帧后，MotionBridge 从 **STREAM WAITING** 变为 **STREAM ONLINE**，才表示安装正常运行。
6. 如果数据流一直处于等待状态，请打开 `<目标目录>\ue4ss\UE4SS.log`，并检查进入 HAnime 后 `%USERPROFILE%\.f8\studio\games\fallen-doll\runtime\fd-skeleton.ndjson` 是否存在且持续更新。

Mod 包包含匹配的 UE4SS 文件；MotionBridge 与游戏 Mod 独立下载、独立更新。

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

## 开发结构

- `fd_tcode_probe/` 与 `fd_tcode_reloader/` 是唯一需要部署的 UE4SS Mod 源码。
- `fd_tcode_probe/Scripts/fd_tcode/core/` 保存手写运行逻辑。
- `fd_tcode_probe/Scripts/fd_tcode/data/` 保存生成数据与 Demo 专属数据表。
- `tools/` 保存验证、安装与发布脚本；发布构建会先检查模块结构。

## 问题反馈

游戏识别、遗漏姿势、参与者绑定、功能骨映射和 Mod 安装问题，请在本仓库反馈。MotionBridge 的桌面界面、预览、设备连接或输出调节问题，请到 [MotionBridge Issues](https://github.com/Huarch/MotionBridge/issues) 反馈。

游戏页面：[Steam 上的 Fallen Doll Demo](https://store.steampowered.com/app/1811180/)

这是非官方社区项目，不包含游戏资源或设备驱动。
