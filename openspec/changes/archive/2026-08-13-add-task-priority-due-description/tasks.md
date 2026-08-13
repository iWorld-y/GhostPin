## 1. Core 数据模型

- [x] 1.1 新增 `Priority` 枚举（`high`/`medium`/`low`，String rawValue，Codable/Sendable）
- [x] 1.2 `TodoItem` 新增 `priority`（非 Optional，默认 `.medium`）、`dueAt: Date?`、`description: String?` 三个字段
- [x] 1.3 `TodoItem` 自定义 `init(from:)`：`priority` 用 `decodeIfPresent ?? .medium` 兼容旧数据；其余字段与合成语义一致，`encode(to:)` 保留合成
- [x] 1.4 `TodoItem.init` 与 `TodoStore.add` 增加新字段形参（带默认值），保持既有调用点可编译

## 2. TodoStore 排序

- [x] 2.1 `openItems()` 增加 `now: Date = Date()` 参数，实现新排序：未过期在前（过期全局沉底）→ 优先级降序 → 截止日期升序（nil 排组内最后）→ 创建时间降序兜底
- [x] 2.2 `hudItems` 将既有 `now` 透传给 `openItems`
- [x] 2.3 `add`/`update` 支持写入 `priority`/`dueAt`/`description`

## 3. DTO 扩展

- [x] 3.1 `TodoItemPayload` 增加 `priority`/`dueAt`/`description` 三个 CodingKey 与编码（旧 8 字段顺序不变，仅追加），优先级编码为枚举 rawValue，日期 ISO8601

## 4. MCP 工具扩展

- [x] 4.1 `create_task`：inputSchema 与执行增加 `priority`（白名单 `high|medium|low`，默认 `medium`）、`due_at`（ISO8601）、`description`（字符串）参数
- [x] 4.2 `update_task`：inputSchema 与执行增加 `priority`/`due_at`/`clear_due`/`description`，沿用「至少提供一项」「未提供字段不变」语义
- [x] 4.3 非法 `priority` 或非法 `due_at` 返回 isError 工具错误，不修改数据

## 5. HUD 展示

- [x] 5.1 HUD 任务行展示优先级标记（「高/中/低」中文 + 可辨识颜色/图标）
- [x] 5.2 过期未完成任务标题以删除线标注
- [x] 5.3 有描述的任务在标题下方以较小字体展示描述

## 6. 测试与验证

- [x] 6.1 `TodoPinCoreChecks` 新增字段编解码 checks：旧数据缺失 `priority` 解码为 `.medium`、`dueAt`/`description` 缺失为 nil
- [x] 6.2 `TodoPinCoreChecks` 新增排序 checks：优先级优先、同优先级按截止日期、过期全局沉底、无截止日期排后
- [x] 6.3 `TodoPinCoreChecks` 新增 MCP checks：create/update 新参数、非法 priority、非法 due_at、clear_due
- [x] 6.4 `swift build` 通过；`swift run TodoPinCoreChecks` 全绿
- [x] 6.5 `todopin-cli list --json` 输出确认多出 `priority`/`dueAt`/`description` 三字段（CLI 子命令参数不变）
- [x] 6.6 `./script/build_and_run.sh --verify` 通过
