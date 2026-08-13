## Context

- `TodoItem` 现为合成 Codable，8 字段；`TodoStore.openItems()` 是 CLI `list`、MCP `list_tasks`、HUD 的共用未完成任务入口，排序集中在 `sortByCreatedAtDescending`（创建时间倒序）。
- `TodoItemPayload` 是 CLI 与 MCP 共用的手写 Encodable DTO（8 字段），避免双份契约漂移。
- 旧数据 `todos.json` 中的任务没有新字段，读取时必须容忍缺失。
- 项目零第三方 Swift 依赖；`TodoPinCore` 不得 import AppKit/SwiftUI（排序与字段语义必须落在 Core，视觉标记才落在 App 层）。

## Goals / Non-Goals

**Goals:**

- 三个新字段（优先级/截止日期/描述）在 Core 层建模，CLI/MCP/HUD 共用同一语义与排序。
- 旧数据无迁移即可加载；新字段向后兼容（缺失时优先级默认「中」、截止/描述为空）。
- MCP 参数与返回契约显式、可被 Agent 稳定解析。

**Non-Goals:**

- 不强制校验「提醒早于截止」的先后顺序（语义约定，由 Agent 保证）。
- 不为 CLI 子命令新增 `--priority`/`--due`/`--description` 输入参数（用户仅通过 MCP 设置新字段）；CLI 仅输出随之扩展。
- 不做多级优先级、不做截止日期的时区换算（直接存 ISO8601 带偏移的绝对时刻）。

## Decisions

### 1. 优先级建模：非 Optional 枚举 + 自定义解码默认「中」

`Priority` 为 `String` rawValue 枚举（`high`/`medium`/`low`），存非 Optional 字段 `priority`，语义上永远是三档之一。旧 JSON 缺失该字段会令合成 Codable 解码失败，故 `TodoItem` 自定义 `init(from:)`，对 `priority` 用 `decodeIfPresent ?? .medium`；其余字段沿用合成语义（`dueAt`/`description` 为 Optional，天然容忍缺失）。`encode(to:)` 仍走合成。

替代方案（`priority` 存 Optional，nil 表示中）：会让排序、MCP、HUD 各处反复处理 nil→中 的映射，逻辑分散，否决。

### 2. wire format：优先级英文枚举，展示层映射中文

MCP 参数与 DTO 序列化统一用英文 `"high"`/`"medium"`/`"low"`（Agent 更易稳定生成），默认 `"medium"`；HUD 在 App 层映射为中文「高/中/低」并配视觉标记。避免中文/英文两套取值并存导致契约漂移。

### 3. 排序下沉 TodoStore，`openItems` 增加 `now` 参数

排序是任务语义（优先级 + 截止日期定义了相对重要性），落在 `TodoStore`（Core），CLI/MCP/HUD 三处自动一致。`openItems()` 增加 `now: Date = Date()` 用于「过期」判定（`dueAt < now` 且未完成）。比较键顺序：

1. 是否过期：未过期在前，过期全局沉底；
2. 优先级降序：high > medium > low；
3. 截止日期升序：快到期在前，无截止日期（nil）排在组内有截止日期之后；
4. 创建时间降序兜底（保持原行为，作为最后 tie-break）。

`hudItems` 将既有 `now` 透传给 `openItems`；CLI/MCP 用默认 `now`，无需改调用点签名（默认参数）。

### 4. DTO 扩展为 11 字段

`TodoItemPayload` 增加 `priority`/`dueAt`/`description` 三个 CodingKey，CLI 与 MCP 输出同时扩展（旧 8 字段顺序不变，仅追加）。优先级按枚举 rawValue 编码，日期沿用 ISO8601。

### 5. MCP 参数解析

`create_task` 增加 `priority`（字符串，白名单校验 `high|medium|low`，非法返回 isError）、`due_at`（复用现有 `parseISO8601`）、`description`（字符串）。`update_task` 增加 `priority`/`due_at`/`clear_due`/`description`，沿用「至少提供一项」与「未提供字段保持不变」的既有语义。`TodoStore.add`/`update` 增加对应参数。

### 6. 过期判定基准

`dueAt` 是带偏移的绝对时刻，「过期」即 `dueAt < now`（含时间），无额外时区换算。HUD 对过期任务打删除线并沉底，由排序保证沉底位置。

## Risks / Trade-offs

- [旧数据解码失败] → 自定义 `init(from:)` 对 `priority` 默认 `.medium`；`dueAt`/`description` Optional 天然兼容。
- [排序语义双重（优先级 + 过期沉底）易误解] → 明确「过期沉底」优先级最高（覆盖优先级档），在 spec 场景「过期任务全局沉底」中锁定，且 `openItems` 单一实现避免各层漂移。
- [CLI/MCP/HUD 排序不一致] → 排序只存在于 `TodoStore.openItems` 一处；三处均经此入口。
- [回滚后旧版本读新数据] → 旧版本合成 Codable 会忽略 JSON 多余字段，新字段被忽略，排序退回创建时间倒序，数据无损。

## Migration Plan

- 无数据迁移：旧任务加载时 `priority` 默认「中」、`dueAt`/`description` 为空。
- 回滚：移除新字段与排序逻辑即可；`todos.json` 中多出的字段对旧版本无害。
