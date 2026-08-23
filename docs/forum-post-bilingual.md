# [WIP] Operation Lovecraft: Fallen Doll — real-time TCode / OSR2 / SR6 integration

## English

This is an unofficial community integration for **Operation Lovecraft: Fallen Doll**.
It reads the currently playing HAnime skeleton in real time through UE4SS Lua and
sends a compact functional-bone stream to F8Studio. F8Studio calculates L0, provides
3D Skeleton and SR6/OSR viewers, and can output TCode over USB or Wi-Fi.

Unlike an animation-progress curve or a pre-made Funscript, the signal follows the
current in-game skeleton pose, including animation-speed changes.

### Current features

- Playtest/Closed Beta desktop and VR layouts
- old Demo desktop and VR layouts
- exact HAnime Montage detection; menus, idle, expressions, and ordinary transitions
  are excluded
- event-driven character and action switching with low-overhead functional-bone sampling
- participant and functional-bone priority selection
- direct L0 with 3D Skeleton and SR6/OSR viewers
- USB or Wi-Fi TCode output (only one may be enabled)
- 250 ms last-value hold and a 600 ms smooth return to `L05000` on stream loss
- F10 Lua hot reload for development

Physical-device support is currently **L0 only**. Some left/right and dual-limb
priorities, special actions, multiplayer scenes, and non-human poses still need
annotation. The other five SR6 axes are future work, so this should be considered WIP.

### Quick start

1. Close the game and install the package's `Game` folder into the matching
   `Paralogue/Binaries/Win64` directory. The tested UE4SS runtime is included.
2. Use an F8Studio build containing `Fallen Doll Source`, import the included project,
   and Deploy it.
3. Confirm `studio`, `fd_pyengine`, and `fd_source` are running. Studio automatically
   starts the latter two.
4. Enter HAnime and verify motion in a Viewer first.
5. After checking direction and range, enable either USB or Wi-Fi output—never both.

- Download: [v0.16.5 package](https://github.com/Huarch/FallenDollTCode/releases/download/v0.16.5/FallenDollTCode-0.16.5-event-driven-switch.zip)
- Source and documentation: [Huarch/FallenDollTCode](https://github.com/Huarch/FallenDollTCode)
- F8Studio integration PR: [feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)
SHA-256: `D0BA2D6B6F588F673653C14780909256FD0A2CBAA46CCFAC8A8331D7459AB855`

Both physical-output nodes are disabled by default. Please verify the Viewer, direction,
range, stream-loss centering, and your emergency-stop method before connecting a device.
The package does not include game assets, F8Studio binaries, or device drivers.

---

## 中文

这是 **Operation Lovecraft: Fallen Doll** 的非官方社区 TCode 接入项目。游戏侧通过
UE4SS Lua 实时读取当前 HAnime 的功能骨骼，F8Studio 负责计算 L0、显示 3D 骨骼与
SR6/OSR Viewer，并可通过 USB 或 Wi-Fi 输出 TCode。

它不是按照动画进度播放预制曲线或 Funscript，而是跟随游戏当前帧的骨骼姿态；调整
动画速度后，信号也会随画面同步。

### 当前功能

- 支持 Playtest/Closed Beta 桌面与 VR，以及旧 Demo 桌面与 VR 的目录结构
- 精确识别 HAnime Montage，排除主菜单、待机、表情和普通转场
- 角色与动作切换采用事件触发，只采集当前动作需要的紧凑功能骨集合
- 可选择参与者以及功能骨优先级
- 直接 L0、3D Skeleton Viewer 和 SR6/OSR Viewer
- USB 或 Wi-Fi TCode 输出，两者只能启用一个
- 断流时保持最后值 250 ms，再用 600 ms 平滑回到 `L05000`
- 开发时可用 F10 热重载 Lua

目前真实设备正式支持范围仅为 **L0**。部分左右手脚、双肢主次、特殊动作、多人和
非人类姿势仍需继续标注，另外五轴属于后续目标，因此当前版本仍是 WIP。

### 快速使用

1. 关闭游戏，将发布包 `Game` 中的内容安装到对应版本的
   `Paralogue/Binaries/Win64`；包内已包含验证过的 UE4SS。
2. 使用包含 `Fallen Doll Source` 的 F8Studio，导入包内工程并 Deploy。
3. 确认 `studio`、`fd_pyengine`、`fd_source` 均已运行；后两个服务由 Studio 自动启动。
4. 进入 HAnime，先打开 Viewer 检查动作。
5. 确认方向和范围正确后，只启用 USB 或 Wi-Fi 中的一种输出。

- 下载：[v0.16.5 发布包](https://github.com/Huarch/FallenDollTCode/releases/download/v0.16.5/FallenDollTCode-0.16.5-event-driven-switch.zip)
- 源码与文档：[Huarch/FallenDollTCode](https://github.com/Huarch/FallenDollTCode)
- F8Studio 接入 PR：[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)
SHA-256：`D0BA2D6B6F588F673653C14780909256FD0A2CBAA46CCFAC8A8331D7459AB855`

实体输出节点默认关闭。连接设备前请先验证 Viewer、方向、范围、断流回中和紧急停止
方式。发布包不包含游戏资源、F8Studio 本体或设备驱动。
