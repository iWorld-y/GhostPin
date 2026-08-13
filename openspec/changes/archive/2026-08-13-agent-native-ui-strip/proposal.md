# Proposal: Agent Native UI 精简

## Why

TodoPin 转型为 **Agent native**:任务的新增、修改、删除一律通过 MCP 完成,App 退化为纯「展示壳」(幽灵 HUD 展示 + 托盘 + 本地通知)。UI 上所有操作入口与全局快捷键系统不再有存在意义,一并移除,减少维护面并消除固定快捷键与其他软件的冲突风险。

## What Changes

- **BREAKING**: 删除文本快速录入 — `QuickAddPanelView`、`Option+Space` 快捷键、`WindowCoordinator.showQuickAdd`。
- **BREAKING**: 删除中文时间解析 — `TodoTimeParser`、`ReminderConfirmationView`、`PendingReminderDraft`(Agent 自行解析自然语言时间后传 ISO8601)。
- **BREAKING**: 删除菜单栏任务面板 — `MenuBarContentView` 的输入框、任务列表与操作按钮;托盘退化为原生菜单:未完成数量徽标 +「显示/隐藏桌面便签」+「交互模式」开关 + 设置 + 退出。
- **BREAKING**: HUD 仅保留「勾选完成」唯一交互 — 删除卡片上的编辑/删除按钮与 `DesktopNoteEditorView`。
- **BREAKING**: 删除全局快捷键系统 — `HotKeyService`、`HotKeyShortcut`/`HotKeyPreset`、Carbon 注册与 `linkedFramework("Carbon")`;HUD 穿透/交互切换改由托盘开关控制。
- **BREAKING**: 删除每小时未完成提醒 — `ReminderPolicy`、`ReminderSettings`(reminderInterval/quietHours)、`NotificationService.sendHourlyReminder`;定时提醒逻辑内联进 `ReminderService`。
- **BREAKING**: 设置页仅保留 HUD 展示参数(透明度/显示范围/最多条数/跨 Space/置顶)与登录启动。
- README(中/英)新增 **Agent Native 设计理念** 章节,强调操作走 MCP、App 仅负责展示与通知。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `ghost-hud`:穿透/交互模式切换从全局快捷键改为托盘开关;交互模式不再包含编辑(仅勾选完成、拖动、调整大小);Purpose 更新为 Agent native 展示壳定位。

## Impact

- **删除文件**: `HotKeyService.swift`、`HotKeyPreset.swift`、`TodoTimeParser.swift`、`QuickAddPanelView.swift`、`ReminderConfirmationView.swift`、`ReminderPolicy.swift`、`ReminderSettings.swift`。
- **重写/修改**: `TodoPinApp.swift`(MenuBarExtra 面板→原生菜单)、`MenuBarContentView.swift`(退化为托盘菜单)、`DesktopNotesBoardView.swift`(删编辑/删除,留勾选)、`AppState.swift`、`AppPreferences.swift`、`WindowCoordinator.swift`、`NotificationService.swift`、`ReminderService.swift`、`SettingsView.swift`、`Package.swift`(去 Carbon)、`Tests/TodoPinCoreChecks/main.swift`、`README.md`/`README.en.md`。
- **保留**: 幽灵 HUD 展示、定时提醒+本地通知、文件监听、MCP(6 工具)、`todopin-cli`、登录启动、优先级/截止/描述(仅 MCP 可写、HUD 展示)。
