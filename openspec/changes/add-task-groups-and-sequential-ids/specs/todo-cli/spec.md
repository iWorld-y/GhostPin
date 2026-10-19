# Spec Delta

## MODIFIED Requirements

### Requirement: 查询任务

`ghostpin-cli list` SHALL 默认列出全部分组的未完成任务（状态为 Todo 或 Doing，按状态分组后按优先级、截止日期排序）；`--all` 时列出全部任务（含已完成）。`--group <组名>` SHALL 筛选指定组，并支持与 `--all`、`--json` 组合；筛选 MUST 保留原列表相对排序。旧可执行名称 `todopin-cli` MUST NOT 继续作为发行别名提供。

#### Scenario: 默认列出未完成

- **WHEN** 用户执行 `ghostpin-cli list`
- **THEN** 输出全部组的 Todo 与 Doing 任务，先输出 Doing 再输出 Todo；每个状态内按优先级（高、中、低）、截止日期升序排列，不包含 Done 任务

#### Scenario: 列出全部

- **WHEN** 用户执行 `ghostpin-cli list --all`
- **THEN** 输出全部分组的全部任务，包含已完成任务及其完成时间

#### Scenario: 旧命令不再分发

- **WHEN** 用户检查 GhostPin App Bundle 的命令行程序
- **THEN** 其中存在 `ghostpin-cli`，不存在作为兼容别名的 `todopin-cli`

#### Scenario: 按组列出未完成任务

- **WHEN** 用户执行 `ghostpin-cli list --group GhostPin --json`
- **THEN** 返回只包含 `GhostPin` 组未完成任务的 JSON 数组

#### Scenario: 按组列出全部任务

- **WHEN** 用户执行 `ghostpin-cli list --group 默认 --all --json`
- **THEN** 返回 `默认` 组包括 Done 在内的全部任务，按原全量列表相对顺序排列

#### Scenario: 查询没有成员的组

- **WHEN** 用户查询一个没有任务的非空组名
- **THEN** 返回空列表，退出码为 0

### Requirement: 新增任务

`ghostpin-cli add <title> --group <组名>` SHALL 新增一条 Todo 任务，组别 MUST 显式提供且非空，不能自动补 `默认`。`--reminder` 与 `--due` 以 ISO8601 字符串分别设置提醒时间和截止时间，`--priority` 接受 `high`、`medium`、`low` 且默认 `medium`，`--description` 设置描述。CLI 不解析自然语言时间。

#### Scenario: 新增纯文本任务

- **WHEN** 用户执行 `ghostpin-cli add "修复 Redis 问题" --group 默认`
- **THEN** 创建一条组别为 `默认`、标题为 "修复 Redis 问题"、优先级为 `medium` 的 Todo 任务，无提醒、截止时间和描述

#### Scenario: 新增带提醒的任务

- **WHEN** 用户执行 `ghostpin-cli add "开会" --group 默认 --reminder "2026-08-14T09:00:00+08:00"`
- **THEN** 创建任务并保存组别和给定的提醒时间，其他可选字段使用默认值

#### Scenario: 新增完整字段任务

- **WHEN** 用户执行 `ghostpin-cli add "开会" --group GhostPin --reminder "2026-08-14T09:00:00+08:00" --priority high --due "2026-08-14T10:00:00+08:00" --description "准备周报"`
- **THEN** 创建任务并保存给定组别、提醒、优先级、截止时间和描述

#### Scenario: 新增时优先级非法

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group 默认 --priority urgent`
- **THEN** 命令报错并以非零退出码结束，不创建任务

#### Scenario: 新增缺少组别

- **WHEN** 用户执行 `ghostpin-cli add "任务"`，即使 `默认` 已存在
- **THEN** 命令提示必须指定 `--group`，以非零退出码结束，不访问或迁移任务文件

#### Scenario: 显式指定空组别

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group "   "`
- **THEN** 命令报错，任务集合与下一编号保持不变

### Requirement: 修改任务

`ghostpin-cli update <id>` SHALL 支持 `--title` 修改标题、`--reminder` 修改提醒时间、`--clear-reminder` 清除提醒时间、`--priority` 修改优先级、`--due` 修改截止时间、`--clear-due` 清除截止时间、`--description` 修改描述，以及 `--group` 修改组别；以上 MUST 至少指定一项。只提供部分参数时其他字段 MUST 保持不变，且 MUST 保留锁内最新任务中未请求修改的字段。

#### Scenario: 修改标题保留提醒

- **WHEN** 用户执行 `ghostpin-cli update 10000 --title "新标题"`
- **THEN** 任务标题被更新，原组别、提醒、优先级、截止时间和描述保持不变

#### Scenario: 清除提醒时间

- **WHEN** 用户执行 `ghostpin-cli update 10000 --clear-reminder`
- **THEN** 该任务的提醒时间被移除，其他字段保持不变

#### Scenario: 修改优先级、截止时间和描述

- **WHEN** 用户执行 `ghostpin-cli update 10000 --priority low --due "2026-08-20T18:00:00+08:00" --description "延后处理"`
- **THEN** 该任务的优先级、截止时间和描述被更新，其他字段保持不变

#### Scenario: 清除截止时间

- **WHEN** 用户执行 `ghostpin-cli update 10000 --clear-due`
- **THEN** 该任务的截止时间被移除，其他字段保持不变

#### Scenario: 未指定任何修改项

- **WHEN** 用户执行 `ghostpin-cli update 10000` 且未附带任何修改参数
- **THEN** 命令报错并以非零退出码结束，任务数据不变

#### Scenario: 修改任务组别

- **WHEN** 用户执行 `ghostpin-cli update 10000 --group GhostPin`
- **THEN** 任务组别变为 `GhostPin`，ID 和其他字段保持不变，不分配新编号

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/doing/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；所有日期 MUST 使用 ISO8601 编码。任务对象 MUST 输出整数 `id`、非空字符串 `group` 和 `status`，并保留 `completedAt` 与 `isCompleted` 等既有业务字段；不得将存储文档的版本与下一编号包装到 list 结果中。

#### Scenario: JSON 列表输出

- **WHEN** 用户执行 `ghostpin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、group、title、createdAt、status、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 字段，id 为整数，日期为 ISO8601 字符串

#### Scenario: JSON 成功设置 Doing

- **WHEN** 用户执行 `ghostpin-cli doing 10000 --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`，结果任务的 `id` 为整数 `10000`、状态为 `"doing"`，退出码为 0

#### Scenario: JSON 成功结果

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group 默认 --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`，`item` 中包含整数 ID 和 `"group": "默认"`，退出码为 0

#### Scenario: JSON 失败结果

- **WHEN** 用户执行带 `--json` 的命令且操作失败，例如 id 不存在
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零

#### Scenario: JSON 删除成功结果

- **WHEN** 用户执行 `ghostpin-cli delete 10000 --json` 且删除成功
- **THEN** 标准输出包含 `"ok": true` 和 `"id": 10000`，id 为整数

### Requirement: 输入校验与错误处理

CLI SHALL 校验参数：无效或不存在的整数 id、非法 ISO8601 提醒或截止时间、非法优先级、空组名和缺失必选参数 MUST 输出错误信息并以非零退出码结束，且不得修改任务数据。所有修改命令 MUST 接受数字 ID，拒绝 UUID 操作别名；无效输入不得消耗编号或触发存储迁移。

#### Scenario: id 不存在

- **WHEN** 用户对不存在的整数 id 执行 doing/done/undone/update/delete
- **THEN** 输出错误信息，退出码非零，任务数据不变

#### Scenario: 非法提醒时间

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group 默认 --reminder "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

#### Scenario: 非法截止时间

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group 默认 --due "not-a-date"`
- **THEN** 输出错误信息，退出码非零，不创建任务

#### Scenario: 非法优先级

- **WHEN** 用户执行 `ghostpin-cli update 10000 --priority urgent`
- **THEN** 输出错误信息，退出码非零，任务数据不变

#### Scenario: 非法 ID 表示

- **WHEN** 用户将 UUID、负数、小数或小于 `10000` 的值作为任务 id
- **THEN** 输出数字 ID 要求的错误说明，退出码非零，任务数据不变

### Requirement: 命令级帮助

`ghostpin-cli` 根命令以及 `list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 命令 MUST 同时支持 `-h` 与 `--help`；帮助请求 SHALL 在业务参数校验和任务存储访问前处理，输出对应命令的用法、位置参数和可用选项，以退出码 0 结束且不得修改任务数据。新增帮助 MUST 明示 `--group` 必填，列表和修改帮助 MUST 说明组别选项，ID 帮助 MUST 说明使用从 `10000` 开始的整数。

#### Scenario: 根命令帮助

- **WHEN** 用户执行 `ghostpin-cli --help` 或 `ghostpin-cli -h`
- **THEN** CLI 输出命令列表与全局选项，以退出码 0 结束

#### Scenario: 每条子命令均可查看帮助

- **WHEN** 用户对 `list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 中任一命令执行 `ghostpin-cli <command> --help` 或 `ghostpin-cli <command> -h`
- **THEN** CLI 输出该命令的专属用法、位置参数和选项，以退出码 0 结束，不要求提供 id、标题或其他业务参数

#### Scenario: 更新命令展示截止日期选项

- **WHEN** 用户执行 `ghostpin-cli update --help`
- **THEN** 帮助包含 `--due <ISO8601>`、`--clear-due` 和 `--group <组名>`，并说明未指定的任务字段保持不变

#### Scenario: 帮助请求无数据副作用

- **WHEN** 用户在任务文件不存在或内容不可读时执行任一帮助请求
- **THEN** CLI 仍正常输出帮助并以退出码 0 结束，不创建、读取或修改任务文件

#### Scenario: 新增和查询帮助说明组别

- **WHEN** 用户分别查看 `add --help` 和 `list --help`
- **THEN** 新增帮助将 `--group <组名>` 展示为必填参数，查询帮助说明该选项可与 `--all` 和 `--json` 组合
