# Fallen Doll TCode Mod：运行时探针

这个目录目前只包含**只读探针**，用于确认 Fallen Doll 在运行时暴露的角色和动画对象。它不发送 TCode 指令、不访问串口、不修改 Pak，也不改动游戏状态。

## 当前结论

- 目标游戏是 UE5 打包版；本机现有解包记录标注为 UE5.5。
- UE4SS 3.0.1 的发行说明包含 UE5.5 支持，因此应先用它取得运行时的动画信息。
- 解包不是第一步。等探针输出确切资产路径后，只导出该动作对应资源，再制作动作到 TCode 曲线的映射。

## 准备内容

已下载但尚未部署的开发版 UE4SS：`zDEV-UE4SS_v3.0.1.zip`。

将压缩包内容解压到以下目录（`Paralogue-Win64-Shipping.exe` 所在位置）：

```text
D:\SteamLibrary\steamapps\common\Operation Lovecraft Fallen Doll Playtest\Paralogue\Binaries\Win64
```

然后将本项目的 `fd_tcode_probe` 文件夹复制至解压后 `Mods` 文件夹中，并在 `Mods\mods.txt` 追加：

```text
fd_tcode_probe : 1
```

这是首次运行需要的唯一游戏目录改动。恢复原状时，移走 UE4SS 文件和 `fd_tcode_probe` 的这一条配置即可；Pak 文件从不需要改。

## 测试步骤

1. 先启动游戏并进入一个实际动作场景。
2. 按 `Ctrl + Alt + F8`。
3. 在 UE4SS 控制台或 `UE4SS.log` 中寻找 `[FD-TCode-Probe]`。
4. 把从 `BEGIN` 到 `END` 的日志保存下来。

日志会列出当前内存中的 `AnimInstance`、`SkeletalMeshComponent`、`Character` 和 `Pawn`。下一阶段根据真实的类名与对象路径读取具体的 Montage/Sequence 和播放时间。

## 后续架构

```text
Fallen Doll / UE4SS 探针
    -> 动作资产路径 + 归一化播放进度
    -> 本机桥接程序
    -> 设备配置（OSR2: L0；SR6: L0/L1/L2/R0/R1/R2）
    -> 串口 TCode 固件
```

设备输出会放在独立桥接程序中；探针阶段不会触碰硬件。

## 游戏内状态浮窗（模拟模式）

`tools\Start-TCodeOverlay.ps1` 会启动一个置顶游戏覆盖层。它通过本机桥接器读取当前动画、播放位置、速度、曲线相位和 OSR2/SR6 的模拟轴状态；设备输出固定为关闭。覆盖层默认隐藏，按 `F12` 可在游戏中显示或隐藏，方便逐帧对比动画和曲线。

覆盖层包含一个抽象的 3D 六轴机构：中心滑台对应 `L0`，平台的前后/左右位移对应 `L1/L2`，三项角度对应 `R0/R1/R2`。它是运动学预览，不是设备控制界面，也不会推断或发送任何硬件指令。

先在游戏中按 `Ctrl + R` 重载 Mod，再按 `F11` 打开播放状态流，确认本机桥接器正在运行，最后在 PowerShell 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Start-TCodeOverlay.ps1
```

`F11` 再按一次会关闭状态流。浮窗可直接关闭，不会影响游戏。

## 已验证的 TCode 输出模型

现成库 [AyvaJS](https://github.com/ayvasoftware/ayvajs) 明确支持 OSR2、SR6 和 TCode 设备，可作为后续桥接器的运动与限位层。它的 SR6 基础配置使用：

- `L0`：stroke（主行程）
- `L1`：surge（前后）
- `L2`：sway（左右）
- `R0`：twist（扭转）
- `R1`：roll
- `R2`：pitch

实时 TCode 是以空格分隔、每轴四位目标值、换行结尾的命令，例如 `L05000 R05000\n`。桥接器会先以 OSR2 安全子集（仅 `L0`）实现，再在设备明确为 SR6 且各轴校准后开启额外五轴。

## Alet 动作曲线库

已从 Alet 的 102 条标准主体循环导出设备无关曲线：

- [motion-profiles.json](data/motion-profiles.json)：每条动作的时长、骨盆平移/偏航范围、64 点归一化曲线与轴能力标签；
- [build_motion_profiles.py](tools/build_motion_profiles.py)：从 UModel 导出的 PSA 重新生成曲线库；
- [animation-motion-evidence.md](docs/animation-motion-evidence.md)：动作多轴可用性的依据与限制。

曲线保留游戏局部坐标 `x/y/z/yaw`。设备桥接层会在校准阶段把这些坐标映射为实际 TCode 轴、方向、幅度与限位；在此之前它们不会被当作设备指令。

## 本机模拟桥接器

运行 `node bridge/server.mjs` 后，桥接器仅监听 `127.0.0.1:17890`：

- `GET /state`：当前动作、速度、匹配到的曲线和虚拟轴目标；
- `GET /health`：服务状态。

桥接器从 UE4SS 日志中的 `[FD-TCode-State]` 记录读取数据。它没有串口依赖，且 `deviceOutput` 固定为 `disabled`；当前所有 `L0/L1/L2/R0/R1/R2` 数值都是模拟结果。
