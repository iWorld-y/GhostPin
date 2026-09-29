# Spec Delta

## ADDED Requirements

### Requirement: 有 Doing 时只显示 Doing

系统 SHALL 提供「有 Doing 时只显示 Doing」显示偏好，默认开启。该偏好开启时，若当前显示范围内存在任意 Doing 任务，HUD MUST 只渲染 Doing 任务并隐藏全部 Todo 卡片；若不存在 Doing 任务，HUD SHALL 照常渲染 Todo 任务。该偏好关闭时，HUD MUST 恢复为 Doing 区域与 Todo 区域同时展示。

#### Scenario: 开启且存在 Doing 任务

- **WHEN** 「有 Doing 时只显示 Doing」开启，且显示范围内同时存在 Doing 与 Todo 任务
- **THEN** HUD 只展示 Doing 任务，不展示任何 Todo 卡片，也不展示 Todo 区域标题

#### Scenario: 开启但不存在 Doing 任务

- **WHEN** 「有 Doing 时只显示 Doing」开启，且显示范围内只有 Todo 任务
- **THEN** HUD 展示 Todo 任务，行为与关闭该偏好时一致

#### Scenario: 关闭后恢复同时展示

- **WHEN** 用户关闭「有 Doing 时只显示 Doing」，且显示范围内同时存在 Doing 与 Todo 任务
- **THEN** HUD 同时展示 Doing 区域与 Todo 区域

#### Scenario: 最后一条 Doing 完成

- **WHEN** 该偏好开启，用户在交互模式下将显示范围内最后一条 Doing 任务标记为 Done
- **THEN** 该任务从 HUD 消失，HUD 因不再存在 Doing 任务而转为展示 Todo 任务

### Requirement: 分区任务计数

HUD 头部 SHALL 分别展示当前显示范围内的 Doing 任务数与 Todo 任务数；两个计数 MUST 相互独立呈现，且在该偏好隐藏 Todo 卡片时仍 SHALL 展示 Todo 计数。

#### Scenario: 两个计数分别展示

- **WHEN** 显示范围内存在 2 条 Doing 与 5 条 Todo 任务
- **THEN** HUD 头部同时展示 Doing 计数 2 与 Todo 计数 5，而不是合计的 7

#### Scenario: 隐藏 Todo 卡片时计数仍可见

- **WHEN** 「有 Doing 时只显示 Doing」开启且存在 Doing 任务
- **THEN** HUD 头部仍展示 Todo 计数，用户可据此得知存在被隐藏的 Todo 任务

#### Scenario: 计数随数据刷新

- **WHEN** CLI 将一条 Todo 任务改为 Doing，HUD 自动刷新
- **THEN** 头部 Doing 计数加一、Todo 计数减一，且卡片按当前偏好重新分流

## MODIFIED Requirements

### Requirement: 未完成任务分区

HUD SHALL 将未完成任务分为 Doing 和 Todo 两个区域；当「有 Doing 时只显示 Doing」关闭时，Doing 区域 MUST 位于 Todo 区域上方，空区域 MUST 不展示。当该偏好开启且存在 Doing 任务时，HUD MUST 只展示 Doing 区域。每个区域内部 SHALL 沿用现有优先级、截止时间、逾期状态和创建时间排序规则。

#### Scenario: 两个区域均有任务

- **WHEN** 「有 Doing 时只显示 Doing」关闭，且 HUD 显示范围内同时存在 Doing 和 Todo 任务
- **THEN** HUD 先展示 Doing 区域，再展示 Todo 区域，且 Doing 区域中的 low 优先级任务仍排在所有 Todo 任务之前

#### Scenario: 只有一个区域有任务

- **WHEN** HUD 显示范围内只有 Doing 或只有 Todo 任务
- **THEN** HUD 只展示有任务的区域，不展示空区域

#### Scenario: 完成 Doing 任务

- **WHEN** Doing 任务被标记为 Done
- **THEN** 任务从 HUD 中消失，HUD 重新应用显示范围、分区和条数上限

### Requirement: 条数上限跨区域生效

HUD SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间）。条数上限 MUST 只作用于 HUD 实际渲染的任务集合：「有 Doing 时只显示 Doing」开启且存在 Doing 任务时作用于 Doing 任务，否则先保留 Doing 区域任务、再保留 Todo 区域任务。

#### Scenario: 聚焦 Doing 时截断 Doing

- **WHEN** 「有 Doing 时只显示 Doing」开启，Doing 任务数量超过 N
- **THEN** HUD 只展示按区域内排序规则排列的前 N 个 Doing 任务

#### Scenario: Doing 任务占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量不少于 N
- **THEN** HUD 只展示按区域内排序规则排列的前 N 个 Doing 任务，不展示 Todo 区域

#### Scenario: Doing 任务未占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量少于 N 且 Todo 任务数量超过剩余容量
- **THEN** HUD 展示全部 Doing 任务和按区域内排序规则排列的 Todo 任务，合计不超过 N 条
