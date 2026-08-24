# Operation Lovecraft: Fallen Doll TCode Mod

非官方的实时 TCode 接入项目。游戏侧使用 UE4SS Lua 读取正在播放的 HAnime
功能骨骼，F8Studio 负责参与者/功能骨选择、L0 计算、Viewer、安全回中以及
USB 或 Wi-Fi 输出。它不是离线 Funscript，也不修改或重新打包游戏 Pak。

当前版本：`0.16.6`

游戏商店：
[Operation Lovecraft: Fallen Doll（Steam）](https://store.steampowered.com/app/1685960/)
 · [Demo（Steam）](https://store.steampowered.com/app/1811180/)

## 支持范围

- Closed Beta / Playtest（桌面与 VR）
- 旧 Demo（桌面与 VR）
- Playtest：508 个 HAnime family、3081 条精确 Montage 身份
- Demo：217 个 HAnime family、1160 条精确 Montage 身份
- 实时 3D 骨骼与 SR6/OSR Viewer
- SR6/OSR2 的 L0 输出；USB 与 Wi-Fi 二选一
- HAnime/参与者切换使用组件与 Montage 事件触发，低频轮询只作核验
- 断流保持最后值 250 ms，再用 600 ms 平滑回到 `L05000`

当前真实设备链只正式支持 L0。部分 Hand/Foot 的左右侧和主次骨、特殊动作、
多人及非人类动作仍需继续标注；其余五轴属于后续目标。

## 数据链路

```text
Operation Lovecraft: Fallen Doll
  → UE4SS Lua（精确识别 HAnime，采集紧凑功能骨集合）
  → ~/.f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson
  → Fallen Doll Source (fd_source)
  → PyEngine (fd_pyengine)
  → 3D Viewer / Relative L0 / TCode / OSR Viewer / USB 或 Wi-Fi
```

`studio` 是 F8Studio 主程序自身。导入并 Deploy 工程后，它应自动启动
`fd_pyengine` 和 `fd_source`，不需要玩家手动开三个窗口。

## 快速开始

1. 关闭游戏，把发布包 `Game` 内的内容复制到对应版本的
   `Paralogue/Binaries/Win64`；也可使用包内 `Install-Mod.ps1`。
2. 使用包含 `Fallen Doll Source` 的 F8Studio，导入
   `f8studio/fallen-doll-skeleton-preview-v16.json` 并 Deploy。
3. 确认 `studio`、`fd_pyengine`、`fd_source` 均为 Running/Active。
4. 只启用 USB 或 Wi-Fi 中的一种输出。首次使用先打开 Viewer，不连接设备。
5. 启动游戏并进入 HAnime；离开动作或断流会自动安全回中。

详细安装与排错：

- [中文用户说明](docs/user-guide-zh.md)
- [English user guide](docs/user-guide-en.md)
- [中文启动与排错](docs/startup-and-troubleshooting-zh.md)
- [English startup and troubleshooting](docs/startup-and-troubleshooting-en.md)

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

实时识别与骨骼流默认自动待命，不需要启动/停止侦测快捷键。Lua 不创建游戏内
UI，Viewer 是 F8Studio 的独立窗口。

## 工程目录

- `fd_tcode_probe/`：游戏侧 Lua Mod
- `fd_tcode_reloader/`：Lua 安全热重载 broker
- `data/`：从解包资料生成的 HAnime、姿势与骨架索引
- `f8studio/`：F8Studio 工程导出及 Fallen Doll Source 上游补丁
- `tools/`：数据生成、安装、启动与发布脚本
- `docs/`：用户文档、发布帖与解包资料约束

解包数据在运行实验前优先使用，详见
[unpacked-data-first.md](docs/unpacked-data-first.md)。运行时不再周期性全局枚举整套
骨架，避免游戏卡顿和物理刷新。

## F8Studio

测试工程：`Fallen Doll Skeleton Preview v16 (direct L0)`
Project ID：`a2bfd785-51a2-4920-86d3-3bc82d262f36`

Fallen Doll Source 上游 PR：
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

共享工程中的 Wi-Fi 与 USB 节点都默认关闭，USB 端口为空。两个输出不能同时
启用。Wi-Fi 默认目标为 `tcode.local:8000`；USB 使用设备对应串口及 115200
波特率。

这是非官方社区项目。仓库与发布包不包含游戏资源、F8Studio 二进制或设备驱动。
