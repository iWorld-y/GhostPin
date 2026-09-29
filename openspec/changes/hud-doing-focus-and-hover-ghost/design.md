# Design

## Context

见 `proposal.md` 的 Why。当前与实现相关的事实：

- `Sources/GhostPin/Views/DesktopNotesBoardView.swift` 从 `TodoStore.hudItems(scope:maxCount:)` 取数后自行按 `status` 过滤成 Doing / Todo 两组渲染；头部标题旁用 `hudItems.count` 显示「N 个未完成」。
- `TodoStore.hudItems` 内部先按范围过滤、再按「Doing 优先」排序、最后统一截断 N 条，因此截断是跨区域生效的。
- `Sources/GhostPin/App/WindowCoordinator.swift` 的 `updateHUD()` 中 `boardWindow.ignoresMouseEvents = (hudMode != .interactive)`，并把 `boardWindow.alphaValue` 设为 `hudOpacity` 偏好（0.5–1.0）。
- `DesktopNotesBoardView` 已存在一段淡出逻辑：`isGhostFading = !isInteractive && isHovering`，经 `.onHover` 驱动，效果为透明度降至 0.4。
- 全仓库没有任何鼠标移动监听（`.onHover` 之外的 `NSEvent` 监听只有 `SettingsView.swift` 的 `.keyDown`）。

`ignoresMouseEvents = true` 的窗口不参与窗口服务器的命中测试，`mouseEntered` / `mouseExited` 通常不会投递到该窗口，因此 SwiftUI `.onHover` 在穿透模式下预期不会触发；而交互模式下 `!isInteractive` 为假，`isGhostFading` 同样为假。据此推断现有淡出分支在任何模式下都恒为 `false`，从未生效。**该推断属于待验证假设，实施第一步必须实测确认，不得直接当作既定事实沿用。**

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
- 不重构 `hudItems` 既有排序与范围规则。

## Decisions

### 决策 1：指针检测采用全局鼠标移动监听 + 窗口 frame 命中判断

`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` 在穿透模式下仍能收到鼠标移动事件，因为监听发生在应用之外、与窗口是否参与命中测试无关；`.mouseMoved` 属于指针类监听，不需要辅助功能（Accessibility）授权，这与键盘类全局监听不同。检测到移动后用 `NSWindow.frame.contains(NSEvent.mouseLocation)` 判断指针是否位于 HUD 区域内。

*备选与取舍：*

- **继续用 SwiftUI `.onHover`**：实现最省，但穿透模式下窗口不参与命中测试，事件预期收不到，正是当前失效的原因；在穿透模式下是否可被修复不可控，放弃。
- **`NSTrackingArea` + `mouseEntered/mouseExited`**：同样依赖窗口接收事件，穿透模式下不成立，放弃。
- **轮询 `NSEvent.mouseLocation` 定时器**：无需监听且最直观，但常驻定时器带来无谓唤醒；全局监听由系统在鼠标移动时驱动，无事件时不消耗，更省。
- **比较窗口 frame 而非视图 bounds**：窗口 frame 与实际遮挡区域一致，且视图随窗口移动，无需额外坐标转换。

命中的判定需要覆盖窗口移动与缩放后的新 frame，因此监听回调每次读取当前 `boardWindow.frame`，不缓存。

### 决策 2：隐身通过窗口 `alphaValue = 0` 实现，不移除窗口

复用 `WindowCoordinator.updateHUD()` 既有的 `alphaValue` 通道，在其中插入「穿透模式 && 指针在区域内 → 0」的分支；`hudOpacity` 偏好只作为可见时的取值来源，不被覆写。

*备选与取舍：*

- **`orderOut` / `orderFront`**：视觉上同为不可见，但会改变窗口的显示状态，与 `isBoardVisible`（用于菜单栏「隐藏桌面便签」）语义耦合，还会引入「因隐身而被判定为已隐藏」的分支；`hud-state-persistence` 中的可见性/几何语义也会被搅乱，放弃。
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

- [全局鼠标监听在穿透模式下的投递行为未经实测，决策 1 的前提可能不成立] → 实施第一步先做实测（启动开发版、穿透模式下移动鼠标，观察监听回调是否触发）；若不触发，退回轮询 `NSEvent.mouseLocation` 的定时器方案，规格与验收标准不受影响。
- [高频 `.mouseMoved` 回调导致主线程频繁改 alpha] → 仅在「命中状态发生变化」时写入 `alphaValue`，并用短时长 `NSAnimationContext` 过渡，避免每个移动事件都触发窗口属性写入与重绘。
- [alphaValue 由 `updateHUD()` 与监听回调两处写入而互相覆盖] → 让 `updateHUD()` 与监听回调共用同一个「依据当前模式与命中状态计算目标透明度」的函数，保证单一取值来源。
- [隐身期间指针仍在下方的应用内移动，HUD 可能被误判为应恢复显示] → 判定只看指针是否在窗口 frame 内，与下方应用无关；frame 内即隐身，逻辑上无歧义。
- [`isGhostFading` 属既有（很可能从未生效的）代码，删除它是本次改动的一部分] → 仅移除因本次改动而失效的分支；其他既有代码不动，符合 AGENTS.md 的精准改动要求。
- [只改 macOS 使 `windows-ghost-hud` 规格的跨平台一致性条款与实际脱离] → 本次接受该偏差，在任务中显式记录，不静默修改 Windows 规格。

## Migration Plan

无数据迁移。新增偏好为带默认值的 UserDefaults 布尔项，旧版本无该键时按开启处理，升级即生效；回滚只需回退代码，遗留的偏好键不影响旧版本运行。

## Open Questions

- 隐身是否需要对「窗口被其他窗口完全遮挡」的情况做额外判断（当前设计不做，仅按几何位置判定）。
