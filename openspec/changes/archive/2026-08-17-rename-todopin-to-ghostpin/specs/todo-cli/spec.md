## MODIFIED Requirements

### Requirement: 查询任务

`ghostpin-cli list` SHALL 默认列出全部未完成任务（状态为 Todo 或 Doing，按状态分组后按优先级→截止日期排序）；`--all` 时列出全部任务（含已完成）。旧可执行名称 `todopin-cli` MUST NOT 继续作为发行别名提供。

#### Scenario: 默认列出未完成
- **WHEN** 用户执行 `ghostpin-cli list`
- **THEN** 输出全部 Todo 与 Doing 任务，先输出 Doing 再输出 Todo；每组按优先级（高→中→低）→截止日期升序排列，不包含 Done 任务

#### Scenario: 列出全部
- **WHEN** 用户执行 `ghostpin-cli list --all`
- **THEN** 输出全部任务，包含已完成任务及其完成时间

#### Scenario: 旧命令不再分发
- **WHEN** 用户检查 GhostPin App Bundle 的命令行程序
- **THEN** 其中存在 `ghostpin-cli`，不存在作为兼容别名的 `todopin-cli`

### Requirement: 新增任务

`ghostpin-cli add <title>` SHALL 新增一条 Todo 任务；`--reminder` 与 `--due` 以 ISO8601 字符串分别设置提醒时间和截止时间，`--priority` 接受 `high`、`medium`、`low` 且默认 `medium`，`--description` 设置描述。CLI 不解析自然语言时间。

#### Scenario: 新增纯文本任务
- **WHEN** 用户执行 `ghostpin-cli add "修复 Redis 问题"`
- **THEN** 创建一条标题为“修复 Redis 问题”、优先级为 `medium` 的 Todo 任务，无提醒、截止时间和描述

#### Scenario: 新增带提醒的任务
- **WHEN** 用户执行 `ghostpin-cli add "开会" --reminder "2026-08-14T09:00:00+08:00"`
- **THEN** 创建任务并保存给定的提醒时间，其他可选字段使用默认值

#### Scenario: 新增完整字段任务
- **WHEN** 用户执行 `ghostpin-cli add "开会" --reminder "2026-08-14T09:00:00+08:00" --priority high --due "2026-08-14T10:00:00+08:00" --description "准备周报"`
- **THEN** 创建任务并保存给定提醒、优先级、截止时间和描述

#### Scenario: 新增时优先级非法
- **WHEN** 用户执行 `ghostpin-cli add "任务" --priority urgent`
- **THEN** 命令报错并以非零退出码结束，不创建任务

### Requirement: 完成与恢复任务

`ghostpin-cli done <id>` SHALL 将指定任务标记为 Done；`ghostpin-cli undone <id>` SHALL 将指定任务恢复为 Todo。

#### Scenario: 完成已有任务
- **WHEN** 用户执行 `ghostpin-cli done <任务 id>`
- **THEN** 该任务被标记为 Done，从默认 `list` 结果中消失

#### Scenario: 恢复已完成任务
- **WHEN** 用户执行 `ghostpin-cli undone <任务 id>`
- **THEN** 该任务恢复为 Todo，重新出现在默认 `list` 结果中

#### Scenario: Doing 任务恢复为 Todo
- **WHEN** 用户对 Doing 任务执行 `ghostpin-cli undone <任务 id>`
- **THEN** 该任务恢复为 Todo，仍出现在默认 `list` 结果中

### Requirement: 设置 Doing

`ghostpin-cli doing <id>` SHALL 将指定任务标记为 Doing；任务不存在或 id 无效时 MUST 输出错误、以非零退出码结束，且不得修改任务数据。

#### Scenario: 设置已有任务为 Doing
- **WHEN** 用户执行 `ghostpin-cli doing <任务 id>`
- **THEN** 任务状态变为 Doing，并继续出现在默认 `list` 结果中

#### Scenario: 设置不存在任务为 Doing
- **WHEN** 用户对不存在的 id 执行 `ghostpin-cli doing <id>`
- **THEN** CLI 输出错误并以非零退出码结束，任务数据不变

### Requirement: 修改任务

`ghostpin-cli update <id>` SHALL 支持 `--title` 修改标题、`--reminder` 修改提醒时间、`--clear-reminder` 清除提醒时间、`--priority` 修改优先级、`--due` 修改截止时间、`--clear-due` 清除截止时间、`--description` 修改描述；以上 MUST 至少指定一项，只提供部分参数时其他字段 MUST 保持不变。

#### Scenario: 修改标题保留提醒
- **WHEN** 用户执行 `ghostpin-cli update <id> --title "新标题"`
- **THEN** 任务标题被更新，原提醒、优先级、截止时间和描述保持不变

#### Scenario: 清除提醒时间
- **WHEN** 用户执行 `ghostpin-cli update <id> --clear-reminder`
- **THEN** 该任务提醒时间被移除，其他字段保持不变

#### Scenario: 修改优先级、截止时间和描述
- **WHEN** 用户执行 `ghostpin-cli update <id> --priority low --due "2026-08-20T18:00:00+08:00" --description "延后处理"`
- **THEN** 该任务的优先级、截止时间和描述被更新，其他字段保持不变

#### Scenario: 清除截止时间
- **WHEN** 用户执行 `ghostpin-cli update <id> --clear-due`
- **THEN** 该任务截止时间被移除，其他字段保持不变

#### Scenario: 未指定任何修改项
- **WHEN** 用户执行 `ghostpin-cli update <id>` 且未附带任何修改参数
- **THEN** 命令报错并以非零退出码结束，任务数据不变

### Requirement: 删除任务

`ghostpin-cli delete <id>` SHALL 删除指定任务。

#### Scenario: 删除已有任务
- **WHEN** 用户执行 `ghostpin-cli delete <任务 id>`
- **THEN** 该任务从存储中移除

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/doing/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；所有日期 MUST 使用 ISO8601 编码；任务对象 MUST 包含 `status` 字段并保留 `completedAt` 与 `isCompleted` 字段。

#### Scenario: JSON 列表输出
- **WHEN** 用户执行 `ghostpin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、title、createdAt、status、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 字段，日期为 ISO8601 字符串

#### Scenario: JSON 成功设置 Doing
- **WHEN** 用户执行 `ghostpin-cli doing "<任务 id>" --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`、状态为 `"doing"` 的结果数据，退出码为 0

#### Scenario: JSON 成功结果
- **WHEN** 用户执行 `ghostpin-cli add "任务" --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true` 与结果数据，退出码为 0

#### Scenario: JSON 失败结果
- **WHEN** 用户执行带 `--json` 的命令且操作失败（如 id 不存在）
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零

### Requirement: 输入校验与错误处理

CLI SHALL 校验参数：无效或不存在的 id、非法 ISO8601 提醒或截止时间、非法优先级、缺失必选参数 MUST 输出错误信息并以非零退出码结束，且不得修改任务数据。

#### Scenario: id 不存在
- **WHEN** 用户对不存在的 id 执行 doing/done/undone/update/delete
- **THEN** 输出错误信息，退出码非零，任务数据不变

#### Scenario: 非法提醒时间
- **WHEN** 用户执行 `ghostpin-cli add "任务" --reminder "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

#### Scenario: 非法截止时间
- **WHEN** 用户执行 `ghostpin-cli add "任务" --due "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

#### Scenario: 非法优先级
- **WHEN** 用户执行 `ghostpin-cli update <id> --priority urgent`
- **THEN** 输出错误信息，退出码非零，任务数据不变

### Requirement: 独立运行

CLI SHALL 可在 App 未运行时独立工作，直接读写 `todos.json`；与 App 共用 `~/Library/Application Support/GhostPin/todos.json` 及相同数据格式，并遵守产品身份规格定义的旧数据迁移行为。

#### Scenario: App 未运行时操作
- **WHEN** GhostPin App 未运行且用户执行 `ghostpin-cli add "任务"`
- **THEN** 任务写入 `~/Library/Application Support/GhostPin/todos.json`，App 下次启动时可见

#### Scenario: CLI 首次触发旧数据迁移
- **WHEN** App 未运行、新任务文件不存在且旧 TodoPin 任务文件存在时，用户首次执行 `ghostpin-cli list`
- **THEN** CLI 迁移旧数据后从 GhostPin 任务文件返回原有任务

### Requirement: 随应用分发

`ghostpin-cli` SHALL 随 GhostPin 的 DMG 一起分发；安装完成后，`GhostPin.app` 的 `Contents/MacOS/` 目录内 MUST 存在与主程序出自同一次 release 构建的可执行 `ghostpin-cli`，用户无需构建源码即可独立管理任务。

#### Scenario: 全新安装后 CLI 立即可用
- **WHEN** 用户从 DMG 将 `GhostPin.app` 安装到 `/Applications`
- **THEN** `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli` 存在且可执行

#### Scenario: App 未运行时 CLI 独立工作
- **WHEN** GhostPin App 未运行且用户执行 App Bundle 内的 `ghostpin-cli add`
- **THEN** 任务写入 `~/Library/Application Support/GhostPin/todos.json`，与 App 共用同一存储

#### Scenario: CLI 与主程序版本一致
- **WHEN** 用户安装某一版本的 GhostPin DMG
- **THEN** App Bundle 内的 `ghostpin-cli` 与该版本主程序出自同一次 release 构建，行为与发行说明一致

#### Scenario: 非标准安装位置
- **WHEN** 用户将 `GhostPin.app` 安装到 `/Applications` 以外的位置
- **THEN** `ghostpin-cli` 仍随 App Bundle 一起存在并可通过其完整路径执行

### Requirement: 命令级帮助

`ghostpin-cli` 根命令以及 `list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 命令 MUST 同时支持 `-h` 与 `--help`；帮助请求 SHALL 在业务参数校验和任务存储访问前处理，输出对应命令的用法、位置参数和可用选项，以退出码 0 结束且不得修改任务数据。

#### Scenario: 根命令帮助
- **WHEN** 用户执行 `ghostpin-cli --help` 或 `ghostpin-cli -h`
- **THEN** CLI 输出命令列表与全局选项，以退出码 0 结束

#### Scenario: 每条子命令均可查看帮助
- **WHEN** 用户对 `list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 中任一命令执行 `ghostpin-cli <command> --help` 或 `ghostpin-cli <command> -h`
- **THEN** CLI 输出该命令的专属用法、位置参数和选项，以退出码 0 结束，不要求提供 id、标题或其他业务参数

#### Scenario: 更新命令展示截止日期选项
- **WHEN** 用户执行 `ghostpin-cli update --help`
- **THEN** 帮助包含 `--due <ISO8601>` 与 `--clear-due`，并说明未指定的任务字段保持不变

#### Scenario: 帮助请求无数据副作用
- **WHEN** 用户在任务文件不存在或内容不可读时执行任一帮助请求
- **THEN** CLI 仍正常输出帮助并以退出码 0 结束，不创建、读取或修改任务文件
