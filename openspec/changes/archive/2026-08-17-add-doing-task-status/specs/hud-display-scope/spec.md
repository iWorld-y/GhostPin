## MODIFIED Requirements

### Requirement: 显示范围切换

HUD SHALL 支持两种显示范围：全部未完成任务、今天新增的未完成任务。未完成任务包括状态为 Todo 或 Doing 的任务。

#### Scenario: 展示今天新增
- **WHEN** 显示范围设为"今天新增"
- **THEN** HUD 只展示创建于今天且状态为 Todo 或 Doing 的任务

#### Scenario: 展示全部未完成
- **WHEN** 显示范围设为"全部未完成"
- **THEN** HUD 展示所有状态为 Todo 或 Doing 的任务

## ADDED Requirements

### Requirement: 未完成任务分区

HUD SHALL 将未完成任务分为 Doing 和 Todo 两个区域；Doing 区域 MUST 位于 Todo 区域上方，空区域 MUST 不展示。每个区域内部 SHALL 沿用现有优先级、截止时间、逾期状态和创建时间排序规则。

#### Scenario: 两个区域均有任务
- **WHEN** HUD 显示范围内同时存在 Doing 和 Todo 任务
- **THEN** HUD 先展示 Doing 区域，再展示 Todo 区域，且 Doing 区域中的 low 优先级任务仍排在所有 Todo 任务之前

#### Scenario: 只有一个区域有任务
- **WHEN** HUD 显示范围内只有 Doing 或只有 Todo 任务
- **THEN** HUD 只展示有任务的区域，不展示空区域

#### Scenario: 完成 Doing 任务
- **WHEN** Doing 任务被标记为 Done
- **THEN** 任务从 HUD 中消失，HUD 重新应用显示范围、分区和条数上限

### Requirement: 条数上限跨区域生效

HUD SHALL 最多展示 N 条未完成任务（N 可在设置中调整，默认值位于 5 至 10 之间）；截断时 MUST 先保留 Doing 区域任务，再保留 Todo 区域任务。

#### Scenario: Doing 任务占满上限
- **WHEN** Doing 任务数量不少于 N
- **THEN** HUD 只展示按区域内排序规则排列的前 N 个 Doing 任务，不展示 Todo 区域

#### Scenario: Doing 任务未占满上限
- **WHEN** Doing 任务数量少于 N 且 Todo 任务数量超过剩余容量
- **THEN** HUD 展示全部 Doing 任务和按区域内排序规则排列的 Todo 任务，合计不超过 N 条
