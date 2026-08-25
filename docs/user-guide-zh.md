# Operation Lovecraft: Fallen Doll TCode Mod

版本：`0.17.0`

游戏页面：[Operation Lovecraft: Fallen Doll（Steam）](https://store.steampowered.com/app/1685960/) ·
[Steam Demo](https://store.steampowered.com/app/1811180/)

这个非官方 Mod 使用 UE4SS Lua 实时读取当前 HAnime 的功能骨骼，并由 F8Studio
生成多轴运动：SR6 使用 `L0/L1/L2/R0/R1/R2`，OSR2 使用同一运动流中的 `L0`。
信号跟随游戏当前姿态与动画速度，不是播放预制 Funscript。

## 安装

1. 关闭游戏，将包内 `Game` 的全部内容复制到对应目录：
   - Playtest：`Paralogue/Binaries/Win64`
   - 旧版 0.49：`Paralogue/Binaries/Win64`（通过 `KiritoMod049.exe` 识别；安装后仍使用该版本原有的 `Launch.bat` 启动）
   - Demo 桌面：`Desktop/WindowsNoEditor/Paralogue/Binaries/Win64`
   - Demo VR：`VR/WindowsNoEditor/Paralogue/Binaries/Win64`
   也可运行 `Install-Mod.ps1 -GameRoot "游戏根目录"`。发布包已包含 UE4SS。
2. 使用包含 [feel8-fun/f8studio#3](https://github.com/feel8-fun/f8studio/pull/3)
   改动的 F8Studio，导入 `F8Studio/fallen-doll-skeleton-preview-v17.json`，然后 Deploy。
3. 确认 `studio`、`fd_pyengine`、`fd_source` 都已运行。后两个服务应由 Studio
   自动启动，不需要分别手动运行。
4. 进入 HAnime，打开 `Live Preview`，先检查 SR6 模型和六轴波形。
5. 在 Safety 分区中用各轴的最小/最大滑条设置设备范围，再只启用 USB 或 Wi-Fi
   中的一种输出，不能同时启用。

Wi-Fi 默认使用 `tcode.local:8000`。USB 需要选择正确串口并使用 115200 波特率。
两个设备输出节点默认关闭，USB 端口默认留空。

待机、普通转场和未识别动作不会作为有效输出；断流会先保持最后值 250 ms，再用
600 ms 平滑回中。

## 快捷键

- `F6`：开关低频诊断
- `F8`：一次性导出当前姿势列表
- `F10`：安全热重载 Lua Mod

动作侦测默认自动待命。Viewer 是 F8Studio 窗口，不是游戏内浮层。

## 当前状态

- 支持 Playtest、旧版 0.49、Demo 桌面与 Demo VR 的目录结构。
- Playtest 身份目录包含 508 个 HAnime family、3081 条精确 Montage。
- Demo 身份目录包含 217 个 family、1160 条精确 Montage。
- SR6 已支持 50 Hz 实时六轴输出，OSR2 使用 L0。
- 部分左右手脚、双肢主次、特殊动作、多人和非人类动作仍需逐项校准。“支持多轴”
  不代表全部 HAnime 都已经人工验证。

启动失败或服务不全时请阅读 `Startup-and-Troubleshooting-ZH.md`。
本项目不包含游戏资源、F8Studio 本体或设备驱动。
