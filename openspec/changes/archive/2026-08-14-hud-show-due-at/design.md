## Context

动机见 proposal.md。现状约束：

- HUD 卡片时间行在 `DesktopNotesBoardView.swift` 的 `DesktopNoteCardView`：无条件画 `createdAt`（clock），有 `reminderAt` 再画铃铛；`dueAt` 完全不读。
- 过期判定已有：`TodoItem.isOverdue()`（`dueAt < now` 且未完成），标题已用红色删除线。
- 日期格式现为 zh_CN `M月d日 HH:mm`，创建与提醒各一份相同 formatter。
- Core 层字段与排序不动；本次只改 App 层展示。
- 无 XCTest，HUD 视觉无现成自动化检查。

## Goals / Non-Goals

**Goals:**

- 卡片时间行只表达截止日期；无截止则整行消失。
- 过期时截止时间与标题删除线共用红色。
- 提醒通知行为保持不变。

**Non-Goals:**

- 不改 `dueAt` / `reminderAt` / `createdAt` 的数据模型、排序、MCP/CLI 契约。
- 不做相对时间（「今天 18:00」）、不做「截止 vs 提醒」切换开关。
- 不给 HUD 加录入/编辑入口。

## Decisions

**D1. 时间行只绑定 `dueAt`**

`if let dueAt` 才画一行；否则不渲染该 HStack。创建时间永远不画。

备选：无截止时回退创建时间 —— 拒绝，与「空则不显示」冲突。

**D2. 提醒铃铛从 HUD 拿掉**

`reminderAt` 仍驱动 `ReminderService` 本地通知，卡片不再画 bell。截止与提醒是两个字段，桌面面板只关心「何时必须完」。

备选：截止 + 提醒并列 —— 已在探索中否决。

**D3. 过期用同一套红色**

`item.isOverdue()` 为真时，截止时间 `.foregroundStyle(.red)`；未过期保持 `.secondary`。与标题 `strikethrough(..., color: .red)` 对齐。

备选：时间保持次要色 —— 已否决。

**D4. 格式复用现有 formatter**

继续 zh_CN `M月d日 HH:mm`，一份即可（删掉 created/reminder 两份重复）。不引入相对日期文案。

**D5. 验证落在手动验收**

HUD 无现成检查框架。Core 层行为不变，不新增 `TodoPinCoreChecks`。任务里写三条肉眼场景：有截止、无截止、过期变红。

## Risks / Trade-offs

- [用户以为提醒没设上] → 提醒仍发通知；MCP/CLI 仍返回 `reminderAt`。HUD 本就不是编辑面。
- [无截止卡片更「空」] → 预期行为，减少噪声。
- [过期无 dueAt 无处画红时间] → 不会发生：`isOverdue()` 要求 `dueAt != nil`。

## Migration Plan

- 无数据迁移，纯展示。
- 回滚：恢复 `createdAt` + 可选 `reminderAt` 两行即可。
