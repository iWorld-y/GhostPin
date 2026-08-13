# Design: Agent Native UI 精简

## Context

见 proposal.md - Why。当前 App 仍承担全部操作入口(快速录入、菜单栏面板、HUD 编辑、全局快捷键)。本次将操作层整体移交 MCP,App 保留展示与通知;快捷键系统、时间解析、每小时提醒一并移除。前提:第一刀(`remove-voice-summary-source`)已合并进 main,语音/汇总/来源标记已不存在。

## Goals / Non-Goals

**Goals**

- App UI 无任何任务写入口,唯一例外是 HUD 勾选完成(走 TodoStore,不经 MCP)。
- 零全局快捷键注册;穿透/交互切换仅靠托盘开关。
- 删除后构建/测试全绿,CLI/MCP 行为不变。

**Non-Goals**

- 不改 MCP 6 工具的行为与参数(已满足 Agent native 需要)。
- 不动 HUD 的展示层(穿透/置顶/悬停/透明度/跨 Space)。
- 不清理旧 UserDefaults 键(无害残留)。

## Decisions

### D1: 托盘退化为原生菜单

`MenuBarExtra` 从 `.window` 面板样式改为原生菜单(`menuBarExtraStyle(.menu)`),保留图标上的未完成数量徽标。菜单项:「显示/隐藏桌面便签」「交互模式」(Toggle,绑定 `preferences.hudMode`)「设置…」「退出」。删除 `MenuBarContentView` 的任务面板逻辑,新建轻量菜单视图。

- 备选:保留面板但删操作 → 拒绝,面板本身就是为操作而生,退化为菜单更彻底。

### D2: 快捷键系统整体删除

删除 `HotKeyService.swift`、`HotKeyPreset.swift`(HotKeyShortcut)、`AppPreferences` 中 text/hudMode 快捷键偏好、`AppState.registerHotKeys`/`updateTextHotKey`/`updateHUDModeHotKey`、`Package.swift` 的 `linkedFramework("Carbon")`。托盘开关直接调 `AppState.toggleHUDMode()`。

- 备选:保留 ⌥⌘T 固定快捷键 → 拒绝,用户明确要求零快捷键避免冲突。

### D3: 提醒系统收敛为定时提醒

删除 `ReminderPolicy.swift` 与 `ReminderSettings.swift`(每小时提醒的 interval/quietHours 无调用方)。`ReminderService` 只保留:遍历未完成任务,`reminderAt <= now && reminderSentAt == nil` 时发定时通知并 `markTimedReminderSent`。

- 注意:删除 `ReminderPolicy`/`ReminderSettings` 后,`AppPreferences.reminderSettings` 属性一并删除。

### D4: HUD 只读 + 勾选完成

`DesktopNotesBoardView` 删除卡片上的编辑/删除按钮与 `DesktopNoteEditorView`,保留勾选圆圈(调 `setCompleted`)。编辑操作提示:无 UI 入口,走 MCP `update_task`。

### D5: 视图与入口清理

删除 `QuickAddPanelView`、`ReminderConfirmationView`(+`PendingReminderDraft`)、`TodoTimeParser.swift`;`WindowCoordinator` 删除 `showQuickAdd`/`quickAddWindow`。`SettingsView` 仅保留 HUD 参数 Section 与登录启动。`AppPreferences` 保留 hudMode/hudOpacity/hudScope/hudMaxItems/hudAllSpaces/keepBoardOnTop/hudFrame/launchAtLogin。

## Risks / Trade-offs

- **HUD 勾选完成不经 MCP** → 与「操作仅靠 MCP」理念有轻微出入,但它是本地即时动作,无歧义;specs 已明确这是唯一例外。
- **移除快捷键后无全局呼出** → 展示依赖 HUD 常驻(穿透模式本来就不挡操作),托盘可随时显示/隐藏,可接受。
- **遗留偏好键** → UserDefaults 中 hotKey 相关键不再读取,无害,不清理。
- **遗漏引用** → 删除面跨 5 个 target,以编译错误为哨兵逐文件清理,`TodoPinCoreChecks` 兜底。

## Migration Plan

1. 在 main 分支直接实施(PR #1 已合并)。
2. 先删 Core 层(TodoTimeParser/ReminderPolicy/ReminderSettings)→ App 层与视图 → Package.swift → 测试 → 文档。
3. 每阶段 `swift build --disable-sandbox` 验证(本机 SPM manifest 沙箱问题)。
4. 回归 `swift run --disable-sandbox TodoPinCoreChecks`;打包启动验证(手动 bundle 流程)。
5. README 增补 Agent Native 章节。

## Open Questions

无。
