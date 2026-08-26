# Motion Bridge

这是面向多款游戏的独立 Windows 运动桥接程序，将实时游戏动作转换为 OSR2/SR6 等多轴设备输出。Fallen Doll 是首个内置适配器；正常使用时不需要启动 F8Studio。

## 当前能力

- 独立、低延时的 C++20 运动与安全引擎；界面不阻塞实时输出。
- Fallen Doll Playtest、Demo、0.49 共用的 `fd-skeleton.ndjson` 输入。
- L0/L1/L2/R0/R1/R2、双手/双脚参考、增益、中心、死区、曲线、范围、反向与失联回中逻辑。
- USB 串口、Wi-Fi UDP（默认 `tcode.local:8000`）与 Intiface Desktop；初始状态始终未解锁输出。
- 外部桌面 SR6/OSR 圆柱预览，VR 游戏运行时同样可在桌面查看。
- `adapters/motion-frame-v1.schema.json` 是未来游戏的公开输入协议。外部适配器只需向所选 NDJSON 文件逐行写入完整帧，不加载第三方 DLL。

## 使用

1. 保持现有 Fallen Doll UE4SS Mod 已安装并启用骨骼流。
2. 启动 Motion Bridge，确认“Fallen Doll 数据流已连接”。
3. 在输出区选择 USB、Wi-Fi 或 Intiface，并确认端点/端口。
4. 先观察预览与波形，再手动点击 **ARM OUTPUT**。停止或断流会先保持 250 ms，再在 600 ms 内回中；重新启动始终未解锁。

F8Studio 仍可作为工程编辑和调试工具，与 Motion Bridge 并行，不会被修改。

## 构建便携版

```powershell
.\tools\Install-CompanionToolchain.ps1
.\tools\Build-Companion.ps1 -Portable
```

便携目录和 ZIP 会生成在 `dist/`。安装包脚本将在发布阶段以同一个已部署的便携目录生成；当前不把未测试的设备输出作为发行前置条件。
