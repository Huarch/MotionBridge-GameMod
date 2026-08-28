# MotionBridge 游戏 Mod — Fallen Doll Demo

[English](README.md) | 简体中文

本分支提供 **Operation Lovecraft: Fallen Doll Demo** 的 UE4SS Mod。它识别当前 HAnime，并将所需功能骨数据实时发送给 [MotionBridge](https://github.com/Huarch/MotionBridge)。

必须配合 MotionBridge 使用：桌面界面、3D 预览、动作调节、USB/Wi-Fi 设备连接、TCode 输出和安全回中均由 MotionBridge 负责。此 Mod 本身不直接控制设备、不创建游戏内浮层，也不会修改游戏 Pak 文件。

## 使用前准备

- 安装 Steam 版 Operation Lovecraft: Fallen Doll Demo。
- 下载并启动最新的 [MotionBridge](https://github.com/Huarch/MotionBridge/releases)。
- 下载由 `fallen-doll-demo` 分支构建的 Mod 包，或下载匹配的 [Release](https://github.com/Huarch/MotionBridge-GameMod/releases)。

## 安装与使用

1. 关闭游戏。
2. 解压 Mod 包。运行 `Install-Mod.ps1` 并选择 Fallen Doll Demo 游戏目录；也可以将包内 `Game` 目录的内容复制到游戏目录中的 `Paralogue/Binaries/Win64`。
3. 启动 MotionBridge；如需使用实体设备，再配置 USB 或 Wi-Fi。
4. 启动 Fallen Doll Demo 并进入 HAnime。
5. 确认 MotionBridge 显示 Fallen Doll 数据流为 **Online**。开启真实设备输出前，先打开 3D 预览检查方向和行程。
6. 离开 HAnime 或数据流中断后，MotionBridge 会安全回中。

安装命令示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\Games\Fallen Doll Demo"
```

Mod 包包含匹配的 UE4SS 文件；MotionBridge 与游戏 Mod 独立下载、独立更新。

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

## 问题反馈

游戏识别、遗漏姿势、参与者绑定、功能骨映射和 Mod 安装问题，请在本仓库反馈。MotionBridge 的桌面界面、预览、设备连接或输出调节问题，请到 [MotionBridge Issues](https://github.com/Huarch/MotionBridge/issues) 反馈。

游戏页面：[Steam 上的 Fallen Doll Demo](https://store.steampowered.com/app/1811180/)

这是非官方社区项目，不包含游戏资源或设备驱动。
