# 骨骼、动画分析与功能骨选取经验

本文总结 Operation Lovecraft: Fallen Doll TCode 项目在解包、运行时日志、骨架流和 F8Studio 六轴实验中形成的方法。目标不是为某一条动画硬编码曲线，而是稳定回答三个互相独立的问题：

1. 当前是否正在播放可输出的 HAnime；
2. 当前 HAnime 中有哪些真实参与者，谁是主要交互对；
3. 应读取哪些最少的功能骨，如何由它们计算相对运动。

文中的“已验证”表示同时具有静态资源或运行时证据；“候选”仅表示骨架结构上可能可用，不能直接启用设备输出。

## 一、最重要的结论

- 解包数据负责确定骨架、父子链、动画 family、参与者标签和候选功能骨；运行时只验证活动实例、实际播放状态和当前帧变换。
- 动画身份不能通过路径中的 `Hand`、`Foot`、`Vaginal` 等单词猜测。正式识别使用 `TableHAnim` family 生成的精确 Montage 白名单。
- Montage position 不能代表往返动作，也不能直接驱动 L0。动作速度、循环和姿态应来自当前帧骨骼相对几何。
- 角色名不是运动规则。先选择参与者，再在该参与者自己的骨架目录中选择功能骨。
- 功能骨不是“离接触点最近的任意骨”。它是具有稳定语义的少量骨骼：接触轴起点、方向点、完整端点、支撑平面，以及手、脚、口、阴道、肛门、乳房等 Target。
- 左右手、左右脚、双手/双脚同时参与以及多人场景都存在主次关系。没有逐 HAnime 标注时，应暴露候选但不猜主骨。
- 不连续读取完整骨架。正式路径按当前交互类别读取紧凑功能骨，通常每个接触对约 5 根，50 Hz 足以同步游戏动画。

## 二、证据优先级

建议按以下顺序形成结论：

1. **解包后的 TableHAnim 和动画 family**：确认 HAnime 身份、参与者标签、NORMAL/MIN/MAX 变体和准确资产路径。
2. **Skeleton / SkeletalMesh / PSKX REFSKELT**：确认骨名、父链、参考姿势长度和本地轴。
3. **配对动画 PSA**：确认候选骨确实有动画轨道、哪一侧在运动、附肢是否弯曲、接触范围是否合理。
4. **运行时 Montage 与组件日志**：确认活动对象、主 SkeletalMeshComponent、动画进入/退出和切换行为。
5. **3D Viewer 与画面对照**：确认 L0 方向、左右/前后、Twist、Roll、Pitch 及本地轴映射。

不要反过来先做全局运行时枚举，再从大量日志猜资产结构。静态结论应写回机器可读目录，下一次直接复用。

主要依据文件：

- `data/unpacked-hsystem-contract-v1.json`
- `data/hanime-identity-v1.json`
- `data/hanim-table-index-v1.json`
- `data/skeleton-catalog-v1.json`
- `data/exported-skeletons/`
- `data/runtime-profiles-v2.json`
- `docs/nonhuman-skeleton-analysis.md`

## 三、动画分析：先识别身份，再分析运动

### 3.1 HAnime 身份门控

当前可靠做法是把活动 Montage 与由 `TableHAnim` family 生成的精确白名单匹配。Playtest 数据中，477 个权威 family 展开为约 3,081 条主角色、配对角色和物件 Montage。只有精确命中后才开启骨骼流。

正式门控规则：

- 连续 3 次观察到同一新 HAnime 后才确认进入；
- `Exp_Idle`、表情、普通待机、未知 Montage 和过渡动画不进入输出；
- NORMAL、MIN、MAX 是同一 family 的阶段/变体，不应被当成三种互不相关的姿势；
- 轮盘直接切换和“先回 Idle 再进入”都要通过状态事件重新绑定；
- 退出、隐藏角色、VR 第一人称过滤或对象暂时不可见时，允许短暂保持，但不能永久保留陈旧对象；
- 重新进入 HAnime 时自动恢复发现，不要求用户重新开关快捷键。

### 3.2 为什么不能用 Montage position

实践中 Montage position 很容易被误解为动作位置，实际更像播放器进度：

- 往返画面可能对应单向递增的 position；
- 主表 Montage 可能只播放约 1.65 秒，但 HAnime 画面由其他路径继续循环；
- Section 或 Montage 切换会造成 position 归零，产生错误的回中或“下砸”；
- 游戏速度改变后，离线相位曲线容易漂移。

因此 Montage 只用于身份与规则选择。实际运动必须读取当前帧骨骼变换；相同画面姿态应得到相同轴值，与动画播放了第几轮无关。

### 3.3 Special 和短触发动作

很多 HAnime 含 1–2 条约数秒的特殊动作，但它们未必具有独立、可读的名称，也未必改变主要接触骨。当前经验是：

- 首先记录实际 Montage/Section/事件和持续时间；
- 若主要交互对没有变化，保持原绑定连续计算；
- 只有画面明确切换到另一功能骨或另一参与者时，才增加逐 HAnime/Section 覆盖；
- 无证据时不按时间点或名称猜测 Special。

## 四、参与者绑定经验

### 4.1 参与者身份来自 family，不来自场景中任意网格

参与者应由解包的 `TableHAnim` participant tag 推导，并由该参与者正在播放的精确 Montage 绑定到运行时组件。A/B/C 标签是参与者槽位，不代表另一套通用骨架。例如动画轨道中的 `Male_A` 仍可能使用 `MeshMaleB_Skeleton`。

运行时输出保留两类信息：

- 通用运动角色：`male` / `female`，供 UI 和通用算法选择；
- 精确目录身份：Alet、Erika、Galatea、Juzi、yanshi、Anya、MaleB 或非人骨架，用于骨名和轴映射。

### 4.2 模块化角色只算一个参与者

身体、头发、衣服、手部等多个 SkinnedAsset 可能共用同一骨架。若无条件枚举，会把一个角色误识别为数十个参与者，并显著拖慢游戏。

每种角色目录必须记录：

- 准确 SkeletalMesh/Skeleton 名称；
- 主组件名称或组件标记；
- 参考骨数量/兼容签名；
- 已验证的 participant tags。

只有主组件可进入实时流。以 yanshi 为例，运行时已确认只使用 `Mesh_Main`，不读取共享骨架的身体附件。

### 4.3 多人场景的选择

多人场景不应默认固定选择 `MaleA` 或 `MaleB`，也不能逐帧按距离在参与者间跳转。推荐顺序：

1. 用户在 UI 中明确选择的参与者；
2. 当前 HAnime 注释中指定的主参与者槽位；
3. TableHAnim participant tag 的 A/B/C 优先级；
4. 无可靠主接触对时不输出。

同一角色类型的参与者使用稳定 key，例如 `fallen-doll:male:0`、`fallen-doll:male:1`。用户可以禁用优先参与者，让选择器回退到下一个已登记参与者；禁用全部则停止输出。

## 五、功能骨的模型

### 5.1 Reference 与 Target

VaM/ToySerial 一类几何方法可以抽象为：

- **Reference**：稳定的接触轴或有限圆柱；
- **Target**：相对 Reference 运动的接触点及其朝向。

Reference 通常由四个骨骼定义：

| 角色 | 用途 |
|---|---|
| Origin | 接触轴起点 |
| Direction | 只用于确定当前帧主轴正方向 |
| Extended Tip | 定义完整有效长度 |
| Support | 构造稳定的横向参考平面 |

Target 至少需要一个位置骨；计算旋转轴时还需要已校准的本地 `up/right` 映射，必要时可增加方向辅助骨。

### 5.2 为什么方向点和完整端点要分开

MaleB 已验证父链为：

`M_Hips -> M_Gen -> Penis01 -> Penis02 -> ... -> Penis09`

其中：

- `Penis01 -> Penis02` 约 2.6 cm，适合确定实时轴方向；
- `Penis01 -> Penis09` 约 19.6 cm，适合定义完整有限圆柱长度；
- `M_Hips` 的校准本地轴适合稳定 Reference 平面。

只用 `Penis01 -> Penis02` 当完整行程会把 L0 压缩并放大噪声；只用世界轴或髋骨方向又会在姿势改变时失去接触语义。

### 5.3 六轴含义

统一局部坐标系建立后：

- `L0`：Target 沿 Reference 主轴的归一化深度；
- `L1/L2`：Target 在 Reference 局部前后、左右方向的偏移；
- `R0`：Target 围绕主轴的相对扭转；
- `R1/R2`：Target 相对 Reference 平面的两个倾斜角。

旋转应通过局部基向量和四元数/有符号角计算，不直接相减 Unreal 欧拉角。直接做欧拉角差会在 `+180°/-180°` 分支处突变，早期 Hand 测试中的 Pitch 跳变就是这一类错误。

## 六、按交互类别选择功能骨

| 交互类别 | 常用 Reference | 常用 Target | 主要风险 |
|---|---|---|---|
| 手部 | 被作用对象的接触轴 | `R_Hand` / `L_Hand` | 左右手与主次手不能猜 |
| 足部 | 被作用对象的接触轴 | `R_Foot` / `L_Foot` | 双脚、斜向运动和局部轴差异 |
| 口部 | 进入物/附肢轴 | Jaw 或 Tongue root | 各骨架 Jaw 名称不同 |
| 阴道 | 进入物/附肢轴 | `M_Gen` | Target 本地轴需独立校准 |
| 肛门 | 进入物/附肢轴 | 骨架目录中的 anal origin | 不同角色骨名不一致 |
| 乳房 | 显式接触轴或活动对象 | 左/右乳头接触骨 | 左右乳房、双侧同时接触 |
| 道具 | 道具轴或控制手 | 被作用部位 | 道具可能有独立组件/骨架 |
| 非人附肢 | 已验证的附肢父链 | 当前接触部位 | 多条触手/尾链不能按物种猜 |

### 6.1 手和脚的主次关系

Hand/Foot 不能仅按类别设置一个全局默认。常见情况包括：

- 只有右侧或左侧参与；
- 两侧都参与，但只有一侧提供主要往返；
- 一侧稳定接触，另一侧执行短触发动作；
- 两侧交替成为主要动作。

推荐在逐 HAnime 注释中保存有序候选，例如：

```text
preferred: [R_Hand, L_Hand]
```

选择器默认使用第一个启用候选。用户取消勾选 `R_Hand` 后，应自然回退到 `L_Hand`，不需要重载 Mod。未标注左右/主次的 Hand 或 Foot 姿势可以被识别为 HAnime，但不应自动生成正式接触输出。

当前已验证的 `AletMale_Hand01/02/03` 采用右手主、左手备选；这条结论不能自动推广到其他 Hand 动画。

### 6.2 口、阴道和肛门

这三类通常没有左右歧义，因此可按骨架目录给出类别默认候选。但骨名不能跨角色硬套：

| 骨架 | Mouth | Vaginal | Anal |
|---|---|---|---|
| Alet / Erika / Anya | `M_Jaw` | `M_Gen` | `M_AnusInside` |
| Galatea / yanshi | `M_Jaw_master` | `M_Gen` | `M_Anus_Inside1` |
| Juzi | `Jaw_master` | `M_Gen` | `M_Anus_Inside` |

Tongue root 可作为口部备选或朝向辅助，但 Jaw 与 Tongue 表达的运动含义不同，应通过画面对照决定优先级。

### 6.3 乳房

人形目录当前登记 `R_Breast_Nipple` 和 `L_Breast_Nipple` 作为紧凑候选。它们只是语义接触点，不表示所有 Breast 动画已完成主次标注。双侧动作仍应保存有序候选或显式双接触规则。

### 6.4 非人角色

非人骨架差异很大，不能套用人形固定集合。静态父链只证明“可能是一条连续附肢”，不能证明该动画实际使用它。

以 DeepOne 为例，代表动画已经验证：

- Origin：`JJ02_joint1`
- Direction：`JJ02_joint2`
- Extended Tip：`JJ02_joint15`
- Support：`M_Hips`
- 参考姿势链长约 29.32 cm，动画中链长稳定，但端点弦长会随弯曲变化。

多触手、多尾链或双附肢生物必须按精确 HAnime 选择具体链。若单一直线端点不足以表达弯曲接触，应改用分段最近点，而不是强行把整条附肢当刚性圆柱。

Hound 是“有序叶骨扇”而不是连续父链的例子。`Mesh_Hound_Skeleton` 的
`Tongue1` 下挂 `Tongue2`–`Tongue71` 共 70 个叶子骨；三条 NORMAL PSA 对照中，
`Tongue2` 每帧都是最近舌叶、`Tongue71` 每帧都是最远舌叶。精确
`Alet/Hound/Mouth01` 的舌部 Reference 候选为：

- Origin：`Tongue1`
- Direction：`Tongue2`
- Extended Tip：`Tongue71`
- Support 候选：`RootPart1_M`，回退 `Root_M`

这只证明 Mouth01 的候选轴。Hound 的 Anal01/Vaginal01 也会让舌轨道运动，
但没有证据表明舌部是这些动作的接触对，因此不能把 `Tongue*` 作为 Hound 的
物种级默认 Reference。三条 PSA 的帧级测量、精确 Montage 路径和 61 条导出
移除轨道记录于 `hound-animation-analysis.json`；运行时组件匹配、Viewer 轴和
Target 仍需逐姿势验证。

### Playtest 受控导出的精测边界

Playtest 的批量精测必须从 `playtest-family-evidence-status-v1.json` 生成，而
不是从动作名或怪物目录直接展开。`playtest-precision-measurement-queue-v1.json`
只收入同时满足以下条件的同一条记录：精确 `TableHAnim` 身份、声明候选在
REFSKELT 中完整、同一 mesh 的精确 `*_04_NOR` PSA 全骨名覆盖、以及候选骨都
实际具有 PSA 轨道。当前队列为 41 个 family/41 条 PSA（34 条连续父链、7 条
道具轴）；离线帧测结果保存在
`playtest-precision-actorx-measurements-v1.json`。

其中 7 条 Sylph 道具轴在每个采样帧中都呈现 Origin/Direction（同时也是
Tip）重合。它们是“已测得退化骨对”的静态证据，**不能**被自动变成零长度
运行时方向轴；仍须在 Viewer 中确认对应的组件、道具或 spline 是否提供了
方向。所有 41 条队列项都明确保留组件绑定、Reference/Target 角色、目标骨、
局部轴正负/基准和 Viewer 接触验证等未完成项，且均无 runtime rule。

Playtest 非人则有一张完整、可由 profile-table adapter 读取的静态正式表：
`playtest-nonhuman-static-formal-rules-v1.json`。它覆盖 227/227 个由
TableHAnim 和 UE5 package 身份确认的 family，使用精确 `hanimeId` 与 edition；
150 条提供静态 Reference 链，77 条没有已声明的静态链也会以空
`referenceCandidates` 明确入表。所有条目的 `state` 都是
`static_formal_pending_runtime_calibration`，`runtimeCalibrationPending=true`，
没有任一条声称已经 runtime verified。没有同 mesh 完整 PSA 覆盖或 REFSKELT
候选不完整的链会保留相应置信度和未决原因，不能由名称补全 Target 或局部轴。

## 七、候选、优先级与回退

建议把“需要读取的候选骨”和“默认首选骨”分开：

- `candidate bones` 决定本帧最多读取哪些骨；
- `preferred bones` 是按 HAnime 注释排序的默认选择；
- UI 的 enabled 列表决定用户允许哪些候选；
- 禁止 `allowUnrankedFallback`，避免未知骨突然接管输出。

当前类别默认策略：

- Mouth：Jaw，Tongue root；
- Vaginal：vaginal origin；
- Anal：anal origin；
- Hand/Foot：只暴露左右候选，不自动确定主次；
- Breast：暴露左右候选，不自动确定主次；
- Other：只为精确白名单 HAnime 暴露一个小型功能骨集合，由用户选择，不按名称猜测。

## 八、本地轴与方向校准

骨名相同不等于本地轴相同。每个 Target 类型、必要时每种骨架，都应分别记录 `up/right` 映射。

当前 Hand01 运行日志确认：

- Reference right：`M_Hips -local_x`
- Reference up：`M_Hips +local_y`
- Alet `R_Hand` Target up：`+local_z`
- Alet `R_Hand` Target right：`-local_y`

校准顺序：

1. 先固定 Reference 和 Target，观察纯 L0 往返方向；
2. 再观察前后与左右，确认 L1/L2 没有互换或反向；
3. 用带明显朝向变化的姿势检查 Twist；
4. 最后检查 Roll/Pitch 是否在边界连续；
5. 同一映射必须在动画循环、速度改变和 Section 切换下保持稳定。

不要用“在最终输出端反向”掩盖骨架基准错误。设备 Output Range、轴反向和安全限制属于用户配置；骨架本地轴映射属于游戏适配层，两者应分离。

## 九、性能经验

### 9.1 紧凑采样

正式路径以 50 Hz 读取当前类别需要的最小集合。典型 Hand 接触对为：

- Reference：`Penis01`、`Penis02`、`Penis09`、`M_Hips`；
- Target：当前主手 1 根；
- 若允许用户即时切换左右手，可同时读取左右手，但仍不读取完整骨架。

动画身份发现可保持 250 ms。骨骼变换负责速度同步，身份轮询不需要跟随每帧动画速度。

### 9.2 避免的高成本操作

- 不逐帧 `FindAllOf`；
- 不逐帧枚举所有 SkeletalMeshComponent；
- 不读取数百根完整骨架用于设备输出；
- 不打印每帧骨骼日志；
- 不把 3D Viewer 或波形刷新放入设备输出关键路径。

全局发现只在启动、缓存对象失效或确认从 Idle 重新进入 HAnime 时执行。曾经的高频发现会造成明显卡顿，并刷新角色次级物理，例如胸部抖动。

### 9.3 数据有效性

- Unreal 位置从厘米转换为米；
- 四元数从 Unreal `XYZW` 重排为接收端 `WXYZ`；
- 零四元数、NaN、未注册组件和失效 UObject 立即判无效；
- 不发送只有 Reference 或只有 Target 的半帧；
- 六轴以同一原子帧传递，避免一帧内混入不同采样时刻。

## 十、连续性与状态管理

功能骨正确仍不代表输出连续。建议同时应用：

- 新接触连续 3 帧有效才进入 Active；
- 释放使用更大的迟滞半径并连续确认；
- 新候选至少明显优于当前候选，并保持一段时间才切换；
- 相同参与者与功能骨下的 NORMAL/MIN/MAX 或 Section 切换不重置 L0；
- 短暂丢帧保持最后值，持续无效再平滑回中；
- Idle 不输出接触运动，但保持低频重入检测；
- 隐藏角色或 VR 显示过滤不能让陈旧缓存永久停止检测。

突然“下砸”通常不是骨骼动作，而是状态切换时强制回 5000 后又立即恢复。应先判断绑定是否真的改变，再决定是否回中。

## 十一、逐姿势标注模板

推荐每条已验证规则至少保存以下信息：

```json
{
  "hanimeId": "AletMale_Hand02",
  "participants": {
    "reference": { "role": "male", "priority": 0 },
    "target": { "characterRole": "alet", "priority": 0 }
  },
  "reference": {
    "origin": "Penis01",
    "direction": "Penis02",
    "extendedTip": "Penis09",
    "support": "M_Hips",
    "right": "support_-local_x",
    "up": "support_+local_y"
  },
  "targets": [
    { "bone": "R_Hand", "priority": 0, "up": "+local_z", "right": "-local_y" },
    { "bone": "L_Hand", "priority": 1, "status": "user_fallback" }
  ],
  "evidence": ["unpacked_skeleton", "paired_animation", "runtime_viewer"],
  "status": "verified"
}
```

模板中的优先级是选择顺序，不是把多个接触混合成一条轴。若一个姿势确实需要双接触同时建模，应明确新增多接触规则，而不是隐式平均两只手或两只脚。

## 十二、验证清单

每个新 HAnime/功能骨组合至少验证：

1. 精确 HAnime 身份可进入，Idle/过渡不会误触发；
2. 参与者数量、角色和 A/B/C 槽位正确；
3. 主组件正确，没有把衣服或附件当成新角色；
4. 左右手/脚及主次关系与画面一致；
5. L0 与主要往返同向且无循环末尾跳变；
6. L1/L2 的前后、左右含义正确；
7. R0/R1/R2 无 `±180°` 翻转和持续饱和；
8. 改变游戏动画速度后，骨骼输出仍同步；
9. 轮盘切换、回 Idle、ESC、隐藏角色和 VR 模式后可自动恢复；
10. 运行时只读取紧凑骨集合，无明显帧率下降或次级物理刷新；
11. Preview 关闭时不绘制 3D/波形，但设备数据路径仍正常；
12. 最后才启用真实设备，并在 Studio/设备层限制输出范围。

## 十三、已经验证与尚未完成的边界

已验证：

- 七种可玩人形骨架的独立目录和主要功能骨；
- MaleB 接触轴 `Penis01/02/09 + M_Hips`；
- `AletMale_Hand01/02/03` 的右手主 Target 和 Hand 本地轴映射；
- 精确 HAnime 白名单、参与者优先级、Idle 关闭与重新进入恢复；
- 50 Hz 紧凑功能骨流可以在不持续全骨架枚举的情况下工作；
- DeepOne 一条代表附肢链的静态和动画测量。

仍需逐姿势验证：

- 其他 Hand/Foot 的左右和主次；
- 双手、双脚、双乳房同时交互；
- 多人场景的主接触对；
- 每类 Target 的本地轴映射；
- 多触手、道具和非人附肢的具体链；
- Special 短动作是否需要切换功能骨；
- 尚未标注 HAnime 的完整六轴方向和输入范围。

最终原则是：**身份可自动识别，候选可由骨架目录提供，但主功能骨和局部轴必须有逐姿势证据。**

## 十四、严格精测采集模式（默认关闭）

`fd_tcode.precision_capture` 是为严格 Demo/Playtest 精测队列准备的独立证据记录器，
不是普通实时骨骼流的一部分。它只读取已经进入严格队列的 `hanimeId`、精确网格和
候选骨名；不会新增规则、选择 Reference/Target、计算轴，也不会写入设备输出。

默认没有任何采集副作用：只有在启动游戏进程前同时设置以下环境变量才会启动：

```powershell
$env:FD_TCODE_PRECISION_CAPTURE = "1"
$env:FD_TCODE_PRECISION_EDITION = "demo-ue4.25" # 或 playtest-ue5，必须与游戏版本一致
```

输出单独位于运行时目录的 `fd-precision-capture.ndjson`；不会覆写普通
`fd-skeleton.ndjson`。每条记录包含严格队列 case、精确活动 Montage、Section/Position、
参与组件与 SkinnedAsset 标识、组件 world transform，以及每根候选骨的 world transform
和 component-space transform（`RTS_World=0`、`RTS_Component=2`）。component-space 不是
父骨 local transform，不能把它直接标成已经校准的局部轴。

队列变动后，先在工作区运行：

```powershell
python tools/build_precision_capture_data.py --check
```

采集代码和 allowlist 只保存在工作区；该命令不会安装、复制或覆盖任何外部游戏目录。
部署必须由操作者在关闭游戏后另行执行，且 Demo 与 Playtest 必须分别部署/验证。

采集完成仍不能自动生成规则。人工 Viewer 门槛为：在对应游戏场景中逐条核对 capture
记录的 `hanimeId`、Montage 和 `SkinnedAsset`；确认该组件是当前活动实例；在游戏/F8Studio
Viewer 中确认 Reference、Target、左右/主次和真实接触顺序；最后以同一时间段的画面
确认局部轴方向、符号及标定。当前 `fd_source` 只读取普通 `fd-skeleton.ndjson`，不读取
此精测文件，因此精测 capture spool 本身不构成 Viewer 验证或正式规则证据。
