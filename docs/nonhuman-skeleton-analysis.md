# 非人角色骨架分析

本文记录 Playtest Pak4 中非人 HAnime 参与者的静态骨架证据。分析遵循
`D:/zhifu/Desktop/data/mmd/docs/解包导出流程.md`：使用 UE5 专用
`umodel_materials_ue5.exe`、`-game=love` 与 Playtest AES 密钥，只读扫描游戏
Pak；不修改、重打包或全量重复解包资源。

## 当前结论

- `data/hanime-identity-v1.json` 中有 232 个不同的 HAnime family 引用了怪物
  Montage，共 756 条怪物 Montage、18 个怪物资源目录。
- Pak4 中确认了 18 种怪物主骨架和 19 个主 SkeletalMesh；Hound 同时保留
  `Mesh_Hound` 与 `Mesh_HoundRemake`，两者共用 `Mesh_Hound_Skeleton`。
- 怪物主骨架规模为 24–483 根参考骨，不能套用人形角色的固定功能骨集合。
- DeepOne 已完成一条代表动画的骨架与运动验证；Hound 已完成三条 NORMAL PSA
  的舌部端点对照。两者都还没有完成运行时组件与 Viewer 轴校准，因此仍不得
  直接加入正式自动 profile。

按 HAnime family 分类，怪物参与动作包含 105 个 vaginal、73 个 anal、23 个
mouth、14 个 hand、7 个 foot、4 个 breast，以及 6 个暂未归入现有分类的
family。多人/多怪物 family 会同时计入多个资源目录，因此下表各目录的 family
数量相加会高于 232 个全局唯一 family。

## Pak4 怪物清单

| 资源目录 | Family | Montage | 主网格骨数 | 静态附肢候选 | 状态 |
|---|---:|---:|---:|---|---|
| DeepOne | 39 | 123 | 176 | `JJ02_joint1 -> JJ02_joint15`，29.32 cm | 代表动画已验证 |
| Hound | 36 | 108 | 203 / 264 | `Tongue1` → `Tongue2` / `Tongue71`，参考距离 1.11 / 76.61 cm | 3 条 NORMAL 已确认舌端点；运行时待验证 |
| Ghast | 28 | 90 | 160 | `Ghast_jj_joint1 -> Ghast_jj_joint16`，24.39 cm | 连续链候选 |
| FlyCreature / Byakhee | 20 | 60 | 142 | `jj1_M -> jj_joint07`，32.25 cm | 连续链候选 |
| GreatRaceofYith | 18 | 54 | 483 | 49 条 `Skirt_*` 触手与大量 `cirrus` 骨 | 必须按动画选择 |
| Skorpios | 18 | 57 | 46 | `Tail001_M -> tail14`，45.63 cm | 尾部轴候选 |
| Ghoul | 13 | 45 | 330 | `JJ_joint -> JJ_join_Skin14`，23.27 cm | 连续链候选 |
| Shaggai | 11 | 51 | 169 | 多段 `Tail*` / `curve4Joint*` 链 | 必须按动画选择 |
| Lloigor | 8 | 24 | 284 | `j01_joint1 -> 21`，40.61 cm；`j02_joint1 -> 21`，40.44 cm | 双轴，必须按动画选择 |
| Sylph | 8 | 24 | 24 | `Drill3 -> Drill3_0`，8.01 cm；另有零长度缩放控制骨 | 道具式轴，待动画确认 |
| TchoTcho | 8 | 27 | 413 | `JJ_skin1splineIkBnA -> ...20`，18.04 cm | 连续链候选 |
| guge / Gug | 7 | 21 | 191 | `JJ_skin1 -> JJ_skin21`，39.92 cm | 连续链候选 |
| ElderThing | 6 | 18 | 268 | 多组 `Tentacle*` 分支 | 必须按动画选择 |
| Migo_2 | 5 | 15 | 367 | `JJ_slide*` 与多条 `tail_*` 分支 | 必须按动画选择 |
| yeyan / Nightgaunt | 5 | 15 | 249 | `tail_C0_0_Jnt` 到远端尾骨；另有 `JJ_size*` 控制骨 | 待动画确认 |
| Hippocamp_1 | 3 | 9 | 199 | `JJ_skin1 -> JJ_skin28`，55.08 cm | 连续链候选 |
| RevenantOfSaaitii_1 | 3 | 9 | 108 | `penis_root` 到远端 `penis_joint36`，约 41.01 cm | 星形远端链候选 |
| Shantak | 2 | 6 | 312 | `JJ2splineIkBnA -> ...20`，同时与尾链相连 | 待动画确认起点 |

长度来自 PSK/PSKX `REFSKELT` 的局部平移累加。它只能证明参考姿势中的骨架
结构，不能单独证明某条 Montage 使用哪一条附肢或哪一个远端骨。

## DeepOne 代表动画验证

静态资源：

- 主网格：`/Paralogue/Content/Characters/Monster/DeepOne/Meshes/Mesh_DeepOne`
- Skeleton：`Mesh_DeepOne_Skeleton`
- 参考骨数：176
- 参与者标签：`DeepOne`、`DeepOne_01`、`DeepOne_A_01`、
  `DeepOne_B_01`

代表动画：

`/Paralogue/Content/Characters/Monster/DeepOne/Anim/HAnim/Alet/Anal01/`
`AletDeepOne_Anal01_DeepOne_04_NOR`

该动画导出为 211 帧、188 条 PSA 轨道；其中 176 条映射到主骨架，其余 12 条
`L/R_Meat*` 轨道由 UModel 配置明确移除。主骨架中确认了以下连续父链：

`M_Hips -> JJ02_joint1 -> JJ02_joint2 -> ... -> JJ02_joint15`

测量结果：

- 参考姿势链长：29.319 cm。
- 动画中链长保持 29.319 cm，说明它是稳定的分段附肢链。
- `joint1` 到 `joint15` 的直线弦长在 25.191–26.564 cm 之间，链会随动画弯曲。
- 相对第 0 帧，基部最大移动约 13.879 cm，末端最大移动约 14.866 cm。

因此 DeepOne 的穿透/手足/口部接触 profile 可以以以下结构进入下一阶段验证：

- `originBone = JJ02_joint1`
- `directionBone = JJ02_joint2`
- `extendedTipBone = JJ02_joint15`
- `supportBone = M_Hips`

这只是骨架级 Reference 定义。每个 HAnime 仍需使用精确 Montage family 决定
Target（手、脚、口、vaginal 或 anal 接触骨），并在 Viewer 中核对 L0 方向、
接触半径以及 R0/R1/R2 的局部轴映射。

## Hound 代表动画验证

本节按《骨骼、动画分析与功能骨选取经验》的证据顺序记录 Hound。它只证明
`Mouth01` 的舌部 Reference 候选，不把 `Tongue*` 名称推广到所有 Hound 动作。

静态资源：

- 主网格：`/Paralogue/Content/Characters/Monster/Hound/Meshes/Mesh_Hound`
  与 `Mesh_HoundRemake`。
- Skeleton：`/Paralogue/Content/Characters/Monster/Hound/Meshes/Mesh_Hound_Skeleton`。
- 两个网格共用 `Mesh_Hound_Skeleton`；旧网格有 203 根参考骨，Remake 有 264
  根。三条导出 PSA 都是 264 轨，导出配置移除 61 条 Remake 新增软刺/脚趾轨道，
  `Tongue1`–`Tongue71` 轨道均保留。

参考姿势的舌部不是连续父链：`Tongue1` 是 `Root_M` 的子骨，`Tongue2` 至
`Tongue71` 是它的 70 个叶子子骨。按参考位置排序，`Tongue2` 距根约 1.112 cm，
`Tongue71` 距根约 76.609 cm；因此需要把它记录为“扇形叶骨的有序端点”，而不是
把 `Tongue2 -> Tongue3 -> ...` 当作父链。

代表 NORMAL 动画（精确路径同时登记在离线证据 JSON）：

| HAnime 类别 | 动画序列 | 帧数 / 轨道 | `Tongue1`→`Tongue71` 世界距离 | 远端最大移动 |
|---|---|---:|---:|---:|
| mouth | `AletHound_Mouth01_Hound_04_NOR` | 181 / 264 | 66.744–72.562 cm | 13.659 cm |
| anal | `AletHound_Anal01_Hound_04_NOR` | 186 / 264 | 75.432–77.215 cm | 11.193 cm |
| vaginal | `AletHound_Vaginal01_Hound_04_NOR` | 183 / 264 | 62.522–71.180 cm | 14.919 cm |

三条动画中每一帧的最近舌叶都是 `Tongue2`，最远舌叶都是 `Tongue71`；
这证明端点排序稳定。`Mouth01` 中 `Tongue1` 最大旋转约 18.91°、`Tongue71`
最大旋转约 48.19°，且远端距离和位置明显变化，足以把舌部列为口部 Reference
候选。`Anal01` 与 `Vaginal01` 虽然也会带动舌轨道，但这不能证明舌部是肛门或阴道
接触对，不能建立物种级默认绑定。

对精确 `Alet/Hound/Mouth01` family，下一阶段可登记以下骨架级候选：

- `originBone = Tongue1`
- `directionBone = Tongue2`
- `extendedTipBone = Tongue71`
- `supportBone` 候选：`RootPart1_M`；回退候选 `Root_M`

`RootPart1_M` 在三条样本中的最大本地旋转约 1.04–2.07°，比 `Root_M` 的
3.67–15.03° 更适合作为稳定参考面，但仍需 Viewer/运行时对照确认本地 right/up
映射。Target（Alet 的口部/接触部位）以及 L0 正负方向必须按精确 Montage/Section
继续标注，不能从 Hound 物种名推断。

离线证据：

`D:/zhifu/Desktop/data/mmd/exports/nonhuman-skeleton-analysis/Characters/Monster/Hound/hound-animation-analysis.json`

## 启用门槛

1. 为每种主骨架保留精确 SkinnedAsset 名称、骨架名、参考骨数和参与者标签。
2. 每条候选轴至少导出一个 NORMAL 循环，确认 origin、direction、tip 均存在于
   主动画轨道中且端点随画面接触运动。
3. 多轴怪物必须按精确 Montage/Section 选择轴，不设置物种级默认。
4. 在 F8Studio Viewer 中确认 L0 深度方向，并检查弯曲附肢的端点弦是否足以表示
   接触；不足时改用分段或最近点策略。
5. 完成运行时主组件匹配与断流回中测试后，才能写入正式
   `skeleton-catalog-v1.json` 和 runtime profile。

## 分析产物

本轮定向导出位于：

`D:/zhifu/Desktop/data/mmd/exports/nonhuman-skeleton-analysis/`

其中包含 19 个主网格的 PSK/PSKX、对应属性文件和参考骨架 JSON，以及 DeepOne
和 Hound 代表 NORMAL 动画的 PSA 与 Hound 测量 JSON。该目录只用于离线证据与
后续复现，不是发布包内容。
