# Alet 动画离线证据与运行时边界

`AletMaleAB_VaginalMouth02_Alet_04nor` 的 PSA 导出证明骨盆主位移和偏航存在，但不能单独决定现实接触关系或 SR6 各轴。

旧方案曾以动画进度为时钟、以 Alet 骨盆曲线生成 L0/L1/L2/R0。这些数据保留在 `motion-profiles.json`，仅用于回归比较，不再是实时输出来源。

正式运行时的证据链为：

1. UE4SS C++ 在游戏线程读取已验证的骨骼变换；
2. profile v2 选择 Reference 起点/终点与 Target；
3. `FDTCodeCore` 计算轴向深度、局部偏移和相对朝向；
4. profile 再应用每轴方向与范围；
5. 桥接器仅显示 UDP v1 模拟结果。

因此“某个 PSA 存在骨盆移动”不能自动启用某个姿势。每个姿势仍要验证参与者、接触轴、骨架朝向、循环接缝和待机/过渡行为。
