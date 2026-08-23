# Fallen Doll → F8Studio skeleton stream

这是 Fallen Doll 的 Lua 实时骨骼采集与 F8Studio 接入工程。当前只做模拟和
可视化，不发送 TCode 到串口、蓝牙或真实设备。

## 当前链路

```text
Fallen Doll / UE4SS Lua
  → 精确 HAnime Montage 白名单
  → 当前 HAnime 参与者骨骼（20 Hz）
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
- `F9`：开始/停止 20 Hz 骨骼流。
- `F10`：通过独立 broker 热重载 Lua Mod。若 F9 正在运行，先停止 F9。

Lua 不创建游戏内 UI。F8Studio 的 Viewer 是独立桌面窗口。

## F8Studio 接收

F8Studio 内已保存的正式工程为：

- 名称：`Fallen Doll Skeleton Preview`
- Project ID：`fc812463-e55a-42c2-9c5f-4f0bd9aeb422`
- 当前版本：10（第 9 版保留为回退点）
- 完整导出：`f8studio/fallen-doll-skeleton-preview-v10.json`

基础图在 `f8studio/fallen-doll-skeleton-preview.patch.json`，包含：

```text
UDP In :39540 → Skeleton Decoder → 3D Viz
```

第 10 版另外包含：

```text
安全 L0 → TCode Encoder → SR6 OSR Viewer
```

增量补丁位于 `f8studio/fallen-doll-osr-preview.patch.json`。OSR Viewer 是
TCode Viz 节点自己的 `Open Viewer` 独立窗口，不是骨骼 3D Viewer。当前没有
Serial Out；游戏未发送有效的双角色骨骼时，预览保持安全中位 `L05000`。

为了让 CLI 可以直接打开骨骼或 OSR Viewer，本地 F8Studio 源码补丁保存在
`f8studio/f8studio-detached-viewer-cli.patch`；从 `.deps/f8studio` 执行
`git apply ../../f8studio/f8studio-detached-viewer-cli.patch` 即可恢复。

## 安全边界

- 不修改或重新打包 Pak。
- 待机、表情和过渡 Montage 不发送骨骼包。
- F8Studio 断开不影响游戏，且不启用设备输出。
- 验证结束后关闭游戏和 F8Studio。
