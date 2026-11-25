# Spec Delta

## MODIFIED Requirements

### Requirement: 未完成任务分区

列表视图 SHALL 将未完成任务分为 Doing 和 Todo 两个区域；当「有 Doing 时只显示 Doing」关闭时，Doing 区域 MUST 位于 Todo 区域上方，空区域 MUST 不展示。当该偏好开启且存在 Doing 任务时，列表视图 MUST 只展示 Doing 区域。每个区域内部 SHALL 沿用统一的有效四象限投影排序规则（`Q1 → Q2 → Q3 → Q4`，同象限按截止日期升序再按创建时间倒序）。

#### Scenario: 两个区域均有任务

- **WHEN** 「有 Doing 时只显示 Doing」关闭，且列表视图显示范围内同时存在 Doing（Q4「一般 · 不紧急」）和 Todo（Q1「重要 · 紧急」）任务
- **THEN** 列表视图先展示 Doing 区域，再展示 Todo 区域，且 Doing 区域中的 Q4 任务仍排在所有 Todo 任务之前

#### Scenario: 只有一个区域有任务

- **WHEN** 列表视图显示范围内只有 Doing 或只有 Todo 任务
- **THEN** 列表视图只展示有任务的区域，不展示空区域

#### Scenario: 完成 Doing 任务

- **WHEN** Doing 任务被标记为 Done
- **THEN** 任务从列表视图中消失，列表视图重新应用显示范围、分区和条数上限

#### Scenario: 同分区内按四象限投影排序

- **WHEN** Todo 区域内同时存在 Q1、Q2、Q3、Q4 任务
- **THEN** Todo 区域按 Q1 → Q2 → Q3 → Q4 依次展示

### Requirement: 四象限自动分类

macOS 四象限视图 SHALL 将所选范围内每条未完成任务恰好显示一次。重要程度由任务的 `important` 决定（`true` 为重要，`false` 为一般）；紧急程度由任务的 `urgent` 与 `dueAt` 共同决定（`urgent == true`，或 `dueAt` 已逾期/本地今天到期，均为紧急；其余为不紧急）。

#### Scenario: 按重要程度和紧急程度入格

- **WHEN** 当前范围内同时存在以下四条任务：`important: true, urgent: true`（无截止日期）、`important: true, urgent: false`（无截止日期）、`important: false, urgent: false`（今天到期）、`important: false, urgent: false`（明天到期）
- **THEN** 四条任务依次出现在左上「优先处理」、右上「安排时间」、左下「及时处理」、右下「稍后处理」

#### Scenario: 跨日和任务变更

- **WHEN** 一条 `urgent: false` 且明天零点后到期的任务进入到期日，或 CLI 修改 `important`、`urgent` 或 `dueAt`
- **THEN** HUD 按当前本地日期和最新任务值更新所属象限及列表顺序
