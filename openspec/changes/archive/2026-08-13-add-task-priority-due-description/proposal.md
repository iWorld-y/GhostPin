## Why

TodoPin 的任务目前只有「标题 + 提醒时间」，Agent 通过 MCP 创建的任务缺少轻重缓急和「何时必须完成」的信息；HUD 也只按创建时间倒序展示，分不出主次。需要让任务支持优先级、截止日期与描述，使 Agent 能精细管理、HUD 能按「重要的、快到期的事先冒出来」排序。

## What Changes

- `TodoItem` 新增三个字段：`priority`（高/中/低）、`dueAt`（截止日期，日期+具体时刻）、`description`（可选描述文本）。
- `TodoStore` 的 `add`/`update` 支持设置这三个字段；新增按「优先级 → 截止日期」的排序逻辑。
- MCP 工具扩展：`create_task` 新增 `priority`/`due_at`/`description` 参数；`update_task` 新增对应修改参数；`list_tasks` 返回扩展后的任务字段。
- HUD 排序改为：优先级优先（高→中→低）→ 同优先级按截止日期升序 → 过期任务删除线标注并**全局沉底** → 无截止日期者排组内最后（创建时间倒序兜底）。
- HUD 展示描述字段（小字体）；过期任务删除线标注。
- 共用 DTO `TodoItemPayload` 扩展为 11 字段，CLI 与 MCP 的 JSON 输出随之扩展。**CLI 子命令不新增输入参数**（用户仅通过 MCP 设置新字段），但 `list --json` 输出会多出三个字段。

## Capabilities

### New Capabilities

- `task-priority-due-description`: 任务优先级（三档）、截止日期、描述字段的数据模型语义，以及 HUD 的排序规则与视觉标记（优先级标记、过期删除线、描述小字体展示）。

### Modified Capabilities

- `todo-mcp-server`: `create_task`/`update_task` 新增 `priority`/`due_at`/`description` 参数，`list_tasks` 返回字段从 8 个扩到 11 个。
- `todo-cli`: JSON 输出契约从 8 字段扩到 11 字段（因共用 `TodoItemPayload` DTO；CLI 子命令参数不变）。

## Impact

- 代码：
  - `Sources/TodoPinCore/Models/TodoItem.swift`：新增 `priority`/`dueAt`/`description` 字段。
  - `Sources/TodoPinCore/Models/TodoItemPayload.swift`：DTO 扩为 11 字段。
  - `Sources/TodoPinCore/Stores/TodoStore.swift`：`add`/`update` 增加新字段参数与排序逻辑。
  - `Sources/TodoPinMCP/Tools.swift`：`create_task`/`update_task`/`list_tasks` 的 schema 与执行逻辑。
  - `Sources/TodoPin/`（App 层 HUD）：排序展示、优先级标记、过期删除线、描述小字体。
  - `Tests/TodoPinCoreChecks/main.swift`：新增字段编解码、排序、MCP 参数的 checks。
- 依赖：无新增第三方依赖。
- 数据：`todos.json` 中既有任务无新字段，读取时需容忍缺失（`priority` 默认「中」、`dueAt`/`description` 为 nil）。
