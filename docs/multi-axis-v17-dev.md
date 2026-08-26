# v17 多骨骼六轴实验分支

状态：`0.17.0` 正式多轴版本。SR6 使用六轴，OSR2 使用 L0；仍需按姿势和设备校准范围。

## 实现

- 游戏侧以 50 Hz（20 ms）读取紧凑功能骨，不读取完整骨架；HAnime 身份发现仍保持 250 ms。
- 常规接触帧只读取 Reference 的 `Penis01`、`Penis02`、`Penis09`、`M_Hips`，以及当前 Target，典型共 5 根骨骼。
- `Penis01 -> Penis02` 确定实时主轴方向；`Penis01 -> Penis09` 提供约 19.6 cm 的完整有限圆柱长度；`M_Hips` 的校准本地轴构成稳定参考面。
- F8Studio 的 `f8.contact_pose_axes` 使用有限线段最近点、局部投影和有符号角生成归一化 `L0/L1/L2/R0/R1/R2`，不使用 Montage position 或欧拉角差直接驱动。
- 纯几何与四元数运算位于独立模块；同一非空 F8 `ctx_id` 的 6 个轴和状态只解析、计算一次，配置变化时立即清除缓存。
- 原始六轴先经过 250 ms 保持和 600 ms smoothstep 回中；随后在 Studio 侧应用每轴 Motion
  Gain、Center、Dead Zone 与 Curve，最后才应用设备 Output Range 并编码为 TCode。
- `FD Live Preview (Off = Production)` 默认关闭。关闭时 3D、SR6 Viewer 和两组波形不再接收、缓存或绘制数据，但 50 Hz 骨骼计算与设备输出保持运行；需要诊断时打开总开关，并可分别控制模型、曲线和骨骼预览。
- `axesFrame` 始终保留原始、经断流保护的骨骼几何轴；`deviceFrame` 是经 Motion Tuning 和
  Output Range 后的最终设备轴。OSR Viewer、真实设备和 Wave 曲线共用 `deviceFrame`，因此
  调整会立即反映在模拟姿态和波形上。真实设备分支为六轴分别提供 Output Range，把调节后的
  `0..1` 连续映射到用户选择的设备区间。默认保持 L0/L1/L2/R0/R1 全幅，仅将尚在校准的
  Pitch/R2 设为 `0.35..0.65`（`R23500..R26500`）。
- Contact、Safety、TCode 和 Wave 之间使用单个原子 `axesFrame` 传递六轴；Safety 只由
  20 ms 时钟执行一次，不再为六个标量分别 pull、emit 和跨服务发布。
- v17 工程中的 USB/Wi-Fi 输出仍默认关闭，且只能启用一种。

## 文件

- F8Studio 工程：`f8studio/fallen-doll-skeleton-preview-v17.json`
- 工程生成器：`tools/build_f8studio_v17.py`
- 六轴算子：F8Studio 分支中的 `packages/f8pyengine/f8pyengine/operators/contact_pose_axes.py`
- 纯几何模块：F8Studio 分支中的 `packages/f8pyengine/f8pyengine/operators/contact_geometry.py`
- F8Studio v17 补丁按以下顺序应用：
  1. `f8studio/0001-feat-pyengine-add-multi-bone-contact-axes.patch`
  2. `f8studio/0002-fix-sdk-use-generated-state-field-alias.patch`
  3. `f8studio/0003-feat-tcode-expose-all-SR6-graph-inputs.patch`
  4. `f8studio/0004-fix-sdk-support-generated-wire-field-aliases.patch`
  5. `f8studio/0005-refactor-pyengine-isolate-and-cache-contact-geometry.patch`
  6. `f8studio/0006-fix-fallen-doll-apply-target-specific-hand-basis.patch`
  7. `f8studio/0007-perf-sr6-route-axes-as-atomic-frames.patch`
- UDP 设备链路回环工具：`tools/verify_f8studio_v17_udp.py`
- 静态骨架依据：`data/skeleton-catalog-v1.json`
- Hand01/02/03 几何规则：`data/runtime-profiles-v2.json`

## 当前默认校准

- Reference right：`M_Hips -local_x`
- Reference up：`M_Hips +local_y`
- Alet 右手 Target up：`R_Hand +local_z`
- Alet 右手 Target right：`R_Hand -local_y`
- L0 输入：`0.08..0.27 m`
- L1/L2 对称范围：`±0.15 m`
- R0：`±90°`
- R1/R2：`±30°`

这里的 `±30°` 是几何角度到归一化姿态的映射范围，不是设备安全行程。六轴设备输出
范围属于 F8Studio 用户配置；两者不能共用一套参数。

Reference 映射来自解包骨架；Alet 右手映射由 Hand01 运行日志校准。旧映射会让
Pitch 在 `+180°/-180°` 边界翻转并使 R2 全程饱和。不同 Target（左手、脚、口部、
阴道、肛门）仍需在游戏内确认各自本地轴映射后，才能作为正式设备输出配置。

Fallen Doll Source 会把已验证的右手 `basis` 随 `targetBone` 一起发送；通用接触算子
优先使用该逐目标覆盖，没有覆盖的功能骨继续使用工程默认基准。因此修正 Hand 的
Pitch 不会把同一映射错误地套到 `M_Gen` 等其他目标。

## Motion Tuning

`FD Motion Tuning & Stream Safety` 是日常调整节点。常用的 `L0/L1/L2/R0/R1/R2 Motion
Gain` 与 `Output Range` 直接显示在节点上；Center、Dead Zone、Curve 位于同一节点的详细
属性中。

- `Motion Gain`：围绕 Motion Center 放大或缩小运动。默认 `1.0×` 不改变原始输出；短行程
  动作应先从 L0 `1.25×` 开始试。
- `Motion Center`：增益与曲线的中立位置，默认 `0.5`。
- `Motion Dead Zone`：忽略中心附近的细小骨骼抖动，默认 `0`。
- `Motion Curve`：`LINEAR`、`SMOOTHSTEP`、`SMOOTHERSTEP` 三种运动塑形，默认 `LINEAR`。
- `Output Range`：真实设备的物理安全边界，不负责放大短行程。

工程图按五个背景区块整理：Game Input、Contact Mapping、Motion Tuning、Live Preview、
Device Output。两张 10 秒 Wave 图使用 500 点缓冲区，并显示最终 `deviceFrame` 的 L0/L1/L2
与 R0/R1/R2；缓冲区和显示刷新率只影响诊断画面，不改变 50 Hz 设备输出值。3D 骨骼预览
限制为 30 FPS，SR6 Viewer 的 UI 推送限制为 20 FPS。

## 验证顺序

1. 在 F8Studio 导入 v17 工程并 Deploy；需要画面对照时，在
   `FD Live Preview (Off = Production)` 节点打开 `Live Preview`，再打开所需的 3D、
   波形或 OSR Viewer。正式使用时保持该开关关闭。
   也可运行 `powershell -ExecutionPolicy Bypass -File tools/Start-F8Studio.ps1`，它会导入或选择正式的 v17 多轴工程；只有兼容旧工程时才显式传入 `-ProjectVersion v16`。
2. 保持 USB/Wi-Fi 为 Disabled，先验证 Hand02 的六轴方向、幅度和动画速度同步。
3. 验证动作切换、回 Idle、ESC、隐藏角色、VR 第一人称切换及断流时没有突然下砸。
4. 完成画面对照后，再单独启用 USB 或 Wi-Fi 输出。

## 已完成的自动验证

- v17 工程可由生成器精确重建，包含 25 个节点和 20 条连接，并按游戏输入、接触几何、
  运动调节、实时预览和设备输出五个背景区块整理。Preview Gate 默认关闭，且不位于设备
  输出路径上。
- 原子 Contact frame、TCode 编码与 Wave 展开相关的 27 项定向测试通过；同一帧 6 轴
  只计算一次、状态变化清缓存、TCode 不回退到六次标量 pull 均有回归测试。全仓库
  `basedpyright` 为 0 errors / 0 warnings。
- 游戏关闭的同条件实测中，PyEngine `bufferPullDeliveries` 从约 1645/s 降至 182/s，
  跨服务 emit 从约 728/s 降至 148/s，processed 从约 1517/s 降至 895/s；优化后
  10 秒窗口 CPU 平均约 0.8%，无错误或丢帧。
- SDK 状态协议在当前 `field_` 生成模型下通过 41 项测试；另以干净检出中原始
  `field` 生成模型运行 40 项相关测试，确认两种代码生成结果都按线协议字段
  `field` 正常工作，且无需提交本机生成文件。
- 使用 `tools/verify_f8studio_v17_udp.py` 向临时 spool 写入一组确定几何，并将
  Wi-Fi 节点临时指向本机 UDP 端口，真实 F8Studio v17 图捕获到：

  ```text
  L03684I020 L15999I020 L25666I020 R05000I020 R15000I020 R25000I020
  ```

  验证后已恢复 `runtimeDir=""`、`enabled=false` 与 `tcode.local:8000`。该测试
  只使用 `127.0.0.1`，不会连接真实设备。
