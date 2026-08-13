## Purpose

定义 `todopin-cli mcp` 子命令提供的 MCP stdio 服务器行为：通过 JSON-RPC 2.0 让 OpenCode、Codex 等 Agent 客户端发现并调用六个任务管理工具，工具逻辑与 CLI、App 共用 TodoPinCore，不维护第二套任务逻辑。

## Requirements

### Requirement: stdio 传输与协议握手

服务器 SHALL 通过标准输入/输出以换行分隔的 JSON-RPC 2.0 消息通信；MUST 支持 `initialize` 请求（返回协议版本、tools 能力与服务器信息）、`notifications/initialized` 通知与 `ping` 请求；stdout MUST 只输出协议消息，日志只写 stderr。

#### Scenario: 握手成功

- **WHEN** 客户端发送 `initialize` 请求
- **THEN** 返回包含 protocolVersion、capabilities.tools 与 serverInfo 的成功响应

#### Scenario: 心跳

- **WHEN** 客户端发送 `ping` 请求
- **THEN** 返回空结果的成功响应，服务器继续运行

### Requirement: 工具发现

`tools/list` SHALL 返回六个工具的声明：list_tasks、create_task、update_task、complete_task、uncomplete_task、delete_task，每个工具 MUST 附带名称、描述与 inputSchema。

#### Scenario: 列出全部工具

- **WHEN** 客户端发送 `tools/list` 请求
- **THEN** 响应包含上述六个工具，且每个工具的 inputSchema 声明了所需参数类型

### Requirement: list_tasks 工具

`list_tasks` SHALL 查询任务；`include_completed` 参数为 false 或省略时只返回未完成任务，为 true 时返回全部任务；返回的任务对象 MUST 包含 id、title、createdAt、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 十个字段，日期为 ISO8601 字符串。

#### Scenario: 查询未完成任务

- **WHEN** 客户端调用 list_tasks 且未传 include_completed
- **THEN** 返回全部未完成任务，按优先级（高→中→低）→ 截止日期升序排列，过期任务沉底，每项十字段完整

#### Scenario: 查询全部任务

- **WHEN** 客户端调用 list_tasks 且 include_completed 为 true
- **THEN** 返回包含已完成任务在内的全部任务

### Requirement: create_task 工具

`create_task` SHALL 创建任务，参数为 `title`（必填）、`reminder_at`（可选，ISO8601 字符串）、`priority`（可选，`"high"`/`"medium"`/`"low"`，默认 `"medium"`）、`due_at`（可选，ISO8601 字符串）、`description`（可选字符串）；不解析自然语言时间；非法 reminder_at 或 due_at MUST 返回工具错误且不创建任务。

#### Scenario: 创建纯文本任务

- **WHEN** 客户端调用 create_task 且仅提供 title
- **THEN** 创建任务，返回十字段任务对象，优先级为「中」，无提醒与截止时间、无描述

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

### Requirement: complete_task 与 uncomplete_task 工具

`complete_task` SHALL 将指定任务标记完成；`uncomplete_task` SHALL 恢复为未完成；id 不存在时 MUST 返回 isError 工具错误。

#### Scenario: 完成任务

- **WHEN** 客户端调用 complete_task 并提供有效 id
- **THEN** 返回 isCompleted 为 true 的任务对象，任务从默认 list_tasks 结果消失

#### Scenario: 恢复任务

- **WHEN** 客户端调用 uncomplete_task 并提供有效 id
- **THEN** 返回 isCompleted 为 false 的任务对象

#### Scenario: id 不存在

- **WHEN** 客户端调用 complete_task 或 uncomplete_task 且 id 不存在
- **THEN** 返回 isError 工具错误，任务数据不变

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

### Requirement: delete_task 工具

`delete_task` SHALL 删除指定任务；id 不存在时 MUST 返回 isError 工具错误。

#### Scenario: 删除任务

- **WHEN** 客户端调用 delete_task 并提供有效 id
- **THEN** 任务从存储移除，返回成功结果

### Requirement: 协议错误与工具错误分层

非法 JSON-RPC 消息 SHALL 返回 -32700 解析错误；未知 method SHALL 返回 -32601 方法不存在；未知工具 MUST 返回 -32602 无效参数；工具执行失败 MUST 返回包含 isError=true 的工具内容结果而非协议错误，且服务器继续服务后续请求。

#### Scenario: 未知方法

- **WHEN** 客户端发送未知 method 的请求
- **THEN** 返回 -32601 JSON-RPC 错误，服务器继续运行

#### Scenario: 工具失败不中断会话

- **WHEN** 某次工具调用因 id 不存在而失败
- **THEN** 返回 isError 内容，随后调用其他工具仍正常响应

### Requirement: 数据新鲜度与一致性

服务器 MUST 在每次工具调用时读取最新的存储内容并在修改后 atomic 保存；与 App 并发运行时 SHALL 不破坏数据文件，App 通过既有文件监听自动刷新（见 hud-live-refresh 能力）。

#### Scenario: 外部修改后读取最新

- **WHEN** 服务器运行期间 App 或 CLI 修改了任务数据，随后客户端调用 list_tasks
- **THEN** 返回最新任务数据
