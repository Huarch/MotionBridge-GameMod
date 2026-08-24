# v17 多骨骼六轴实验分支

状态：`0.17.0-dev`，需要在游戏画面中校准，不替代已验证的 `0.16.6` L0 发布版。

## 实现

- 游戏侧仍以 20 Hz 读取紧凑功能骨，不读取完整骨架。
- 常规接触帧只读取 Reference 的 `Penis01`、`Penis02`、`Penis09`、`M_Hips`，以及当前 Target，典型共 5 根骨骼。
- `Penis01 -> Penis02` 确定实时主轴方向；`Penis01 -> Penis09` 提供约 19.6 cm 的完整有限圆柱长度；`M_Hips` 的校准本地轴构成稳定参考面。
- F8Studio 的 `f8.contact_pose_axes` 使用有限线段最近点、局部投影和有符号角生成归一化 `L0/L1/L2/R0/R1/R2`，不使用 Montage position 或欧拉角差直接驱动。
- 六轴统一经过 250 ms 保持和 600 ms smoothstep 回中，然后同时接入 OSR Viewer TCode 与设备 TCode。
- v17 工程中的 USB/Wi-Fi 输出仍默认关闭，且只能启用一种。

## 文件

- F8Studio 工程：`f8studio/fallen-doll-skeleton-preview-v17.json`
- 工程生成器：`tools/build_f8studio_v17.py`
- 六轴算子：F8Studio 分支中的 `packages/f8pyengine/f8pyengine/operators/contact_pose_axes.py`
- F8Studio v17 补丁按以下顺序应用：
  1. `f8studio/0001-feat-pyengine-add-multi-bone-contact-axes.patch`
  2. `f8studio/0002-fix-sdk-use-generated-state-field-alias.patch`
  3. `f8studio/0003-feat-tcode-expose-all-SR6-graph-inputs.patch`
- UDP 设备链路回环工具：`tools/verify_f8studio_v17_udp.py`
- 静态骨架依据：`data/skeleton-catalog-v1.json`
- Hand01/02/03 几何规则：`data/runtime-profiles-v2.json`

## 当前默认校准

- Reference right：`M_Hips -local_x`
- Reference up：`M_Hips +local_y`
- Alet 右手 Target up：`R_Hand -local_y`
- Alet 右手 Target right：`R_Hand +local_z`
- L0 输入：`0.08..0.27 m`
- L1/L2 对称范围：`±0.15 m`
- R0：`±90°`
- R1/R2：`±30°`

这些映射来自解包骨架的静态参考姿态。不同 Target（左手、脚、口部、阴道、肛门）需要在游戏内确认各自本地轴映射后，才能作为正式设备输出配置。

## 验证顺序

1. 在 F8Studio 导入 v17 工程并 Deploy，只打开 3D Viewer、波形与 OSR Viewer。
   也可运行 `powershell -ExecutionPolicy Bypass -File tools/Start-F8Studio.ps1 -ProjectVersion v17`，它会导入或选择独立的 v17 工程；默认不带参数仍打开稳定的 v16 工程。
2. 保持 USB/Wi-Fi 为 Disabled，先验证 Hand02 的六轴方向、幅度和动画速度同步。
3. 验证动作切换、回 Idle、ESC、隐藏角色、VR 第一人称切换及断流时没有突然下砸。
4. 完成画面对照后，再单独启用 USB 或 Wi-Fi 输出。

## 已完成的自动验证

- v17 工程可由生成器精确重建，包含 14 个节点、36 条连接和 0 个图诊断问题。
- 多骨骼算子、Source/stream 与 TCode 端口的 23 项定向测试通过；全仓库
  `basedpyright` 为 0 errors / 0 warnings。
- 使用 `tools/verify_f8studio_v17_udp.py` 向临时 spool 写入一组确定几何，并将
  Wi-Fi 节点临时指向本机 UDP 端口，真实 F8Studio v17 图捕获到：

  ```text
  L03684I020 L15999I020 L25666I020 R05000I020 R15000I020 R25000I020
  ```

  验证后已恢复 `runtimeDir=""`、`enabled=false` 与 `tcode.local:8000`。该测试
  只使用 `127.0.0.1`，不会连接真实设备。
