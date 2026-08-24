# 姿势参考系规则

本目录为每条动作定义谁构成接触轴、谁是相对运动目标、以及如何把骨骼本地轴映射到统一的 SR6 参考系。角色显示名不是全局规则；它们只出现在某条 profile 的骨架匹配提示中。

## 当前正式范围

`AletMale_Hand01`、`AletMale_Hand02` 与 `AletMale_Hand03` 已迁移至 `data/runtime-profiles-v2.json`。三者均以配对目标的 `Penis01` 为起点、`Penis02` 为实时方向、`Penis09` 为完整长度，并用 `M_Hips` 稳定参考面；主动方 `R_Hand` 是 Target。它们不再读取动画进度或离线曲线；L0/L1/L2/R0/R1/R2 由当前帧相对几何计算。

此前导出的 `paired-motion-profiles.json` 仍保留为 L0 周期和方向的回归证据。最新实时捕获确认 `local_x` 已按 `Penis01 -> Penis02` 正向增长，因此 L0 不再额外反向；其余五轴必须经游戏内模拟画面对照后再校准。

Pak4 定向导出进一步确认：Alet 使用 `Mesh_Alet_Skeleton`（396 个参考骨），男性主体使用 `MeshMaleB_Skeleton`（353 个参考骨）。男性接触轴的真实父链是 `M_Hips -> M_Gen -> Penis01 -> ... -> Penis09`；`Penis01 -> Penis02` 只有约 2.6 cm，仅适合确定方向，`Penis01 -> Penis09` 约 19.6 cm，才适合作为有限圆柱长度。完整层级位于 `data/exported-skeletons/`。

Hand01/02/03 的六条配对 PSA 及准确包路径记录于 `data/hand-pose-assets-v1.json`。动画轨道中的 `Male_A` 是参与者槽位，而不是另一套 MaleA 骨架；三条动作均绑定 `MeshMaleB_Skeleton`。Hand03 另有椅子同步轨道，但它不参与当前接触轴计算。

## 统一规则

1. 解析顺序为：会话内 UI 覆盖、精确 Montage/Section profile、已登记骨架候选的自动接触、`unmapped`。
2. 每条 profile 都有 `roles`、`reference`、`target` 与每轴设置；`reference` 必须有起点与终点骨骼。
3. 世界坐标、相机坐标和某一个固定角色的髋骨不能作为默认参考系。
4. 自动选择只在同一 profile 允许的候选内进行，使用三帧获取、1.25 倍释放半径和 20%/250 ms 切换迟滞。
5. 待机、未知/无接触、过渡和对象失效会平滑回中；不会因为 Montage position 循环而重置 L0。

## 分类工作队列

| 类别 | Reference / Target 策略 | 当前状态 |
|---|---|---|
| hand_guided | 接触主轴 -> 活动手 | Hand01/02/03 已有运行时 profile |
| foot_guided | 接触主轴 -> 活动脚 | 需骨架目录与配对验证 |
| mouth_guided | 接触主轴 -> 头部/口部代理 | 需骨架目录与配对验证 |
| penetration | 进入物/附肢轴 -> 接触部位 | 每姿势人工标注 |
| breast_contact | 显式接触轴 -> 接触部位 | 每姿势人工标注 |
| prop_guided | 道具轴或控制手 -> 被作用部位 | 每姿势人工标注 |
| generic_pair | 明确的主接触对 | 每姿势人工标注 |

多人动作只选一个主接触对驱动一条 SR6 轨道。非人类只能使用 `skeleton-catalog-v1.json` 中已验证的附肢/目标，不从物种名称猜测。触发型短动作在首版仅记录 Montage/Section，不会另行覆盖轴。
