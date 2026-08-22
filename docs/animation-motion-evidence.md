# Alet 动画的多轴可用性验证

样本为 `AletMaleAB_VaginalMouth02_Alet_04nor`，按既有流程从 Pak4 提取、由 UModel 导出 PSA 后分析。

## 已验证事实

- 它是标准 `AnimSequence`：181 帧、约 6.0 秒、30 FPS。
- Alet 骨架有 619 根骨骼；动画中 `Master` 根骨保持固定，实际主体运动集中在 `M_Hips`（骨盆）及其子骨骼。
- `M_Hips` 在循环内的局部平移范围为：约 `5.60 / 0.62 / 0.72` Unreal 单位；最显著的是一个主方向。
- 骨盆存在约 `9.47°` 的稳定偏航变化；该样本没有可可靠直接映射的 roll / pitch 变化。
- 配对的 MaleA 正常循环也已验证为 181 帧；其骨盆位移更小（约 `0.74 / 0 / 0.49`），不适合充当主行程来源。

## 结论

游戏动画可以作为**协调多轴动作**的输入：用播放进度提供稳定时钟，再从 Alet 骨盆的主位移和偏航提取轨迹。

但游戏不会提供六个相互独立的设备控制量。对 SR6，应区分两类轴：

| 轴 | 来源 | 当前判断 |
|---|---|---|
| L0 | Alet 骨盆主位移 + 动画进度 | 可直接提取、优先使用 |
| L1 / L2 | 骨盆次要平移 | 可作为低幅度辅助，需每个姿势校准 |
| R0 | 骨盆偏航 | 可直接提取、需限制幅度 |
| R1 / R2 | 当前样本无稳定来源 | 默认保持中位；仅在人工曲线或更多动作样本证明有效后启用 |

因此第一版应支持 OSR2 的 L0，以及 SR6 的 L0/L1/L2/R0；R1/R2 先锁定在安全中位。后续再抽样不同姿势，确认哪些姿势含有足够的俯仰/滚转信号。

## 导出物

- `analysis-assets/exports/Characters/Alet/Anim/HAnim/MaleAB/VaginalMouth02/AletMaleAB_VaginalMouth02_Alet_04nor.psa`
- `analysis-assets/exports/Characters/MaleB/Anim/AletMaleAB/VaginalMouth02/AletMaleAB_VaginalMouth02_Male_A_04nor.psa`
