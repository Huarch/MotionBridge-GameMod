# [Release] Operation Lovecraft: Fallen Doll — Real-Time Multi-Axis TCode (OSR2 / SR6)

## English

This is an unofficial real-time TCode integration for **Operation Lovecraft: Fallen Doll**.
UE4SS Lua reads a small set of functional bones from the current HAnime, and F8Studio
converts their live contact motion into TCode. It follows the pose and animation speed in
the game instead of replaying a pre-made Funscript.

Game: [Steam store](https://store.steampowered.com/app/1685960/) ·
[Steam Demo](https://store.steampowered.com/app/1811180/)

### v0.17.0

- real-time SR6 `L0/L1/L2/R0/R1/R2` motion; OSR2 uses `L0`
- 50 Hz compact functional-bone sampling, without continuously reading the full skeleton
- exact HAnime detection; menus, idle, expressions, and ordinary transitions are excluded
- event-driven recovery when changing actions, returning to idle, hiding characters, or
  switching between desktop and VR layouts
- Playtest/Closed Beta and old Demo, both desktop and VR directory layouts
- F8Studio project reorganized into Game Input, Motion Engine, Live Preview, and Device Output
- SR6 model, 3D skeleton and six-axis waveform preview
- per-axis minimum/maximum range sliders in F8Studio
- USB or Wi-Fi TCode output; only one may be enabled

Multi-axis output is ready for use, but not every HAnime has been manually calibrated.
Some left/right and dual-limb priorities, special actions, multiplayer scenes, and non-human
poses may still need adjustment. Please verify a new pose in Live Preview and limit each
axis for your own device before enabling physical output.

### Quick start

1. Close the game and install the package's `Game` folder into the matching
   `Paralogue/Binaries/Win64` directory. UE4SS is included.
2. Use an F8Studio build containing `Fallen Doll Source`, import the bundled v17 project,
   and Deploy it.
3. Confirm `studio`, `fd_pyengine`, and `fd_source` are running. Studio starts the latter two.
4. Enter HAnime and enable Live Preview to verify the SR6 model and waveform.
5. Set safe per-axis ranges, then enable either USB or Wi-Fi—never both.

- Download: [FallenDollTCode v0.17.0](https://github.com/Huarch/FallenDollTCode/releases/download/v0.17.0/FallenDollTCode-0.17.0.zip)
- Source and documentation: [Huarch/FallenDollTCode](https://github.com/Huarch/FallenDollTCode)
- F8Studio integration PR: [feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)
- SHA-256: `9DECA32ECED28535456A9080030245EA11EBB086D817750F627E00E8A060FA83`

Both device-output nodes are disabled by default. The package does not include game assets,
F8Studio binaries, or device drivers.

---

## 中文

这是 **Operation Lovecraft: Fallen Doll** 的非官方实时 TCode 接入项目。游戏侧通过
UE4SS Lua 读取当前 HAnime 的少量功能骨骼，F8Studio 将实时接触运动转换为 TCode。
信号跟随游戏姿态和动画速度，不是播放预制 Funscript。

游戏：[Steam 商店](https://store.steampowered.com/app/1685960/) ·
[Steam Demo](https://store.steampowered.com/app/1811180/)

### v0.17.0

- SR6 实时输出 `L0/L1/L2/R0/R1/R2` 六轴；OSR2 使用 `L0`
- 50 Hz 紧凑功能骨采集，不持续读取完整骨架
- 精确识别 HAnime，排除菜单、待机、表情和普通转场
- 动作切换、返回待机、隐藏角色以及桌面/VR 布局切换采用事件恢复
- 支持 Playtest/Closed Beta 和旧 Demo 的桌面、VR 目录结构
- F8Studio 工程分为游戏输入、运动引擎、实时预览和设备输出四个区域
- SR6 模型、3D 骨骼和六轴波形预览
- 在 F8Studio 中用滑条分别限制六轴最小/最大范围
- 支持 USB 或 Wi-Fi TCode 输出，两者只能启用一个

多轴输出已经可以正式使用，但并非每条 HAnime 都完成了人工校准。部分左右手脚、
双肢主次、特殊动作、多人和非人类姿势仍可能需要调整。首次遇到某个姿势时，请先在
Live Preview 检查，并为自己的设备设置安全的各轴范围。

### 快速使用

1. 关闭游戏，将发布包 `Game` 中的内容安装到对应版本的
   `Paralogue/Binaries/Win64`；包内已包含 UE4SS。
2. 使用包含 `Fallen Doll Source` 的 F8Studio，导入包内 v17 工程并 Deploy。
3. 确认 `studio`、`fd_pyengine`、`fd_source` 均已运行；后两个由 Studio 自动启动。
4. 进入 HAnime，打开 Live Preview 检查 SR6 模型和波形。
5. 设置各轴安全范围后，只启用 USB 或 Wi-Fi 中的一种输出。

- 下载：[FallenDollTCode v0.17.0](https://github.com/Huarch/FallenDollTCode/releases/download/v0.17.0/FallenDollTCode-0.17.0.zip)
- 源码与文档：[Huarch/FallenDollTCode](https://github.com/Huarch/FallenDollTCode)
- F8Studio 接入 PR：[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)
- SHA-256：`9DECA32ECED28535456A9080030245EA11EBB086D817750F627E00E8A060FA83`

两个设备输出节点默认关闭。发布包不包含游戏资源、F8Studio 本体或设备驱动。
