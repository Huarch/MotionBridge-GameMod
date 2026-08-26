# Motion Bridge — Operation Lovecraft: Fallen Doll

[English](README.md) | 简体中文

这是 Motion Bridge 的 Operation Lovecraft: Fallen Doll 游戏适配仓库。
UE4SS Lua Mod 识别当前 HAnime 并输出精简的功能骨帧；Motion Bridge 将实时动作
转换为 OSR2/SR6 TCode，提供 3D Viewer、设备连接与安全回中。本项目不是离线
Funscript，也不会修改或重新打包游戏 Pak。

当前版本：`0.17.0`

`0.17.0` 正式启用 `fallen-doll-skeleton-preview-v17.json` 的实时多轴运动引擎。
SR6 接收 `L0/L1/L2/R0/R1/R2` 六轴，OSR2 使用同一运动流中的 `L0`。实现与
校准边界见 [multi-axis-v17-dev.md](docs/multi-axis-v17-dev.md)。

游戏商店：
[Operation Lovecraft: Fallen Doll（Steam）](https://store.steampowered.com/app/1685960/)
· [Demo（Steam）](https://store.steampowered.com/app/1811180/)

## 支持范围

- Closed Beta / Playtest（桌面与 VR）
- 旧版 0.49 独立版本（`KiritoMod049.exe`，Unreal Engine 4.25）
- 旧 Demo（桌面与 VR）
- Playtest：508 个 HAnime family、3,087 条精确 Montage 身份
- Demo：217 个 HAnime family、1,160 条精确 Montage 身份
- 50 Hz 实时功能骨采集与 VaM 式接触几何
- SR6 六轴输出、OSR2 L0 输出，以及独立的 SR6/OSR 3D Viewer
- 六轴独立范围滑条；USB 与 Wi-Fi 二选一
- HAnime/参与者切换使用组件与 Montage 事件触发，低频轮询只作核验
- 断流保持最后值 250 ms，再用 600 ms 平滑回到 `L05000`

多轴管线已经可以正常使用，但“支持六轴”不代表全部 HAnime 都已逐条人工校准。
部分 Hand/Foot 的左右侧和主次骨、特殊动作、多人及非人类动作仍需继续标注。
遇到未校准姿势时，应先使用 Viewer 检查方向，并在 Motion Bridge 中限制各轴设备范围。

## 数据链路

```text
Operation Lovecraft: Fallen Doll
  → UE4SS Lua（精确识别 HAnime，采集紧凑功能骨集合）
  → ~/.f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson
  → Motion Bridge Fallen Doll Adapter
  → 接触几何、六轴、安全回中和范围映射
  → 3D SR6/OSR Viewer → TCode → USB、Wi-Fi 或 Intiface
```

数据流路径继续兼容已有安装，但正常使用不再需要 F8Studio、`fd_source` 或
`fd_pyengine`。

## 快速开始

1. 关闭游戏，把发布包 `Game` 内的内容复制到对应版本的
   `Paralogue/Binaries/Win64`，也可以运行包内的 `Install-Mod.ps1`。
2. 解压并启动 Motion Bridge；Full 完整包已包含匹配的便携版本。
3. 确认 Motion Bridge 显示 Fallen Doll 数据流 Online。
4. 选择 USB、Wi-Fi 或 Intiface。首次使用时先打开 3D Viewer 验证动作，再解锁
   真实设备输出。
5. 启动游戏并进入 HAnime；离开动作或断流后会自动安全回中。

详细安装与排错：

- [中文用户说明](docs/user-guide-zh.md)
- [English user guide](docs/user-guide-en.md)
- [中文启动与排错](docs/startup-and-troubleshooting-zh.md)
- [English startup and troubleshooting guide](docs/startup-and-troubleshooting-en.md)

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

实时识别与骨骼流默认自动待命，不需要启动/停止侦测快捷键。Lua Mod 不创建
游戏内 UI，Motion Bridge Viewer 是独立桌面窗口。

## 工程目录

- `fd_tcode_probe/`：游戏侧 UE4SS Lua Mod
- `fd_tcode_reloader/`：Lua 安全热重载 broker
- `data/`：从解包资料生成的 HAnime、姿势与骨架索引
- `f8studio/`：可选的旧版/开发调试工程及上游补丁
- `tools/`：数据生成、安装、启动与发布脚本
- `docs/`：用户文档、发布帖与解包资料约束

运行实验前优先使用解包数据，详见
[unpacked-data-first.md](docs/unpacked-data-first.md)。运行时不再周期性全局枚举整套
骨架，以避免游戏卡顿和物理刷新。

## Motion Bridge

原生 Motion Bridge 桌面程序已迁移到独立仓库，其中包含 Qt 桌面界面、多游戏
Adapter 协议、运动引擎、设备输出、SR6 预览、便携构建及 F8Studio 配置迁移
工具。本仓库此后只维护 Fallen Doll 游戏侧接入和对应的 F8Studio 流程。

源码与独立版本发布地址：
[Huarch/MotionBridge](https://github.com/Huarch/MotionBridge)

Fallen Doll 仍是 Motion Bridge 首个内置 Adapter，并继续读取相同的
`fd-skeleton.ndjson` 数据流。游戏 Release 为新用户提供 Full 完整包，同时为已
安装 Motion Bridge 的用户提供体积更小的 Mod-only 包。

## 可选 F8Studio 流程

正常运行 Mod 已不再需要 F8Studio。现有 `Fallen Doll Skeleton Preview v17`
工程继续用于节点图编辑、诊断以及与独立运动引擎进行对比。

Fallen Doll Source 上游 PR：
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

共享工程中的 Wi-Fi 与 USB 节点均默认关闭，USB 端口为空。两个输出不能同时
启用。Wi-Fi 默认目标为 `tcode.local:8000`；USB 使用设备对应串口及 115200
波特率。

这是一个非官方社区项目。仓库与发布包不包含游戏资源、F8Studio 二进制或设备驱动。
