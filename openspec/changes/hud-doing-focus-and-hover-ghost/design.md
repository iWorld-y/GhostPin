# Design

## Context

见 `proposal.md` 的 Why。当前与实现相关的事实：

- `Sources/GhostPin/Views/DesktopNotesBoardView.swift` 从 `TodoStore.hudItems(scope:maxCount:)` 取数后自行按 `status` 过滤成 Doing / Todo 两组渲染；头部标题旁用 `hudItems.count` 显示「N 个未完成」。
- `TodoStore.hudItems` 内部先按范围过滤、再按「Doing 优先」排序、最后统一截断 N 条，因此截断是跨区域生效的。
- `Sources/GhostPin/App/WindowCoordinator.swift` 的 `updateHUD()` 中 `boardWindow.ignoresMouseEvents = (hudMode != .interactive)`，并把 `boardWindow.alphaValue` 设为 `hudOpacity` 偏好（0.5–1.0）。
- `DesktopNotesBoardView` 已存在一段淡出逻辑：`isGhostFading = !isInteractive && isHovering`，经 `.onHover` 驱动，效果为透明度降至 0.4。
- 全仓库没有任何鼠标移动监听（`.onHover` 之外的 `NSEvent` 监听只有 `SettingsView.swift` 的 `.keyDown`）。

### 实测结论（任务 1.1，已在真实 App 上验证）

曾推断 `ignoresMouseEvents = true` 会阻止命中测试、`.onHover` 在穿透模式下不会触发、现有淡出分支恒为 `false`。**该推断经实测被证伪，以下是实测事实：**

1. **`.onHover` 在穿透模式下正常工作。** 以 `make dev` 运行真实 App（`hudMode = passthrough`、`ignoresMouseEvents = true`、应用已 deactivate），外部移动光标跨越 HUD 区域时，`.onHover` 稳定投递 `true` → `false`，与独立计算的 `NSWindow.frame.contains(NSEvent.mouseLocation)` 结果完全吻合，多次往返无遗漏。
2. **现有淡出分支一直是活的。** 探针记录到 `isGhostFading=true boardOpacity=0.4` 与反向恢复，证明 `isGhostFading` 在穿透模式下确实会变为 `true`。**因此 5.3「移除从未生效的死分支」的前提不成立** —— 该分支是有效实现，只把目标值从 0.4 改为 0 即可，不需要引入新的检测机制。
3. **`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` 全程未触发**（合成 CGEvent 不投递到全局监听属已知行为，但真实 App 中亦无收益）。既然 `.onHover` 已可靠工作，**放弃全局监听与轮询定时器方案**。
4. **窗口 `alphaValue = 0` 不会杀死 hover 检测。** 在 timer 内把 `alphaValue` 切到 0.00 再切回 0.50，`.onHover` 仍完整往返 `true → false → true → false`，证明窗口完全透明后指针移出仍能被检测、HUD 不会永久隐身。这使决策 2 的窗口级方案成立。
5. 需要先移出再移入才能触发 enter 的场景（启动时光标已在窗口内）**不成立**：实测中光标位于窗口内时 `.onHover` 也能得到 `true`。

**结论：隐身只需把既有淡出分支的目标不透明度改为 0，并选择在其中叠加窗口级 `alphaValue`。无需新增指针检测机制。**

本次仅改 macOS；`windows-native/src/core.rs` 的同构投影与 `openspec/specs/windows-ghost-hud/spec.md` 的跨平台一致性条款不在范围内。

## Goals / Non-Goals

**Goals:**

- 用一套可工作的指针检测，实现穿透模式下指针进入 HUD 区域即完全隐身、离开即恢复。
- 在 Core 层表达「有 Doing 时只显示 Doing」的分流结果，使 App 层只做渲染编排，并让分流规则可被 `GhostPinCoreChecks` 直接覆盖。
- 保持关闭该偏好时与当前行为完全一致。

**Non-Goals:**

- 不改动 Windows 侧任何代码或规格。
- 不新增 App 写入口、不引入新的全局快捷键、不改 CLI 契约或 `todos.json` 格式。
- 不为隐身行为增加独立的可调透明度数值（用户已确认取 0）。
- 不引入新的指针检测机制（实测证明既有 `.onHover` 已满足需求）。
- 不重构 `hudItems` 既有排序与范围规则。

## Decisions

### 决策 1：沿用既有 SwiftUI `.onHover`，不引入新的指针检测机制

实测（见 Context）表明 `.onHover` 在穿透模式下本来就可靠工作，现有 `isGhostFading = !isInteractive && isHovering` 分支一直是活的。因此指针检测**保持现状**，本次只改它落在哪个不透明度上。

*备选与取舍（均因实测结果而否决）：*

- **`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` + frame 命中判断**：本方案原为首选，但实测中全局监听在真实 App 与合成事件下都未产生可观测收益，而 `.onHover` 已足够；引入它只会增加一个失效模式（监听被系统静默丢弃时无人察觉），放弃。
- **轮询 `NSEvent.mouseLocation` 定时器**：常驻定时器带来无谓唤醒，且同样没有解决的问题，放弃。
- **`NSTrackingArea` + `mouseEntered/mouseExited`**：能力上与 `.onHover` 等价，但需自建 NSView 包装并手动管理 tracking area 的刷新，复杂度更高而无收益，放弃。

因为不再新增监听，窗口移动与缩放后 frame 变化对 .onHover 无影响：SwiftUI 的 hover 由视图几何驱动，视图随窗口一起移动。

### 决策 2：隐身 = 视图不透明度 0 + 窗口 `alphaValue` 归零，不移除窗口

窗口最终可见度是「视图不透明度」与「窗口 `alphaValue`」的乘积。实现选择**只由窗口层承担隐身**：

- `WindowCoordinator`：穿透模式且指针在窗口内时 `alphaValue = 0`，否则恢复为 `hudOpacity` 偏好值。
- `DesktopNotesBoardView`：**不再让视图层归零**。视图层原有的 `isGhostFading` 分支及其 `isHovering` 状态随之移除，视图只负责把 hover 事件转告给协调器。

这样做的理由是乘积已为 0 时，视图层再降不透明度没有任何额外视觉收益，却多出一个可能抑制追踪事件的风险点。`hudOpacity` 偏好始终只作为可见时的取值来源，不被覆写。

指针事实以「指针是否位于窗口 frame 内」这一可推导事实保存，是否隐身每次由「模式 + 该事实」重算，因此不存在需要跨模式清理的中间状态；`updateHUD()` 在模式切换时重算该事实，覆盖「切换时指针已在 HUD 内」的情形。

*备选与取舍：*

- **两层同时归零**：曾计划如此，但无视觉收益且有风险，放弃。
- **只改视图不透明度、不动窗口 `alphaValue`**：窗口保持 `hudOpacity`，仅视图 0 也能达成不可见，但与窗口层方案相比，「完全隐身」会依赖视图层是否被 SwiftUI 复用/重建；窗口层方案行为更确定。
- **`orderOut` / `orderFront`**：视觉上同为不可见，但会改变窗口显示状态，与 `isBoardVisible`（菜单栏「隐藏桌面便签」）语义耦合，还会引入「因隐身而被判定为已隐藏」的分支；`hud-state-persistence` 的可见性语义也会被搅乱，放弃。
- **降到极低透明度（如 0.15）**：用户已明确选择完全不可见，且 0 更贴近「隐身」并可无歧义断言。

### 决策 3：分流规则下沉到 Core，返回分区结果

`GhostPinCore` 增加一个纯函数式的投影入口（在既有 `hudItems` 基础上表达分区与分流），返回 Doing / Todo 两组及各自计数，由 App 层直接渲染。理由：AGENTS.md 要求业务逻辑下沉、`AppState` 只做编排；分区与截断顺序属于可测的业务规则，且现有 `Tests/GhostPinCoreChecks/main.swift` 已覆盖 Doing 优先与条数上限，新规则应与它们同层被测。

`windows-native/src/core.rs` 的 `Projection { items, doing, todo }` 已是同一形状，Swift 侧取其命名可保持两端结构可对照，但不追求行为对齐（见 Non-Goals）。

**关键边界**：条数上限必须只作用于「实际渲染的集合」。若沿用现有「先跨区域截断 N 条、再分流」，在聚焦 Doing 时会先被 Todo 占用配额（例如 N=3、1 条 Doing + 5 条 Todo 时排序结果可能不全是 Doing），与规格中「聚焦 Doing 时截断 Doing」冲突。因此截断需在分流之后按实际展示集合执行。

### 决策 4：头部改为分区计数

头部不再用 `hudItems.count` 作为单一「N 个未完成」，改为分别展示 Doing 与 Todo 计数（用户已确认）。由于聚焦 Doing 时 Todo 卡片被隐藏，Todo 计数必须仍可见，否则用户无法得知存在被隐藏的 Todo 任务。计数取自 Core 分区结果，不在视图层重复过滤。

### 决策 5：偏好命名与持久化沿用现有模式

在 `AppPreferences` 新增一个 `Bool` 偏好（默认开启），沿用现有 `@Published + didSet 写 UserDefaults + Keys 枚举` 的既有写法，透明度、显示范围等均为此模式，无需新模式或存储格式变更。默认值必须在 `init` 中用「键缺失即 true」的写法，以区分「用户显式关闭」与「首次启动」。

## Risks / Trade-offs

- [窗口完全透明后指针移出可能无法被检测，导致 HUD 永久隐身] → 已实测排除：`alphaValue = 0` 期间 `.onHover` 仍完整往返 `true → false → true → false`。实现后仍需在 5.4 复测一次。
- [视图不透明度与窗口 `alphaValue` 两处写入而互相覆盖] → 两层职责分明：窗口层只表达「隐身或不隐身」（由穿透模式 + hover 决定），视图层只表达「活跃/非活跃」；两者都不读取或覆写 `hudOpacity` 偏好。
- [只改 macOS 使 `windows-ghost-hud` 规格的跨平台一致性条款与实际脱离] → 本次接受该偏差，在任务中显式记录，不静默修改 Windows 规格。
- [既有 `isGhostFading` 淡出（0.4）本就是有效行为，直接改数值会让原本可感知的淡出变成完全消失] → 这正是本次需求所要求的行为（用户已确认取完全不可见），并在 `ghost-hud` delta 中以场景固定。

## Migration Plan

无数据迁移。新增偏好为带默认值的 UserDefaults 布尔项，旧版本无该键时按开启处理，升级即生效；回滚只需回退代码，遗留的偏好键不影响旧版本运行。

## Windows 侧未同步（本次已知偏差）

本次改动**仅限 macOS**，Windows 原生 HUD 未同步，因此产生以下已记录的偏差。**`openspec/specs/windows-ghost-hud/spec.md` 未被修改**，其条款保持原样。

1. **分区投影分叉。** `windows-native/src/core.rs` 的 `project()` 在排序后统一截断再分成 `doing` / `todo`，没有「有 Doing 时只显示 Doing」这一分流，也没有分区计数。因此相同任务数据在 Windows 与 macOS 上会产生**不同的渲染集合**：macOS 在存在 Doing 时隐藏 Todo，Windows 仍两个分区同时展示。
2. **一致性条款与实际行为脱节。** `openspec/specs/windows-ghost-hud/spec.md` 中的「Windows HUD 任务投影」要求「相同任务数据和时间输入在 Windows 与现有 GhostPin 中 MUST 产生一致的分区、优先级、截止时间、逾期状态及创建时间排序和截断结果」。该条款在本次改动后仅对排序、优先级、逾期与创建时间仍然成立；**分区与截断结果不再一致**，因为 macOS 侧新增了分流。
3. **鼠标隐身不存在于 Windows 侧。** 「非交互模式指针移入隐身」是 macOS 新增行为，Windows HUD 无对应实现，`windows-ghost-hud` 也没有相应要求。

**处置建议（不在本次范围内）**：另开一个 change 同步 Windows 侧分流与隐身语义，或在那之前收窄 `windows-ghost-hud` 的一致性条款，使其只覆盖排序与逾期等仍然对齐的部分。在未做决定前，不应把本 change 的分流规则当作跨平台契约。

## Open Questions

- 隐身是否需要对「窗口被其他窗口完全遮挡」的情况做额外判断（当前设计不做，仅按几何位置判定）。
