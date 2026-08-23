# 解包数据优先的研究流程

## 原则

Fallen Doll 的 Pak、UAsset、骨架和动画导出结果是进入游戏实验前的
必查材料。运行时验证只回答静态资源不能回答的问题，例如当前账号、房间、
角色和解锁状态最终筛选出的姿势，以及活动中的具体对象实例。

禁止把运行时全局遍历当作默认发现手段。只有当前 Pak 的指纹与缓存记录不符，
或者已有静态契约无法定位目标对象时，才允许做一次有边界的运行时枚举；得到
结论后必须回写静态契约，下一次直接按已知类、外层关系、属性和函数访问。

## 每次实验前的顺序

1. 运行 `python tools/check_unpacked_hsystem_contract.py`，检查
   `data/unpacked-hsystem-contract-v1.json` 中的 Pak/资产指纹是否仍匹配。
2. 查静态契约里的准确资产路径、类名、组件层级、函数名和结构字段。
3. 查 `TableHAnim` 与动画资产索引，确定候选 Card、动画路径和参与者。
4. 只为仍未确定的动态条件设计一个最小实验，并写清预期结果和失败条件。
5. 在游戏线程中只访问已知对象；不逐帧 `FindAllOf`，不无差别打印所有属性。
6. 实验后立即更新静态契约、索引和结论，并关闭游戏。

## 当前已经确认的 H 系统关系

- 单人房活动实例为 `HManager_C`；此前日志中的 `HStateManager_C` 是它的组件，
  不是姿势目录的拥有者。
- `/Game/Core/BP/H/HManager` 提供当前会话目录相关入口：
  `GetSPAnimCount`、`GetSPAnimCountByCardID`、`GetDatabyCardID`、
  `GetHAnimDataByAnimID`、`GetHAnimDataByCardID`、`GetHCardByAnimID`、
  `GetHCardByID`、`GetMyHsystemCharacters`、`GetNecessaryData`、`PlaySPAnim`。
- UE4SS Lua 调用 `GetSPAnimCount` 时必须传入输出表，再读取 `out.Num`。房间实测
  返回 `1`，它只是当前 SP/会话计数，不能解释为该角色约 70 条完整 HAnime。
- `LocalHDatas`/`LocalHDataMap` 是 HManager 蓝图图表中的局部符号，不是活动
  `HManager_C` 可反射的实例属性。目录条目应走 `CardId` → `GetDatabyCardID`
  （`Data` 与 `IsDataValid` 为输出参数），不得再尝试直接读取伪属性。
- `/Game/BP/HSceneManager` 并没有 `GetPoseList`。它主要持有
  `AnimManager`、`StateManager`、`CharacterGroupManager`、`DataManager` 和
  `UIManager`，并处理 `EventSelectPose`/`EventSelectPoseState`。
- `/Game/BP/HAnimManager` 提供 `GetAnimData`、`GetCurrentAnimData`、
  `GetIdleAnimData`、`SetupTargets` 和 `PlayAnim`。
- `/Game/Data/DataHAnim` 是姿势数据结构；`/Game/Data/TableHAnim` 是完整静态表，
  但完整表不等于当前 UI 可见列表。
- `TableHAnim` 导入的 Montage 名称只能作为 HAnime 进入时的保守交叉证据，不能
  单独定义整个动作的持续时间。实测主表 Montage 可能只播放约 1.65 秒，而画面中的
  HAnime 继续由另一条动画路径循环。持续和退出必须读取当前 H 系统的
  `AnimID`/状态；待机、过渡和未知 Montage 仍不依靠名称猜测。
- 当前 UI 数量应从活动 `HManager_C` 的 Card/会话选择逻辑读取，而不是由
  `GetSPAnimCount` 单个结果、Pak 文件数、TableHAnim 导入目录数或名称模式推断。

完整机器可读记录见 `data/unpacked-hsystem-contract-v1.json`。
