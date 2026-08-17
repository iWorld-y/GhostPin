## MODIFIED Requirements

### Requirement: 工具发现

`tools/list` SHALL 返回七个工具的声明：list_tasks、create_task、update_task、complete_task、uncomplete_task、start_task、delete_task，每个工具 MUST 附带名称、描述与 inputSchema。

#### Scenario: 列出全部工具

- **WHEN** 客户端发送 `tools/list` 请求
- **THEN** 响应包含上述七个工具，且每个工具的 inputSchema 声明了所需参数类型

### Requirement: list_tasks 工具

`list_tasks` SHALL 查询任务；`include_completed` 参数为 false 或省略时只返回 Todo 与 Doing，为 true 时返回全部任务；返回的任务对象 MUST 包含 id、title、createdAt、status、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 十一个字段，日期为 ISO8601 字符串。

#### Scenario: 查询未完成任务

- **WHEN** 客户端调用 list_tasks 且未传 include_completed
- **THEN** 返回全部 Todo 与 Doing 任务，先返回 Doing 再返回 Todo，每组按优先级（高→中→低）→截止日期升序排列，过期任务沉底，每项十一字段完整

#### Scenario: 查询全部任务

- **WHEN** 客户端调用 list_tasks 且 include_completed 为 true
- **THEN** 返回包含 Todo、Doing、Done 在内的全部任务

### Requirement: create_task 工具

`create_task` SHALL 创建任务，参数为 `title`（必填）、`reminder_at`（可选，ISO8601 字符串）、`priority`（可选，`"high"`/`"medium"`/`"low"`，默认 `"medium"`）、`due_at`（可选，ISO8601 字符串）、`description`（可选字符串）；不解析自然语言时间；非法 reminder_at 或 due_at MUST 返回工具错误且不创建任务；新任务状态 MUST 为 Todo。

#### Scenario: 创建纯文本任务

- **WHEN** 客户端调用 create_task 且仅提供 title
- **THEN** 创建 Todo 任务，返回十一字段任务对象，优先级为「中」，无提醒与截止时间、无描述

#### Scenario: 创建带优先级与截止日期的任务

- **WHEN** 客户端调用 create_task 提供 title、priority 为 "high"、due_at 为合法 ISO8601
- **THEN** 创建 Todo 任务，优先级为「高」，截止日期为给定时刻

#### Scenario: 非法提醒时间

- **WHEN** 客户端调用 create_task 且 reminder_at 不是合法 ISO8601
- **THEN** 返回 isError 工具错误，不创建任务

#### Scenario: 非法截止日期

- **WHEN** 客户端调用 create_task 且 due_at 不是合法 ISO8601
- **THEN** 返回 isError 工具错误，不创建任务

#### Scenario: 非法优先级

- **WHEN** 客户端调用 create_task 且 priority 不是 "high"/"medium"/"low" 之一
- **THEN** 返回 isError 工具错误，不创建任务

### Requirement: complete_task 与 uncomplete_task 工具

`complete_task` SHALL 将指定任务标记为 Done；`uncomplete_task` SHALL 将指定任务恢复为 Todo；id 不存在时 MUST 返回 isError 工具错误。

#### Scenario: 完成任务

- **WHEN** 客户端调用 complete_task 并提供有效 id
- **THEN** 返回 status 为 `done` 且 isCompleted 为 true 的任务对象，任务从默认 list_tasks 结果消失

#### Scenario: 恢复任务

- **WHEN** 客户端调用 uncomplete_task 并提供有效 id
- **THEN** 返回 status 为 `todo` 且 isCompleted 为 false 的任务对象

#### Scenario: 恢复 Doing 任务

- **WHEN** 客户端调用 uncomplete_task 处理一个 Doing 任务
- **THEN** 返回 status 为 `todo` 且 isCompleted 为 false 的任务对象

#### Scenario: id 不存在

- **WHEN** 客户端调用 complete_task 或 uncomplete_task 且 id 不存在
- **THEN** 返回 isError 工具错误，任务数据不变

## ADDED Requirements

### Requirement: start_task 工具

`start_task` SHALL 接收任务 id 并将指定任务标记为 Doing；任务不存在时 MUST 返回 isError 工具错误，成功时返回包含 status 与 isCompleted 的完整任务对象。

#### Scenario: 开始处理任务

- **WHEN** 客户端调用 start_task 并提供 Todo 任务的有效 id
- **THEN** 返回 status 为 `doing`、isCompleted 为 false 的任务对象，任务继续出现在默认 list_tasks 结果中

#### Scenario: 重复开始 Doing 任务

- **WHEN** 客户端调用 start_task 并提供已是 Doing 的任务 id
- **THEN** 返回该任务的 Doing 状态，不创建重复任务或改变其他字段

#### Scenario: id 不存在

- **WHEN** 客户端调用 start_task 且 id 不存在
- **THEN** 返回 isError 工具错误，任务数据不变
