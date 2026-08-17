## Purpose

定义 TodoPin 任务的 Todo、Doing、Done 三态模型、状态转换、旧数据兼容和跨 CLI/MCP 的状态输出契约，确保任务进度在各入口之间保持一致。

## ADDED Requirements

### Requirement: 三态任务状态

任务 SHALL 恰好处于 `todo`、`doing`、`done` 三种状态之一；新建任务默认处于 `todo`，且 Todo 与 Doing 均属于未完成状态。

#### Scenario: 新建任务默认为 Todo
- **WHEN** 用户通过任一创建入口新建任务且未指定状态
- **THEN** 任务状态为 `todo`，`isCompleted` 为 false

#### Scenario: Doing 仍属于未完成
- **WHEN** 任务状态为 `doing`
- **THEN** 任务仍被视为未完成，可出现在默认任务列表和 HUD 中

#### Scenario: Done 表示已完成
- **WHEN** 任务状态为 `done`
- **THEN** 任务的 `isCompleted` 为 true，且不出现在默认未完成任务结果中

### Requirement: 状态转换

系统 SHALL 支持 Todo、Doing、Done 之间的任务状态转换：Todo 可进入 Doing 或 Done，Doing 可进入 Todo 或 Done，Done 可恢复为 Todo；进入 Done 时 MUST 记录完成时间，离开 Done 时 MUST 清除完成状态。

#### Scenario: Todo 开始处理
- **WHEN** Todo 任务被设置为 Doing
- **THEN** 任务状态变为 `doing`，仍未完成

#### Scenario: Doing 完成
- **WHEN** Doing 任务被标记完成
- **THEN** 任务状态变为 `done`，并记录完成时间

#### Scenario: Doing 暂停
- **WHEN** Doing 任务被恢复为未完成
- **THEN** 任务状态变为 `todo`，完成时间为空

#### Scenario: Done 恢复
- **WHEN** Done 任务被恢复为未完成
- **THEN** 任务状态变为 `todo`，完成时间为空

### Requirement: 旧任务数据兼容

系统 SHALL 继续读取缺少 `status` 字段的既有任务数据：`completedAt` 有值的旧任务 MUST 映射为 `done`，`completedAt` 为空的旧任务 MUST 映射为 `todo`，且既有任务标题、时间、提醒、优先级、截止时间和描述不得丢失。

#### Scenario: 读取旧的未完成任务
- **WHEN** 存储文件中的任务没有 `status` 且 `completedAt` 为空
- **THEN** 任务被读取为 `todo`，其他字段保持不变

#### Scenario: 读取旧的已完成任务
- **WHEN** 存储文件中的任务没有 `status` 且 `completedAt` 有值
- **THEN** 任务被读取为 `done`，并保留原完成时间

### Requirement: 状态输出兼容

面向 CLI 和 MCP 的任务对象 MUST 输出 `status` 字段，并继续输出既有的 `completedAt` 与 `isCompleted` 字段；`isCompleted` MUST 与 `status == "done"` 保持一致。

#### Scenario: 输出 Doing 任务
- **WHEN** CLI 或 MCP 返回一个 Doing 任务
- **THEN** 任务对象包含 `"status": "doing"` 和 `"isCompleted": false`

#### Scenario: 输出 Done 任务
- **WHEN** CLI 或 MCP 返回一个 Done 任务
- **THEN** 任务对象包含 `"status": "done"` 和 `"isCompleted": true`
