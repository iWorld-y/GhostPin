# Spec Delta

## ADDED Requirements

### Requirement: 四象限自动分类

macOS 四象限视图 SHALL 将所选范围内每条未完成任务恰好显示一次。高优先级为重要，中、低优先级为一般。已逾期或本地今天到期为紧急，其余为不紧急。

#### Scenario: 按重要程度和紧急程度入格

- **WHEN** 当前范围内同时存在高优先级今天到期、高优先级无截止时间、中优先级已逾期、低优先级明天到期的任务
- **THEN** 四条任务依次出现在左上「优先处理」、右上「安排时间」、左下「及时处理」、右下「稍后处理」

#### Scenario: 跨日和任务变更

- **WHEN** 明天零点到期的任务进入到期日，或 CLI 修改优先级或截止时间
- **THEN** HUD 按当前本地日期和最新任务值更新所属象限

### Requirement: 四象限完整展示

四象限视图 SHALL 显示当前范围内全部 Todo 和 Doing，忽略列表条数上限及 Doing 聚焦。每格 SHALL 展示任务数并独立滚动，Doing 排在 Todo 前面，同状态沿用列表排序。空格保留标题、零计数和空状态。

#### Scenario: 范围筛选与独立滚动

- **WHEN** 选择「今天新增」，列表上限为 3 且 Doing 聚焦开启，今天创建的 6 条未完成任务集中在同一格
- **THEN** 此格可滚动查看全部 6 条，其他三格保留空状态，昨天创建的任务不计入任何象限

#### Scenario: 状态推进与计数

- **WHEN** 用户在四象限中通过任务圆钮将 Todo 推进到 Doing，随后按现有冷却规则推进到 Done
- **THEN** 第一次推进只改变格内分区，第二次从该格移除任务，格内计数和头部状态计数同步更新

## MODIFIED Requirements

### Requirement: 未完成任务分区

列表视图 SHALL 将未完成任务分为 Doing 和 Todo 两个区域；当「有 Doing 时只显示 Doing」关闭时，Doing 区域 MUST 位于 Todo 区域上方，空区域 MUST 不展示。当该偏好开启且存在 Doing 任务时，列表视图 MUST 只展示 Doing 区域。每个区域内部 SHALL 沿用现有优先级、截止时间、逾期状态和创建时间排序规则。

#### Scenario: 两个区域均有任务

- **WHEN** 「有 Doing 时只显示 Doing」关闭，且 列表视图 显示范围内同时存在 Doing 和 Todo 任务
- **THEN** 列表视图 先展示 Doing 区域，再展示 Todo 区域，且 Doing 区域中的 low 优先级任务仍排在所有 Todo 任务之前

#### Scenario: 只有一个区域有任务

- **WHEN** 列表视图 显示范围内只有 Doing 或只有 Todo 任务
- **THEN** 列表视图 只展示有任务的区域，不展示空区域

#### Scenario: 完成 Doing 任务

- **WHEN** Doing 任务被标记为 Done
- **THEN** 任务从 列表视图 中消失，列表视图 重新应用显示范围、分区和条数上限

### Requirement: 条数上限跨区域生效

列表视图 SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间）。条数上限 MUST 只作用于 列表视图 实际渲染的任务集合：「有 Doing 时只显示 Doing」开启且存在 Doing 任务时作用于 Doing 任务，否则先保留 Doing 区域任务、再保留 Todo 区域任务。

#### Scenario: 聚焦 Doing 时截断 Doing

- **WHEN** 「有 Doing 时只显示 Doing」开启，Doing 任务数量超过 N
- **THEN** 列表视图 只展示按区域内排序规则排列的前 N 个 Doing 任务

#### Scenario: Doing 任务占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量不少于 N
- **THEN** 列表视图 只展示按区域内排序规则排列的前 N 个 Doing 任务，不展示 Todo 区域

#### Scenario: Doing 任务未占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量少于 N 且 Todo 任务数量超过剩余容量
- **THEN** 列表视图 展示全部 Doing 任务和按区域内排序规则排列的 Todo 任务，合计不超过 N 条

### Requirement: 条数上限
列表视图 SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间），超出部分不显示。

#### Scenario: 超出上限截断
- **WHEN** 列表中未完成任务数量超过设定上限
- **THEN** HUD 只展示前 N 条，其余不显示

### Requirement: 完成即消失
任务被标记完成后 SHALL 立即从 HUD 消失。

#### Scenario: 完成任务后消失
- **WHEN** 用户在交互模式下勾选完成一条任务
- **THEN** 该任务立即从 HUD 移除，HUD 更新计数，并按当前视图的范围、分类与条数规则重新展示
