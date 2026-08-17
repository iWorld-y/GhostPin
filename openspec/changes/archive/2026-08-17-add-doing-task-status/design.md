## Context

当前 `TodoPinCore` 以 `completedAt` 是否为空表示二态任务，`TodoStore.openItems()`、提醒/逾期判断、CLI 和 MCP 都直接依赖这一语义。App、CLI 与 MCP 共用同一个 `todos.json`，HUD 通过 `TodoStore.hudItems()` 展示未完成任务；现有 HUD 圆形按钮只调用完成操作。

本设计承接 proposal.md，并实现 specs 中的三态任务、HUD 分区、外部状态接口和点击冷却要求。

## Goals / Non-Goals

**Goals:**

- 在 `TodoPinCore` 建立统一的 `todo` / `doing` / `done` 状态和转换入口。
- 让 CLI、MCP、App 和 HUD 共用同一套状态语义、排序和持久化格式。
- 让旧的 `todos.json` 自动按 `completedAt` 推导状态，并保留旧的完成/恢复接口。
- 让 HUD 复用现有圆形按钮完成 Todo → Doing → Done 的渐进操作，并可靠抑制 500ms 内的重复点击。

**Non-Goals:**

- 不限制 Doing 任务数量，不引入“当前唯一任务”概念。
- 不增加新的外部依赖，不改变提醒时间、截止时间和区域内部排序规则。
- 不实现任务状态历史、状态变更人、状态变更原因或多设备同步。

## Decisions

### 1. 使用显式 `TodoStatus`，并保留 `completedAt`

在 `TodoPinCore` 增加可编码的 `TodoStatus`，编码值固定为 `todo`、`doing`、`done`。`TodoItem.status` 作为新数据的状态真源，`isCompleted` 派生为 `status == .done`；`completedAt` 继续作为完成时间元数据，在进入 Done 时写入、离开 Done 时清空。

选择显式枚举而不是增加 `isDoing` 布尔值，是为了避免 Todo/Doing/Done 三种组合产生不一致，也让 CLI、MCP 的 JSON 契约可以直接表达状态。保留 `completedAt` 则能维持已有完成时间、完成记录和旧客户端字段。

### 2. 在解码层兼容旧数据，写入时统一输出新字段

`TodoItem` 的自定义解码逻辑在 `status` 缺失时按以下规则推导：`completedAt` 有值映射为 `.done`，否则映射为 `.todo`。新版本保存任务时总是编码 `status`，同时继续编码 `completedAt`、`isCompleted` 等既有输出字段。

新数据的状态变更通过 Core 的统一状态操作完成，确保进入 Done 时设置完成时间、离开 Done 时清空完成时间。`hasPendingTimedReminder` 与 `isOverdue` 继续依赖 `isCompleted`，因此 Doing 仍会正常参与提醒和逾期判断。

备选方案是用 `startedAt` 推导 Doing，但这会把状态语义拆散到多个时间字段，并增加回退规则；本变更只需要状态，不需要开始时间历史，因此不采用。

### 3. 用统一状态操作承接旧接口

TodoStore 增加统一的状态变更能力，并保留现有语义包装：

- `doing` / `start_task` 将任务设为 `.doing`；
- `done` / `complete_task` 将任务设为 `.done`；
- `undone` / `uncomplete_task` 将任务设为 `.todo`，既适用于 Done，也适用于 Doing。

CLI 与 MCP 只负责参数解析、错误映射和输出，状态转换与持久化仍由 Core 负责。这样旧调用方继续可用，新 Agent 流程可以显式标记开始处理。

### 4. 让状态排序先于现有任务排序

`TodoStore` 的未完成任务排序先比较状态：Doing 优先于 Todo；同一状态内继续使用既有的优先级、截止日期、逾期状态和创建时间规则。`hudItems` 的条数上限在这套排序之后统一截断，HUD 再按状态分组渲染，因此不会出现 Todo 的 high 任务越过 Doing 的 low 任务。

这比在 SwiftUI 视图中分别截断两个数组更稳定：CLI、MCP、HUD 使用同一顺序，且全局条数上限不会被两个区域各自重复计算。

### 5. 由 AppState 统一处理 HUD 状态推进和点击冷却

HUD 圆形按钮调用 AppState 的状态推进操作：Todo 推进到 Doing，Doing 推进到 Done，Done 不再提供推进动作。AppState 按任务 id 记录最近一次成功状态变化的单调时间，在 500ms 冷却窗口内忽略同一任务的后续点击；冷却逻辑不放在卡片视图的局部状态中，避免任务在分区移动或视图重建时丢失保护。

穿透模式仍不接收点击。交互模式下状态写入成功后由本地 store 立即更新，外部文件监听仍负责 CLI/MCP 写入后的刷新，不改变既有焦点策略。

### 6. 扩展 payload 与 MCP 工具声明，保留旧字段

`TodoItemPayload` 增加 `status`，继续输出 `completedAt` 与 `isCompleted`。CLI 的文本 list 可输出状态标签，JSON 操作结果沿用已有成功/失败结构。MCP 工具列表增加 `start_task`，其参数和错误分层与现有任务工具一致。

## Risks / Trade-offs

- [旧版本回滚] → 旧 App 可以忽略新 `status` 字段读取文件，但旧版本再次保存时无法保留 Doing 状态；发布和回滚说明应提醒在旧版本写入前备份数据，Doing 可能退化为 Todo。
- [状态字段与完成时间不一致] → 所有新写入统一通过 Core 状态操作，并在测试中覆盖 Done/非 Done 与 `completedAt` 的一致性。
- [Doing 优先导致 Todo 被截断] → 这是明确的产品排序要求；CLI、MCP 和 HUD 使用同一状态优先顺序，并补充跨区域条数上限测试。
- [500ms 交互延迟] → 第一次点击立即生效，只有冷却窗口内的重复点击被忽略；测试覆盖窗口内和窗口外两种行为，避免误把正常第二次点击吞掉。
- [跨进程同时写入] → 继续使用现有 atomic 保存和文件监听机制；本变更不引入新的并发写入协议，需在既有外部刷新与 MCP 新鲜度检查上补充 Doing 场景。

## Migration Plan

1. 先发布包含解码兼容和新状态字段的版本；首次读取旧文件时按 `completedAt` 推导状态，后续保存逐步写入 `status`。
2. 在 Core、CLI、MCP 和 HUD 行为检查通过后，再启用新的 `doing` / `start_task` 调用方。
3. 回滚时优先恢复数据备份；若旧版本写回 `todos.json`，Todo/Done 可保持旧语义，Doing 任务可能被旧格式保存为 Todo。
