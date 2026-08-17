## MODIFIED Requirements

### Requirement: 查询任务

`todopin-cli list` SHALL 默认列出全部未完成任务（状态为 Todo 或 Doing，按状态分组后按优先级→截止日期排序）；`--all` 时列出全部任务（含已完成）。

#### Scenario: 默认列出未完成

- **WHEN** 用户执行 `todopin-cli list`
- **THEN** 输出全部 Todo 与 Doing 任务，先输出 Doing 再输出 Todo；每组按优先级（高→中→低）→截止日期升序排列，不包含 Done 任务

#### Scenario: 列出全部

- **WHEN** 用户执行 `todopin-cli list --all`
- **THEN** 输出全部任务，包含 Todo、Doing、Done 任务及其完成时间

### Requirement: 完成与恢复任务

`todopin-cli done <id>` SHALL 将指定任务标记为 Done；`todopin-cli undone <id>` SHALL 将指定任务恢复为 Todo。

#### Scenario: 完成已有任务

- **WHEN** 用户执行 `todopin-cli done <任务 id>`
- **THEN** 该任务被标记为 Done，从默认 `list` 结果中消失

#### Scenario: 恢复已完成任务

- **WHEN** 用户执行 `todopin-cli undone <任务 id>`
- **THEN** 该任务恢复为 Todo，重新出现在默认 `list` 结果中

#### Scenario: Doing 任务恢复为 Todo

- **WHEN** 用户对 Doing 任务执行 `todopin-cli undone <任务 id>`
- **THEN** 该任务恢复为 Todo，仍出现在默认 `list` 结果中

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/doing/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；所有日期 MUST 使用 ISO8601 编码；任务对象 MUST 包含 `status` 字段并保留 `completedAt` 与 `isCompleted` 字段。

#### Scenario: JSON 列表输出

- **WHEN** 用户执行 `todopin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、title、createdAt、status、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 字段，日期为 ISO8601 字符串

#### Scenario: JSON 成功结果

- **WHEN** 用户执行 `todopin-cli doing "<任务 id>" --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`、状态为 `"doing"` 的结果数据，退出码为 0

#### Scenario: JSON 失败结果

- **WHEN** 用户执行带 `--json` 的命令且操作失败（如 id 不存在）
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零

## ADDED Requirements

### Requirement: 设置 Doing

`todopin-cli doing <id>` SHALL 将指定任务标记为 Doing；任务不存在或 id 无效时 MUST 输出错误、以非零退出码结束，且不得修改任务数据。

#### Scenario: 设置已有任务为 Doing

- **WHEN** 用户执行 `todopin-cli doing <任务 id>`
- **THEN** 任务状态变为 Doing，并继续出现在默认 `list` 结果中

#### Scenario: 设置不存在任务为 Doing

- **WHEN** 用户对不存在的 id 执行 `todopin-cli doing <id>`
- **THEN** CLI 输出错误并以非零退出码结束，任务数据不变

### Requirement: 输入校验与错误处理

CLI SHALL 校验参数：无效的 id、非法 ISO8601 日期、缺失必选参数 MUST 输出错误信息并以非零退出码结束，且不得修改任务数据。

#### Scenario: id 不存在

- **WHEN** 用户对不存在的 id 执行 doing/done/undone/update/delete
- **THEN** 输出错误信息，退出码非零，任务数据不变

#### Scenario: 非法提醒时间

- **WHEN** 用户执行 `todopin-cli add "任务" --reminder "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

### Requirement: 独立运行

CLI SHALL 可在 App 未运行时独立工作，直接读写 `todos.json`；与 App 共用同一存储路径与格式。

#### Scenario: App 未运行时操作

- **WHEN** TodoPin App 未运行且用户执行 `todopin-cli add "任务"`
- **THEN** 任务写入 `~/Library/Application Support/TodoPin/todos.json`，App 下次启动时可见

### Requirement: 随应用分发

todopin-cli SHALL 随 TodoPin 的 DMG 一起分发并安装：安装完成后，TodoPin.app 的 Contents/MacOS/ 目录内存在可执行的 todopin-cli，与主程序出自同一次 release 构建，用户无需另行构建即可通过 CLI 与 MCP server 操作任务。

#### Scenario: 全新安装后 CLI 立即可用

- **WHEN** 用户从 DMG 将 TodoPin.app 安装到 /Applications 且从未构建过源码
- **THEN** /Applications/TodoPin.app/Contents/MacOS/todopin-cli 存在且可执行，以 mcp 子命令启动时 MCP server 正常握手

#### Scenario: App 未运行时 CLI 独立工作

- **WHEN** TodoPin App 未运行且用户执行 bundle 内的 todopin-cli add
- **THEN** 任务写入 ~/Library/Application Support/TodoPin/todos.json，与 App 共用同一存储

#### Scenario: CLI 与主程序版本一致

- **WHEN** 用户安装某一版本的 TodoPin DMG
- **THEN** bundle 内 todopin-cli 与该版本主程序出自同一次 release 构建，行为与发行说明一致

#### Scenario: 非标准安装位置

- **WHEN** 用户将 TodoPin.app 安装到 /Applications 以外的位置
- **THEN** todopin-cli 仍随 bundle 一起存在，MCP 注册路径随之指向新位置
