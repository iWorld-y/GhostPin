## MODIFIED Requirements

### Requirement: 状态输出兼容

CLI 返回的任务对象 MUST 输出 `status` 字段，并继续输出既有的 `completedAt` 与 `isCompleted` 字段；`isCompleted` MUST 与 `status == "done"` 保持一致。

#### Scenario: 输出 Doing 任务
- **WHEN** CLI 返回一个 Doing 任务
- **THEN** 任务对象包含 `"status": "doing"` 和 `"isCompleted": false`

#### Scenario: 输出 Done 任务
- **WHEN** CLI 返回一个 Done 任务
- **THEN** 任务对象包含 `"status": "done"` 和 `"isCompleted": true`
