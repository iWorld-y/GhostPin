## MODIFIED Requirements

### Requirement: list_tasks 工具

`list_tasks` SHALL 查询任务；`include_completed` 参数为 false 或省略时只返回未完成任务，为 true 时返回全部任务；返回的任务对象 MUST 包含 id、title、createdAt、completedAt、source、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 十一个字段，日期为 ISO8601 字符串。

#### Scenario: 查询未完成任务

- **WHEN** 客户端调用 list_tasks 且未传 include_completed
- **THEN** 返回全部未完成任务，按优先级（高→中→低）→ 截止日期升序排列，过期任务沉底，每项十一字段完整

#### Scenario: 查询全部任务

- **WHEN** 客户端调用 list_tasks 且 include_completed 为 true
- **THEN** 返回包含已完成任务在内的全部任务

### Requirement: create_task 工具

`create_task` SHALL 创建任务，参数为 `title`（必填）、`reminder_at`（可选，ISO8601 字符串）、`priority`（可选，`"high"`/`"medium"`/`"low"`，默认 `"medium"`）、`due_at`（可选，ISO8601 字符串）、`description`（可选字符串）；不解析自然语言时间；非法 reminder_at 或 due_at MUST 返回工具错误且不创建任务。

#### Scenario: 创建纯文本任务

- **WHEN** 客户端调用 create_task 且仅提供 title
- **THEN** 创建任务，返回十一字段任务对象，优先级为「中」，无提醒与截止时间、无描述

#### Scenario: 创建带优先级与截止日期的任务

- **WHEN** 客户端调用 create_task 提供 title、priority 为 "high"、due_at 为合法 ISO8601
- **THEN** 创建任务，优先级为「高」，截止日期为给定时刻

#### Scenario: 非法提醒时间

- **WHEN** 客户端调用 create_task 且 reminder_at 不是合法 ISO8601
- **THEN** 返回 isError 工具错误，不创建任务

#### Scenario: 非法截止日期

- **WHEN** 客户端调用 create_task 且 due_at 不是合法 ISO8601
- **THEN** 返回 isError 工具错误，不创建任务

#### Scenario: 非法优先级

- **WHEN** 客户端调用 create_task 且 priority 不是 `"high"`/`"medium"`/`"low"` 之一
- **THEN** 返回 isError 工具错误，不创建任务

### Requirement: update_task 工具

`update_task` SHALL 修改任务：`title` 改标题、`reminder_at` 改提醒时间、`clear_reminder` 清除提醒、`priority` 改优先级、`due_at` 改截止日期、`clear_due` 清除截止日期、`description` 改描述；以上 MUST 至少提供一项；只提供部分参数时未提供字段保持不变。

#### Scenario: 只改标题

- **WHEN** 客户端调用 update_task 且仅提供 title
- **THEN** 标题更新，其余字段保持不变

#### Scenario: 清除提醒

- **WHEN** 客户端调用 update_task 且 clear_reminder 为 true
- **THEN** 该任务提醒时间被移除

#### Scenario: 改优先级与截止日期

- **WHEN** 客户端调用 update_task 且提供 priority 与 due_at
- **THEN** 该任务优先级与截止日期更新

#### Scenario: 清除截止日期

- **WHEN** 客户端调用 update_task 且 clear_due 为 true
- **THEN** 该任务截止日期被移除

#### Scenario: 无任何修改参数

- **WHEN** 客户端调用 update_task 且未提供任何修改参数
- **THEN** 返回 isError 工具错误，任务数据不变
