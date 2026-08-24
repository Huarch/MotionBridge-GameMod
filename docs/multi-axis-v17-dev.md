# v17 多骨骼六轴实验分支

状态：`0.17.0-dev`，需要在游戏画面中校准，不替代已验证的 `0.16.6` L0 发布版。

## 实现

- 游戏侧仍以 20 Hz 读取紧凑功能骨，不读取完整骨架。
- 常规接触帧只读取 Reference 的 `Penis01`、`Penis02`、`Penis09`、`M_Hips`，以及当前 Target，典型共 5 根骨骼。
- `Penis01 -> Penis02` 确定实时主轴方向；`Penis01 -> Penis09` 提供约 19.6 cm 的完整有限圆柱长度；`M_Hips` 的校准本地轴构成稳定参考面。
- F8Studio 的 `f8.contact_pose_axes` 使用有限线段最近点、局部投影和有符号角生成归一化 `L0/L1/L2/R0/R1/R2`，不使用 Montage position 或欧拉角差直接驱动。
- 纯几何与四元数运算位于独立模块；同一非空 F8 `ctx_id` 的 6 个轴和状态只解析、计算一次，配置变化时立即清除缓存。
- 六轴统一经过 250 ms 保持和 600 ms smoothstep 回中，然后同时接入 OSR Viewer TCode 与设备 TCode。
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

Reference 映射来自解包骨架；Alet 右手映射由 Hand01 运行日志校准。旧映射会让
Pitch 在 `+180°/-180°` 边界翻转并使 R2 全程饱和。不同 Target（左手、脚、口部、
阴道、肛门）仍需在游戏内确认各自本地轴映射后，才能作为正式设备输出配置。

Fallen Doll Source 会把已验证的右手 `basis` 随 `targetBone` 一起发送；通用接触算子
优先使用该逐目标覆盖，没有覆盖的功能骨继续使用工程默认基准。因此修正 Hand 的
Pitch 不会把同一映射错误地套到 `M_Gen` 等其他目标。

两张 10 秒 Wave 图使用 2000 点缓冲区。两个 Wave 节点从同一个 `axesFrame` 中分别
选择 L0/L1/L2 和 R0/R1/R2，因此只需一次跨服务发布；缓冲区只影响历史显示范围，
不改变设备输出值。

## 验证顺序

1. 在 F8Studio 导入 v17 工程并 Deploy，只打开 3D Viewer、波形与 OSR Viewer。
   也可运行 `powershell -ExecutionPolicy Bypass -File tools/Start-F8Studio.ps1 -ProjectVersion v17`，它会导入或选择独立的 v17 工程；默认不带参数仍打开稳定的 v16 工程。
2. 保持 USB/Wi-Fi 为 Disabled，先验证 Hand02 的六轴方向、幅度和动画速度同步。
3. 验证动作切换、回 Idle、ESC、隐藏角色、VR 第一人称切换及断流时没有突然下砸。
4. 完成画面对照后，再单独启用 USB 或 Wi-Fi 输出。

## 已完成的自动验证

- v17 工程可由生成器精确重建，包含 14 个节点、16 条连接和 0 个图诊断问题。
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
