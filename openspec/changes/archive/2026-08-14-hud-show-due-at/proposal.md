## Why

HUD 任务卡片默认画的是创建时间 `createdAt`（始终有值），截止日期 `dueAt` 完全不展示。对桌面常驻面板来说，创建时间几乎没有决策价值，用户真正需要看见的是「何时必须完成」。无截止的任务再画一个创建时间只会制造噪声。

## What Changes

- HUD 卡片时间行只展示截止日期 `dueAt`，格式仍为 `M月d日 HH:mm`
- 截止日期为空时不显示时间行
- 任务已过期时，截止时间与标题删除线使用同一套红色超时语义
- 不再展示创建时间与提醒时间（提醒仍到点发本地通知，只是卡片不画铃铛）

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `task-priority-due-description`: 扩展「HUD 视觉标记」——卡片时间行只显示 `dueAt`；空则不画；过期时截止时间变红。不改字段语义与排序规则。

## Impact

- `Sources/TodoPin/Views/DesktopNotesBoardView.swift`：卡片时间行从 `createdAt` + 可选 `reminderAt` 改为可选 `dueAt`
- spec `task-priority-due-description`：补时间展示 requirement
- 不改数据模型、排序、MCP/CLI、通知
- 非 breaking
