## Why

TodoPin 当前只有 Todo 与 Done 两种任务状态，Agent 开始处理任务后无法表达“正在进行中”，HUD 也无法区分尚未开始与正在推进的任务。增加 Doing 状态可以让任务进度在 Agent、CLI、MCP 与 HUD 之间保持一致，同时通过分区和点击冷却降低误操作风险。

## What Changes

- 增加 `Todo`、`Doing`、`Done` 三态任务模型，并兼容现有仅包含 `completedAt` 的任务数据。
- 将 Todo 与 Doing 都视为未完成；默认查询和 HUD 均展示两者，Done 才从默认结果与 HUD 中消失。
- HUD 分为 Doing 与 Todo 两个区域，Doing 区域始终位于 Todo 区域上方；空区域不展示，区域内部沿用现有排序规则。
- 复用 HUD 现有圆形按钮：Todo 第一次点击进入 Doing，Doing 再次点击进入 Done；每次状态变化后 500ms 内忽略重复点击。
- CLI 增加 `doing <id>`，MCP 增加 `start_task`；保留现有直接完成与恢复接口的兼容语义。
- `undone` / `uncomplete_task` 将 Done 或 Doing 恢复为 Todo；任务状态通过 CLI/MCP 返回并纳入 JSON payload。

## Capabilities

### New Capabilities

- `todo-status`: 定义任务三态、状态转换、持久化兼容和任务状态输出契约。

### Modified Capabilities

- `hud-display-scope`: 增加 Doing/Todo 分区、分区顺序和空区域隐藏规则。
- `ghost-hud`: 修改圆形按钮的状态推进和 500ms 点击冷却行为。
- `hud-live-refresh`: 外部将任务设置为 Doing 后，HUD 需要刷新并重新分区。
- `todo-cli`: 增加 `doing` 命令及包含状态的查询和操作输出。
- `todo-mcp-server`: 增加 `start_task` 工具及包含状态的任务查询和操作输出。

## Impact

- 受影响代码：`TodoPinCore` 的任务模型、存储与 payload，TodoPin HUD 视图，`todopin-cli`，TodoPin MCP 工具，以及对应的核心行为检查。
- 受影响数据：`todos.json` 增加状态字段；旧数据必须继续可读。
- 受影响接口：CLI 与 MCP 增加 Doing 能力，但保留现有完成/恢复接口，避免破坏已有调用方。
- 不新增外部依赖，不改变提醒、截止时间和区域内部排序的既有规则。
