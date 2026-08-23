# Fallen Doll → F8Studio skeleton stream

这是 Fallen Doll 的 Lua 实时骨骼采集与 F8Studio 接入工程。当前只做模拟和
可视化，不发送 TCode 到串口、蓝牙或真实设备。

## 当前链路

```text
Fallen Doll / UE4SS Lua
  → 精确 HAnime Montage 白名单
  → 当前 HAnime 功能接触骨集合（目标 20 Hz）
  → runtime/fd-skeleton.ndjson
  → localhost UDP relay :39540
  → F8Studio Skeleton Decoder / 3D Viz
  → 相对骨骼 L0 → TCode → SR6 OSR Viewer
```

- HAnime 身份识别和 Fallen Doll 特有规则只存在于游戏侧 Lua。
- 解包数据是运行实验前的权威材料；参见
  [docs/unpacked-data-first.md](docs/unpacked-data-first.md)。
- F8Studio 只负责通用骨骼解码、可视化和后续六轴转换。
- C++ DLL、游戏内 Canvas UI、旧 localhost bridge 和 WinForms 浮层均已移除。
- 真实设备输出始终保持禁用。

## 工程目录

- `fd_tcode_probe/`：游戏侧 Lua Mod。
- `fd_tcode_reloader/`：安全热重载 broker。
- `data/`：由解包数据生成的 HAnime、姿势和骨架索引。
- `tools/`：索引生成、骨架提取和 F8 UDP relay/replay 工具。
- `f8studio/`：本工程维护的 F8Studio 图补丁。
- `docs/`：静态数据约束与仍在使用的设计资料。
- `runtime/`：本机验证输出、日志和截图，不作为源码提交。

第三方 F8Studio 源码位于忽略版本管理的 `.deps/f8studio/`。

## 快捷键

- `F6`：开始/停止 HScene 状态监视。
- `F8`：一次性导出当前可见姿势列表。
- 功能接触骨流随 Mod 自动待命，不再需要 F9。只有精确识别到 HAnime 时才读取并
  发送功能骨；退出动作或进入待机后停止骨骼输出，再次进入时自动恢复。
- `F10`：通过独立 broker 热重载 Lua Mod。

Lua 不创建游戏内 UI。F8Studio 的 Viewer 是独立桌面窗口。

模块化角色的身体、头发、衣物、手脚等组件可能共享同一个 SkinnedAsset。
运行时只采集角色主组件，并按解包 HAnime family 中的已知角色数量限制输出；
不会把所有共享骨架的模块当成独立参与者。F8 通用身份使用
`fallen-doll:male:N` / `fallen-doll:female:N`，角色目录仍通过 trailer 中的
`characterRole` 和 `catalogId` 保留。

实时设备预览不再逐帧导出整套调试骨架。每个参与者只发送当前交互类别所需的
紧凑功能骨候选，例如左右手、左右脚、口、Vaginal、Anal 或进入物起止点。
不同类别的无关骨不会同时采样。F8Studio
按动画标注的优先级从用户仍启用的候选骨中选择；例如 Hand02 默认右手优先，
取消勾选右手后自动回退左手。
HAnime 身份低频刷新，接触骨骼独立实时采样；Relay 只转发最新帧并丢弃积压，
从而避免游戏线程长卡顿和调速后的旧帧回放。

自动实时路径只在 Mod 加载、缓存对象明确失效，或已识别 HAnime 退出后再次
连续看到 `Exp_In / Exp_Sexing` 动作表情时执行一次骨架发现；`Exp_Idle` 待机
期间保持休眠且不消耗恢复机会。不再周期性全局枚举骨架，也不读取会触发多次
全局搜索的 HScene 诊断快照。这样退出动作再重新进入时可以自动恢复。
F6/F8 仍保留低频诊断能力。

当前正式基础映射为 Vaginal/Pussy、Anal 和 Mouth；Alet/Male Hand02 的
`R_Hand` 主、`L_Hand` 次已作为第一条优先级标注。其余 Hand/Foot 尚未标注
左右侧、双肢参与及主次关系，因此不会自动选择一个未验证骨骼；可在 F8Studio
手工切到 Exact 模式验证。`special` 动作也暂不做自动骨骼切换。

## F8Studio 接收

F8Studio 内已保存的正式工程为：

- 名称：`Fallen Doll Skeleton Preview`
- Project ID：`fc812463-e55a-42c2-9c5f-4f0bd9aeb422`
- 当前版本：13（第 11 版保留为无设备出口的回退点）
- 完整导出：`f8studio/fallen-doll-skeleton-preview-v13.json`

基础图在 `f8studio/fallen-doll-skeleton-preview.patch.json`，包含：

```text
UDP In :39540 → Skeleton Decoder → 3D Viz
```

第 10 版加入：

```text
安全 L0 → TCode Encoder → SR6 OSR Viewer
```

第 11 版重建了两个人物选择器和两个功能骨选择器，加入解包参与者优先级、
参与者复选、功能骨复选，以及禁用主候选后自动回退次候选。

第 13 版在安全链末端加入独立的 TCode ESP32 Wi-Fi 设备支路：

```text
FD L0 Stream Safety → 平滑/限速 → Device Range 40–60%
                                      → Device TCode
                                      → UDP Out (tcode.local:8000)
```

节点 `fd_wifi_out` 默认且已验证为 `Enabled=false`。它只由安全节点的执行出口
触发，不允许绕过 250 ms 断流回中逻辑。实体设备使用独立的 40–60% 行程映射，
不会改变 Viewer 的全范围模拟；TCode 编码器已经包含换行，因此 UDP 节点不重复
追加换行。完整可恢复补丁位于
`f8studio/fallen-doll-wifi-output.patch.json`；已应用早期 Wi-Fi 节点的工程可使用
`f8studio/fallen-doll-wifi-safe-range-migration.patch.json` 迁移。设备 IP、端口等
属于本机设置，共享工程始终保持物理输出关闭。

已在 SR6 / TCode ESP32 0.5b / TCode v0.3 上完成实体 Wi-Fi 短测：
`tcode.local:8000` 可直接接收 F8Studio 的 UDP TCode，40%–60% 限幅往返正常，
测试结束后恢复 `Enabled=false`。因此 USB 串口仅保留为网络不可用时的回退方案。
`tools/f8-skeleton-replay.mjs` 默认把录制包时间戳刷新为当前时间，确保回放能通过
250 ms 新鲜度保护；需要专门复现过期包时可加 `--preserve-timestamps`。

增量补丁位于 `f8studio/fallen-doll-osr-preview.patch.json`。OSR Viewer 是
TCode Viz 节点自己的 `Open Viewer` 独立窗口，不是骨骼 3D Viewer。当前没有
Serial Out；Wi-Fi UDP 出口也默认关闭。游戏未发送有效的双角色骨骼时，预览
保持安全中位 `L05000`。

为了让 CLI 可以直接打开骨骼或 OSR Viewer，本地 F8Studio 源码补丁保存在
`f8studio/f8studio-detached-viewer-cli.patch`；从 `.deps/f8studio` 执行
`git apply ../../f8studio/f8studio-detached-viewer-cli.patch` 即可恢复。

环境清理后不要求重新安装全局 Pixi。`f8studio/f8studio-direct-engine-runtime.patch`
将 PyEngine 服务改为直接使用仓库现有的 `.pixi/envs/default/python.exe`；从
`.deps/f8studio` 执行 `git apply ../../f8studio/f8studio-direct-engine-runtime.patch`
即可恢复该运行方式。它只影响游戏骨骼图所需的 PyEngine，不恢复视频、音频、
AI 或 C++/Rust 开发环境。

多人/多功能骨选择使用通用 F8Studio 设置扩展：

- `Skeleton Selector / Enabled Participants`：复选 Male 1、Male 2、Female 1 等
  当前参与者；默认按解包 TableHAnim 的 A/B/C 槽位优先级选择，取消当前人物后
  回退下一位，全部取消则无输出。两个选择器共同定义交互对，不限制为男+女。
- `Bone Selector / Enabled Detection Bones`：复选当前人物的功能骨。
- `Selection Mode = Exporter Priority`：按游戏侧标注顺序选择第一个仍启用的骨；
  取消主骨后自动回退次骨。
- 未标注动作保持无输出；需要临时验证时可切换 `Exact` 并直接选择具体骨名。

源码扩展保存在 `f8studio/f8studio-functional-contact-selection.patch`，图设置补丁
保存在 `f8studio/fallen-doll-contact-selection.patch.json`。二者均为通用骨骼
选择能力，不在 F8Studio 内保存 Fallen Doll 的动画匹配规则。

## 安全边界

- 不修改或重新打包 Pak。
- 待机、表情和过渡 Montage 不发送骨骼包。
- F8Studio 断开不影响游戏，且不启用设备输出。
- 验证结束后关闭游戏和 F8Studio。
