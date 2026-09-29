# Proposal

## Why

HUD 的任务分区目前把 Doing 和 Todo 同时铺开，当已有任务正在处理时，Todo 列表仍然占用主要版面，正在做的事反而不突出。同时穿透模式下 HUD 虽然不响应鼠标，却仍以 0.86 左右的透明度遮挡其下方内容；用户视线掠过 HUD 覆盖区域时无法看清底下的窗口。

本次改动让 HUD 在存在 Doing 任务时聚焦于 Doing（默认开启，可在设置中关闭），并在非交互模式下让指针进入 HUD 区域时完全隐身、移出后恢复。

## What Changes

- HUD 新增「有 Doing 时只显示 Doing」显示偏好，默认开启。开启时若存在 Doing 任务，则只渲染 Doing 分区并隐藏全部 Todo 卡片；不存在 Doing 任务时照常显示 Todo。关闭后恢复当前「Doing 区在上、Todo 区在下」的同时显示行为。
- HUD 头部不再显示单一「N 个未完成」，改为分别显示 Doing 与 Todo 的数量。
- **BREAKING（规格层面）**：`hud-display-scope` 中「条数上限跨区域生效」与「未完成任务分区」两条 Requirement 的现有措辞要求两个分区同时展示，与本次分流规则冲突，需要改写为按该开关分流。
- 非交互（穿透）模式下，指针进入 HUD 窗口区域时 HUD 透明度降为 0（完全不可见），指针离开后恢复为「HUD 透明度」偏好值；该过程不修改已持久化的透明度偏好。交互模式不受影响。
- 现有 `DesktopNotesBoardView` 中的 `isGhostFading` 淡出逻辑（0.4 透明度）从未生效，本次以真正可工作的指针检测替代，并移除该无效分支。
- 新增的显示偏好纳入 `hud-state-persistence` 的持久化范围，默认值为开启。

## Capabilities

### New Capabilities
<!-- 无新增能力：两处行为都落在既有能力内。 -->

### Modified Capabilities
- `hud-display-scope`: 新增「有 Doing 时只显示 Doing」分流规则与头部计数要求；改写「未完成任务分区」与「条数上限跨区域生效」两条与新规则冲突的 Requirement。
- `hud-state-persistence`: 将新的「有 Doing 时只显示 Doing」显示偏好纳入需持久化的显示配置，并明确其默认值为开启。
- `ghost-hud`: 补全非交互模式下指针进入 HUD 区域即隐身的视觉行为要求，替换现有仅以「穿透不响应鼠标」描述的缺口。

## Impact

- macOS App 层：`Sources/GhostPin/Views/DesktopNotesBoardView.swift`（分区渲染、头部计数、隐身不透明度）、`Sources/GhostPin/App/WindowCoordinator.swift`（指针检测与窗口 alpha）、`Sources/GhostPin/App/AppPreferences.swift`（新增偏好项与 UserDefaults key）、`Sources/GhostPin/Views/SettingsView.swift`（新增开关）。
- Core 层：`Sources/GhostPinCore/Stores/TodoStore.swift` 的 `hudItems(scope:maxCount:)` 需要能表达分流结果，供 App 层渲染并被 `Tests/GhostPinCoreChecks/main.swift` 直接覆盖。
- 本次仅限 macOS 平台。`windows-native/src/core.rs` 的 `project()` 与 `openspec/specs/windows-ghost-hud/spec.md` 中的跨平台一致性条款在本次不改动，会与实际 macOS 行为产生偏差，需在实施时明确记录该偏差。
- 无新增依赖、无存储格式变更、无 CLI 契约变更。
