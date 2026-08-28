# Motion Bridge — Operation Lovecraft: Fallen Doll Mod

[English](README.md) | 简体中文

这是 [Motion Bridge](https://github.com/Huarch/MotionBridge) 的 Fallen Doll 游戏侧 UE4SS Lua Mod。它实时识别当前 HAnime，并只采集需要的功能骨；Motion Bridge 负责转换 OSR2/SR6 TCode、3D Viewer、动作调节、设备连接及安全回中。

本项目是实时接入，不是离线 Funscript，也不会修改或重新打包游戏 Pak。

当前 Mod 版本：`0.17.0`

## 支持版本

- Closed Beta / Playtest：桌面与 VR
- 旧版 0.49 独立版本
- 旧 Steam Demo：桌面与 VR

Mod 通过事件切换 HAnime 和参与者，以 50 Hz 读取紧凑功能骨集合，不会持续枚举完整骨架，避免早期方案造成的卡顿和物理刷新。

## 安装

1. 从本仓库 [Releases](https://github.com/Huarch/MotionBridge-FallenDoll/releases) 下载最新 Mod ZIP。
2. 关闭游戏。
3. 解压后用游戏目录运行 `Install-Mod.ps1`，也可以把 `Game` 内全部内容复制到对应的 `Paralogue/Binaries/Win64`。
4. 单独下载并启动 [Motion Bridge](https://github.com/Huarch/MotionBridge/releases)。
5. 进入 HAnime，确认 Motion Bridge 显示游戏数据流 **ONLINE**。
6. 先用 3D Viewer 检查动作，再开启真实设备输出。

安装命令示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -GameRoot "D:\游戏目录\Operation Lovecraft Fallen Doll"
```

Mod 发布包内包含匹配的 UE4SS。Motion Bridge 需要单独下载，两个项目可以独立更新。

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

实时识别与骨骼流默认自动启用，不需要侦测开关，也不会创建游戏内浮层。

## 仓库结构

- `fd_tcode_probe/`：HAnime 识别与功能骨输出 Mod
- `fd_tcode_reloader/`：Lua 安全热重载辅助 Mod
- `tools/Install-FallenDollTCode.ps1`：支持版本的安装脚本
- `tools/build_release_package.ps1`：生成 UE4SS Mod 发布包

## 问题反馈

游戏动作识别、遗漏姿势、参与者选择、功能骨映射和 Mod 安装问题，请提交到本仓库。桌面界面、3D Viewer、设备连接和输出调节问题，请提交到 [Motion Bridge](https://github.com/Huarch/MotionBridge/issues)。

游戏商店：[Playtest](https://store.steampowered.com/app/1685960/) · [Demo](https://store.steampowered.com/app/1811180/)

这是非官方社区项目，不包含游戏资源或设备驱动。
