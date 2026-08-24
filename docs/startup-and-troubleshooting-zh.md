# F8Studio 启动与排错

## 正确启动顺序

1. 启动 F8Studio。
2. 导入 Fallen Doll 工程并点击 Deploy。
3. 在服务监视器确认三个服务：
   - `studio`：主界面自身；
   - `fd_pyengine`：多轴运动、安全和 TCode 图；
   - `fd_source`：读取游戏骨骼文件。
4. 只启用 USB 或 Wi-Fi 中的一种输出。
5. 启动游戏并进入 HAnime。

`fd_pyengine` 和 `fd_source` 应由 Deploy 自动启动，不是三个需要分别运行的程序。

## Pixi 启动问题

源码版 F8Studio 使用 Pixi 管理运行环境。全局命令找不到 Pixi，并不代表已经安装的
Studio 环境损坏。避免混用系统 Python、全局 Pixi 和仓库 `.pixi` 环境：

- Studio 主程序使用仓库 `.pixi/envs/default/python.exe`；
- Fallen Doll Source 使用 `.pixi/envs/studio-runtime/python.exe`；
- 从源码启动时可使用本仓库 `tools/Start-F8Studio.ps1 -F8StudioRoot "路径"`，它会
  优先寻找 F8Studio 仓库和本工程已有的 Pixi，不依赖全局 PATH。

若首次安装/更新环境很慢，可先确保网络可访问依赖源；不要在 Studio 已运行时重复
启动另一套 Pixi 环境。

## 三个服务不全

- 只有 `studio`：先确认已经导入工程并 Deploy，而不是只打开 JSON。
- `fd_pyengine` 启动失败：通常是服务启动命令解析到了错误环境，或旧进程没有退出。
  先 Stop All，关闭 Studio，确认相关 F8Studio Python/Pixi 子进程退出，再重新启动和
  Deploy。
- `fd_source` 启动失败：当前 F8Studio 构建必须包含 Fallen Doll Source；官方版本在
  上游 PR 合并前需要使用项目提供的补丁/分支。
- 服务显示运行但无数据：`fd_source` 只有在游戏识别到 HAnime 并收到新骨骼帧时才
  显示连接。主菜单、待机和普通动画无信号是正常的。
- 热部署后状态异常：Stop All 后重新 Deploy。旧的服务实例可能短暂保留状态，CLI
  状态设置失败不等同于游戏 Mod 故障。

## 分段排查

1. 游戏侧：确认 UE4SS Mod 已加载；需要时用 F6 看低频诊断、F10 热重载。
2. Source：确认 `fd_source` Running/Active，进入 HAnime 后 `Game Stream` 变为 true。
3. 图与设备：先看 3D/OSR Viewer，再检查 TCode；最后才启用实体设备。

Studio 重部署或游戏切换动作时可能短暂断流。安全节点会保持最后值 250 ms，再在
600 ms 内平滑回中。若输出直接下砸，应检查是否导入了当前工程，而不是旧版图。

## 设备与关闭

- Wi-Fi：`tcode.local:8000`；设备与电脑需在可达的同一网络。
- USB：选择实际串口，115200 波特率。
- USB 和 Wi-Fi 不能同时启用。
- 测试完成后先关闭设备输出，再停止工程和关闭游戏。
