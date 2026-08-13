## Why

TodoPin 目前的任务展示入口是"桌面便签"窗口：它虽然已支持置顶与跨 Space，但始终拦截鼠标事件、有完整的窗口感，会遮挡并干扰下方正在使用的应用（VS Code、浏览器等）。需求文档 `docs/需求-2026-08-13.md` 规划了把 TodoPin 变成"幽灵 Todo HUD"的三阶段路线，本变更是第一阶段 MVP：让任务窗口常驻可见却"感觉不到存在"，一抬眼就能看到当前该做的事，日常可用。

## What Changes

- 将现有桌面便签窗口改造成 HUD 窗口：无边框、无标题栏、始终位于普通应用窗口之上、支持调整背景透明度（Settings 滑块，0.5～1.0）。
- 默认开启鼠标点击穿透（基于 `NSWindow.ignoresMouseEvents`）：穿透模式下 HUD 只展示任务、不接收鼠标事件，点击直接传递给下方应用。
- 新增全局快捷键 `⌥⌘T`（Option + Command + T）在穿透/交互模式间快速切换；交互模式下允许勾选、编辑、拖动窗口、调整大小；当前模式有轻微视觉提示。
- HUD 状态持久化：窗口位置、尺寸、透明度、穿透/交互模式、置顶开关、跨 Space 开关、显示范围与条数上限，App 重启后原样恢复。
- HUD 显示范围：支持"全部未完成 / 今天新增"，最多显示 N 条（默认 5～10，可在设置中调整）；已完成任务立即从 HUD 消失。
- 不抢焦点：HUD 出现、刷新任务时不激活 App；只有切换到交互模式或快速新增（保留现有 `⌥Space` 能力）时才获得键盘焦点。
- 保留菜单栏入口对 HUD 的显示/隐藏控制（穿透模式下无法点击 HUD 自身）。

## Capabilities

### New Capabilities

- `ghost-hud`: HUD 窗口的形态与交互模式——无边框置顶、透明度、穿透/交互模式切换与视觉提示、跨 Space 可选、不抢焦点。
- `hud-state-persistence`: HUD 状态与显示配置的持久化——窗口位置/尺寸/透明度/模式/置顶/跨 Space/显示范围/N 条上限，重启恢复。
- `hud-display-scope`: HUD 的展示范围规则——全部未完成或今天新增、最多 N 条、完成即消失。

### Modified Capabilities

（无。`openspec/specs/` 目前为空，本变更是项目首批能力。）

## Impact

- 代码：
  - `Sources/TodoPin/App/WindowCoordinator.swift`：boardWindow 改为 borderless 面板，接入 `ignoresMouseEvents`、`alphaValue`、frame 持久化。
  - `Sources/TodoPin/App/AppState.swift`：HUD 模式切换、显示范围计算、HUD 相关动作。
  - `Sources/TodoPin/App/AppPreferences.swift`：新增透明度、模式、显示范围、N 条上限、跨 Space 开关等偏好键。
  - `Sources/TodoPin/Views/DesktopNotesBoardView.swift`：视觉改造成 HUD（克制外观、模式视觉提示、穿透时隐藏操作按钮）。
  - `Sources/TodoPin/Views/SettingsView.swift`：透明度滑块与 HUD 相关开关。
  - `Sources/TodoPinCore/Models/HotKeyPreset.swift`：新增 `⌥⌘T` 预设；`AppState` 注册第三个全局快捷键。
  - `Tests/TodoPinCoreChecks/main.swift`：为新增的 Core 层逻辑（如显示范围过滤）补充 checks。
- 依赖：无新增依赖，全部使用 AppKit 原生能力（NSWindow、Carbon 快捷键）。
- 风险：`ignoresMouseEvents` 开启时窗口无法被鼠标拖动/调整大小——位置调整必须在交互模式下完成，这使状态持久化成为必需（已纳入本次范围）。
