## Purpose

定义 `todopin-cli` 命令行工具的命令集、显式参数与输出契约，使 Agent（OpenCode、Codex 等）能够通过 CLI 稳定地查询与增删改任务，不依赖 App 是否运行。

## Requirements

### Requirement: 查询任务

`todopin-cli list` SHALL 默认列出全部未完成任务（按创建时间倒序）；`--all` 时列出全部任务（含已完成）。

#### Scenario: 默认列出未完成

- **WHEN** 用户执行 `todopin-cli list`
- **THEN** 输出全部未完成任务，按创建时间从新到旧排列，不包含已完成任务

#### Scenario: 列出全部

- **WHEN** 用户执行 `todopin-cli list --all`
- **THEN** 输出全部任务，包含已完成任务及其完成时间

### Requirement: 新增任务

`todopin-cli add <title>` SHALL 新增一条任务；`--reminder` 参数以 ISO8601 字符串显式设置提醒时间。CLI 不解析自然语言时间。

#### Scenario: 新增纯文本任务

- **WHEN** 用户执行 `todopin-cli add "修复 Redis 问题"`
- **THEN** 创建一条标题为"修复 Redis 问题"的任务，无提醒时间

#### Scenario: 新增带提醒的任务

- **WHEN** 用户执行 `todopin-cli add "开会" --reminder "2026-08-14T09:00:00+08:00"`
- **THEN** 创建任务并保存给定的提醒时间

### Requirement: 完成与恢复任务

`todopin-cli done <id>` SHALL 将指定任务标记为完成；`todopin-cli undone <id>` SHALL 恢复指定任务为未完成。

#### Scenario: 完成已有任务

- **WHEN** 用户执行 `todopin-cli done <任务 id>`
- **THEN** 该任务被标记完成，从默认 `list` 结果中消失

#### Scenario: 恢复已完成任务

- **WHEN** 用户执行 `todopin-cli undone <任务 id>`
- **THEN** 该任务恢复为未完成，重新出现在默认 `list` 结果中

### Requirement: 修改任务

`todopin-cli update <id>` SHALL 支持 `--title` 修改标题、`--reminder` 修改提醒时间、`--clear-reminder` 清除提醒时间；三者 MUST 至少指定一个。

#### Scenario: 修改标题保留提醒

- **WHEN** 用户执行 `todopin-cli update <id> --title "新标题"`
- **THEN** 任务标题被更新，原提醒时间保持不变

#### Scenario: 清除提醒时间

- **WHEN** 用户执行 `todopin-cli update <id> --clear-reminder`
- **THEN** 该任务的提醒时间被移除

#### Scenario: 未指定任何修改项

- **WHEN** 用户执行 `todopin-cli update <id>` 且未附带任何修改参数
- **THEN** 命令报错并以非零退出码结束，任务数据不变

### Requirement: 删除任务

`todopin-cli delete <id>` SHALL 删除指定任务。

#### Scenario: 删除已有任务

- **WHEN** 用户执行 `todopin-cli delete <任务 id>`
- **THEN** 该任务从存储中移除

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；所有日期 MUST 使用 ISO8601 编码。

#### Scenario: JSON 列表输出

- **WHEN** 用户执行 `todopin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、title、createdAt、completedAt、source、reminderAt、reminderSentAt、isCompleted 字段，日期为 ISO8601 字符串

#### Scenario: JSON 成功结果

- **WHEN** 用户执行 `todopin-cli add "任务" --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true` 与结果数据，退出码为 0

#### Scenario: JSON 失败结果

- **WHEN** 用户执行带 `--json` 的命令且操作失败（如 id 不存在）
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零

### Requirement: 输入校验与错误处理

CLI SHALL 校验参数：无效的 id、非法 ISO8601 日期、缺失必选参数 MUST 输出错误信息并以非零退出码结束，且不得修改任务数据。

#### Scenario: id 不存在

- **WHEN** 用户对不存在的 id 执行 done/undone/update/delete
- **THEN** 输出错误信息，退出码非零，任务数据不变

#### Scenario: 非法提醒时间

- **WHEN** 用户执行 `todopin-cli add "任务" --reminder "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

### Requirement: 独立运行

CLI SHALL 可在 App 未运行时独立工作，直接读写 `todos.json`；与 App 共用同一存储路径与格式。

#### Scenario: App 未运行时操作

- **WHEN** TodoPin App 未运行且用户执行 `todopin-cli add "任务"`
- **THEN** 任务写入 `~/Library/Application Support/TodoPin/todos.json`，App 下次启动时可见
