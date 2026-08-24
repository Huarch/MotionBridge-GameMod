# Operation Lovecraft: Fallen Doll TCode Mod

版本：`0.16.5-event-driven-switch`

游戏页面：[Operation Lovecraft: Fallen Doll（Steam）](https://store.steampowered.com/app/1685960/) ·
[Steam Demo](https://store.steampowered.com/app/1811180/)

这个非官方 Mod 使用 UE4SS Lua 读取实时 HAnime 骨骼，并通过 F8Studio 生成 L0、
显示 3D/OSR Viewer，或向 OSR2/SR6 输出 TCode。待机、普通转场和未识别动作不会
作为有效输出；断流会先保持 250 ms，再用 600 ms 平滑回到 `L05000`。

## 安装

1. 关闭游戏，将包内 `Game` 的全部内容复制到对应目录：
   - Playtest：`Paralogue/Binaries/Win64`
   - Demo 桌面：`Desktop/WindowsNoEditor/Paralogue/Binaries/Win64`
   - Demo VR：`VR/WindowsNoEditor/Paralogue/Binaries/Win64`
   也可运行 `Install-Mod.ps1 -GameRoot "游戏根目录"`。发布包已包含 UE4SS。
2. 使用包含 `Fallen Doll Source` 的 F8Studio，导入
   `F8Studio/fallen-doll-skeleton-preview-v16.json`，然后 Deploy。
3. 确认 `studio`、`fd_pyengine`、`fd_source` 都已运行。后两个服务应由 Studio
   自动启动，不需要分别手动运行。
4. 启动游戏并进入 HAnime，先通过 3D Skeleton Viewer 或 SR6/OSR Viewer 验证。
5. 确认方向和范围后，只启用 USB 或 Wi-Fi 中的一种输出，不能同时启用。

Wi-Fi 默认使用 `tcode.local:8000`。USB 需要选择正确串口并使用 115200 波特率。
两个设备节点默认关闭，USB 端口默认留空。

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

动作侦测默认自动待命。Viewer 在 F8Studio 中打开，不是游戏内浮层。

## 当前状态

- 支持 Playtest、Demo 桌面与 Demo VR；Playtest 桌面/VR 已完成主要运行验证。
- Playtest 身份目录包含 508 个 HAnime family、3081 条精确 Montage。
- Demo 身份目录包含 217 个 family、1160 条精确 Montage。
- 当前真实设备正式输出仅为 L0。
- 部分左右手脚、双肢主次、特殊动作、多人和非人类动作仍需继续标注。
- 其他五轴属于后续目标。

启动失败或服务不全时请阅读 `startup-and-troubleshooting-zh.md`。

F8Studio Source PR：
[feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)

本项目不包含游戏资源、F8Studio 本体或设备驱动。
