## MODIFIED Requirements

### Requirement: 查询任务

`todopin-cli list` SHALL 默认列出全部未完成任务（按优先级→截止日期排序）；`--all` 时列出全部任务（含已完成）。

#### Scenario: 默认列出未完成

- **WHEN** 用户执行 `todopin-cli list`
- **THEN** 输出全部未完成任务，按优先级（高→中→低）→ 截止日期升序排列，不包含已完成任务

#### Scenario: 列出全部

- **WHEN** 用户执行 `todopin-cli list --all`
- **THEN** 输出全部任务，包含已完成任务及其完成时间

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；所有日期 MUST 使用 ISO8601 编码。

#### Scenario: JSON 列表输出

- **WHEN** 用户执行 `todopin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、title、createdAt、completedAt、source、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 字段，日期为 ISO8601 字符串

#### Scenario: JSON 成功结果

- **WHEN** 用户执行 `todopin-cli add "任务" --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true` 与结果数据，退出码为 0

#### Scenario: JSON 失败结果

- **WHEN** 用户执行带 `--json` 的命令且操作失败（如 id 不存在）
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零
