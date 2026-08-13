## Context

现有架构（详见 proposal.md - Impact）：

- `WindowCoordinator` 创建并持有 `boardWindow`（NSPanel，`.titled/.closable/.resizable/.fullSizeContentView`，已设 `.canJoinAllSpaces/.fullScreenAuxiliary`、`isMovableByWindowBackground`），`updateBoardLevel()` 统一刷新窗口层级。
- `DesktopNotesBoardView` 已用 `isActive`（hover / 编辑中）控制操作按钮显隐，并有两套视觉（active / inactive）。
- `AppPreferences` 用 UserDefaults 保存偏好，`didSet` 即时落盘。
- `HotKeyService`（Carbon）注册两个全局快捷键：id 1 文本录入、id 2 语音录入；`AppState.registerHotKeys()` 集中注册。
- `TodoStore.openItems()` 返回全部未完成任务；`TodoPinCore` 不得 import AppKit/SwiftUI。
- 测试为可执行 target `TodoPinCoreChecks`，用例注册在 `checks` 数组，东八区固定日历。

## Goals / Non-Goals

**Goals:**

- 一个窗口承载穿透/交互两态，状态机仅两态切换。
- 持久化全部走 UserDefaults，不引入新存储格式。
- 显示范围过滤下沉到 `TodoPinCore`，可被 TodoPinCoreChecks 覆盖。
- 模式切换、刷新全程不抢焦点（仅交互模式与快速新增激活）。

**Non-Goals:**

- 不新建第二个常驻窗口（改造现有 boardWindow）。
- 不做 CLI / MCP / IPC（第二、三阶段变更）。
- 不改 `TodoItem` 数据模型，不做列表/Inbox 概念。

## Decisions

### 1. 改造 boardWindow 为 HUD，而非新建窗口

理由：职责完全重叠（常驻展示未完成任务），保留两个窗口会造成"哪个才是 TodoPin 窗口"的日常困惑与视图代码重复。替代方案（另建 HUD、保留便签）已否决。

### 2. 两态模型：`HudMode.passthrough / interactive`

- 穿透：`ignoresMouseEvents = true`，视图隐藏操作按钮，静止外观，不做 key window。
- 交互：`ignoresMouseEvents = false`，操作按钮可见，`makeKeyAndOrderFront` + 激活以获得键盘焦点。
- 模式状态存 `AppPreferences.hudMode`（持久化），切换入口只有全局快捷键（穿透时点不到窗口，无其他入口）。
- 替代方案（CGEventTap 事件重定向）复杂且无必要，否决。

### 3. 窗口形态：`styleMask = [.borderless, .resizable]`

移除 `.titled/.closable/.fullSizeContentView`，彻底去边框；保留 `.resizable` 以支持交互模式下边缘调整大小，保留 `isMovableByWindowBackground` 支持内容区拖动。替代方案（保留 .titled + 隐藏标题栏）仍有系统边框与标题栏手势区域，不够"无边框"，否决。

### 4. 透明度：`window.alphaValue` + Settings 滑块

`alphaValue = hudOpacity`（0.5～1.0，默认 1.0），作用于整个窗口，最直接且"整体视觉克制"。替代方案（只调背景视图 opacity、保留文字清晰度）需拆分材质背景与前景视图，改动大，否决。下限 0.5 防止文字不可读。

### 5. 持久化：全部走 AppPreferences（UserDefaults）

新增偏好键：`hudFrame`（4 个 CGFloat，JSON 编码）、`hudOpacity`（Double）、`hudMode`（String 原始值）、`hudScope`（String 原始值）、`hudMaxItems`（Int，默认 8）、`hudAllSpaces`（Bool，默认 true）；置顶沿用现有 `keepBoardOnTop`。

- frame 保存时机：`windowDidMove` / `windowDidResize` 回调即存（轻量）；恢复时校验 frame 是否与任一 `NSScreen.frame` 相交，不相交则回落到屏幕居中默认位置。
- 替代方案（`setFrameAutosaveName`）只解决 frame 一项，与其余偏好键机制不统一，否决。

### 6. 模式切换快捷键：HotKeyService 第三个注册

`HotKeyPreset` 新增 `.optionCommandT`（keyCode 17 = kVK_ANSI_T，modifiers = optionKey(2048) | cmdKey(256) = 2304），加入 `presets`。`AppState.registerHotKeys()` 注册 id 3 → `toggleHUDMode()`。SettingsView 增加第三行"模式切换快捷键"录制入口，冲突校验逻辑与现有文本/语音一致（三者两两互斥）。

### 7. 显示范围过滤下沉到 TodoPinCore

新增 `public enum HudScope: String, Codable, Sendable { case all, today }`，`TodoStore` 增加 `hudItems(scope:maxCount:now:calendar:) -> [TodoItem]`：先按范围过滤（today = 创建于今天日界内），再 `openItems()` 排序后截断 N 条。可被 TodoPinCoreChecks 直接覆盖。替代方案（在 View 层过滤）违反分层且不可测，否决。

### 8. 不抢焦点的实现

- HUD 出现沿用现有 `orderFrontRegardless()`（已不激活）。
- 模式切换只改 `ignoresMouseEvents` + 视图状态，不调用 `NSApp.activate`。
- 切到交互：`makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps:)` 获取键盘焦点；切回穿透：`window.resignKey()` + `NSApp.deactivate()`，让焦点自然归还前一个应用。
- 任务列表刷新由 `@Published items` 驱动 SwiftUI 自动更新，无需窗口操作。

### 9. 视觉提示复用现有 active/inactive 双视觉

穿透 = 现有 inactive 外观（浅描边、低饱和、无操作按钮），交互 = 现有 active 外观（清晰描边、操作按钮可见）。现有视图已具备两套视觉，把"交互模式"并入 `isActive` 判断即可，改动最小。

## Risks / Trade-offs

- [穿透模式下无法用鼠标操作窗口，位置/尺寸只能在交互模式调整] → ⌥⌘T 是唯一切换入口；快捷键注册失败时走现有 `lastErrorMessage` 链路，菜单栏与设置面板可见报错。
- [ignoresMouseEvents 开启时 SwiftUI hover 失效] → 穿透模式视图保持静止外观，交互模式恢复 hover。
- [borderless 窗口无系统拖拽区域] → `isMovableByWindowBackground` 使内容区可拖（交互模式），与现有行为一致。
- [frame 恢复时显示器配置已变化（外接屏拔插）] → 恢复前校验与屏幕相交，否则居中回落。
- [⌥⌘T 可能与其他应用冲突] → `RegisterEventHotKey` 失败时走现有报错链路，并保持上一次模式快捷键。

## Migration Plan

- 无需数据迁移：全部为新增偏好键，`todos.json` 格式不变。
- 存量用户升级后首次启动：boardWindow 变为 HUD，默认穿透；历史 `keepBoardOnTop` 键沿用为置顶开关。
- 回滚：改动集中在窗口层与偏好键，恢复旧 build 即可，数据不受影响。
