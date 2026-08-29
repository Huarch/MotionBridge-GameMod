# MotionBridge 游戏 Mod — Fallen Doll Playtest

[English](README.md) | 简体中文

本分支提供 **Operation Lovecraft: Fallen Doll Playtest** 的 UE4SS Mod。它识别当前 HAnime，并将所需功能骨数据实时发送给 [MotionBridge](https://github.com/Huarch/MotionBridge)。

必须配合 MotionBridge 使用：桌面界面、3D 预览、动作调节、USB/Wi-Fi 设备连接、TCode 输出和安全回中均由 MotionBridge 负责。此 Mod 本身不直接控制设备、不创建游戏内浮层，也不会修改游戏 Pak 文件。

## 使用前准备

- 安装 Fallen Doll Playtest（桌面或 VR）。
- 下载并启动最新的 [MotionBridge](https://github.com/Huarch/MotionBridge/releases)。
- 下载由 `fallen-doll-playtest` 分支构建的 Mod 包，或下载匹配的 [Release](https://github.com/Huarch/MotionBridge-GameMod/releases)。

## 安装与使用

1. 关闭游戏。
2. 解压 Mod 包。运行 `Install-Mod.ps1` 并选择 Fallen Doll Playtest 游戏目录；也可以将包内 `Game` 目录的内容复制到游戏目录中的 `Paralogue/Binaries/Win64`。
3. 启动 MotionBridge；如需使用实体设备，再配置 USB 或 Wi-Fi。
4. 启动 Fallen Doll Playtest 并进入 HAnime。
5. 确认 MotionBridge 显示 Fallen Doll 数据流为 **Online**。开启真实设备输出前，先打开 3D 预览检查方向和行程。
6. 离开 HAnime 或数据流中断后，MotionBridge 会安全回中。

安装命令示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\Games\Fallen Doll Playtest"
```

Mod 包包含匹配的 UE4SS 文件；MotionBridge 与游戏 Mod 独立下载、独立更新。

## 快捷键

- `F6`：提示不安全的 UE 5.7 运行时诊断已禁用
- `F10`：只热重载 HAnime 检测逻辑，已注册的 UE4SS 回调不会重建

## 开发结构

- `fd_tcode_probe/` 是当前启用的 UE4SS Mod；`fd_tcode_reloader/` 仅为旧版本保留，默认禁用。
- `fd_tcode_probe/Scripts/fd_tcode/core/` 保存手写运行逻辑。
- `fd_tcode_probe/Scripts/fd_tcode/data/` 保存生成数据与版本专属数据表。
- `tools/` 保存 Playtest 的安装、验证与发布构建脚本；发布构建会先检查模块结构。
- Release ZIP 使用运行文件白名单，不包含 UE4SS 调试符号、开发 Mod、附带文档和其他游戏模板。
- 生成导出、研究数据、本地依赖、构建包和 `.artifacts/` 均保持忽略，不属于此分支源码。
- 跨游戏工具与新游戏模板放在仓库 `master` 分支；Fallen Doll 专属的运行时名称、骨架映射和发布文件只保留在此分支。

## 问题反馈

游戏识别、遗漏姿势、参与者绑定、功能骨映射和 Mod 安装问题，请在本仓库反馈。MotionBridge 的桌面界面、预览、设备连接或输出调节问题，请到 [MotionBridge Issues](https://github.com/Huarch/MotionBridge/issues) 反馈。

游戏页面：[Steam 上的 Fallen Doll Playtest](https://store.steampowered.com/app/1685960/)

这是非官方社区项目，不包含游戏资源或设备驱动。
