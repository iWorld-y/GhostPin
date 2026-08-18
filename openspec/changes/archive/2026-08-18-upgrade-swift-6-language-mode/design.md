## Context

见 `proposal.md` 的动机。当前 `Package.swift` 使用 `swiftLanguageModes: [.v5]`；在临时副本切换到 `.v6` 后，`GhostPinCore` 可直接编译，但 CLI 的共享 `ISO8601DateFormatter`、App 的主线程对象、Timer 回调和 Carbon 热键回调会触发 Swift 6 并发安全诊断。

本变更跨越 Package、CLI 和 App 层，但不改变数据模型、产品规格或外部接口。AppKit/SwiftUI 对象必须继续只在主线程访问，Carbon 回调则需要显式跨越到 MainActor。

## Goals / Non-Goals

**Goals:**

- 让全部 SwiftPM 目标以 Swift 6 语言模式构建。
- 用明确的 actor 与 Sendable 边界表达现有主线程约束，避免使用关闭检查的编译参数。
- 保持 CLI、HUD、提醒、快捷键和持久化行为不变。
- 保持 Core 检查通过，并完成 App 启动验证。

**Non-Goals:**

- 不重构 `TodoStore`、数据格式或提醒策略。
- 不增加 async/await 业务流程、依赖或新的产品能力。
- 不改变最低 macOS 版本、CLI 契约或发布流程。

## Decisions

### 1. 将 App 编排对象隔离到 MainActor

为 `AppState`、`AppDelegate`、`WindowCoordinator`、`ReminderService` 和 `HotKeyRecorder` 标注 `@MainActor`。这些对象拥有 SwiftUI/AppKit 状态或只由应用主线程驱动，类型级隔离比逐方法标注更符合其真实生命周期，也能避免遗漏窗口属性访问。

替代方案是逐个方法标注，或用 `nonisolated(unsafe)` 压制诊断。前者容易形成不一致边界，后者会隐藏潜在数据竞争，因此不采用。

### 2. 在系统回调边界显式切换到 MainActor

`ReminderService` 的 Timer 回调通过 `Task { @MainActor in ... }` 调用 `evaluate`。Carbon 事件处理仍保留在非隔离的 `HotKeyService` 中，但其 `action` 声明为 `@MainActor @Sendable`，触发时通过 MainActor Task 执行。

不把整个 `HotKeyService` 标为 MainActor，因为 C 事件处理函数没有 actor 隔离语义，强行隔离会把问题转移到回调入口。

### 3. 消除 CLI 的共享非 Sendable 格式化器

移除文件级 `ISO8601DateFormatter`，在日期解析函数内创建格式化器。CLI 为短生命周期串行进程，这点对象创建成本可忽略，同时避免为共享 Foundation 引用类型引入锁或 `nonisolated(unsafe)`。

### 4. 保持 Swift 6 构建告警可审计

将 CLI 的顶层执行块放到辅助函数声明之后，避免 Swift 6 把顶层 `exit` 之后的声明报告为不可达代码。除该机械调整外，不改变退出码或错误输出。

### 5. 直接启用 Swift 6 语言模式

将 `Package.swift` 改为 `swiftLanguageModes: [.v6]`，不使用 `-strict-concurrency=minimal` 或其他降级检查参数。迁移完成的判断以干净构建、Core 检查和 App 启动验证为准。

## Risks / Trade-offs

- [系统回调经 Task 调度后可能晚一个主线程调度周期执行] → 保持回调逻辑短小，并通过 App 启动与交互路径验证；不在 Task 中加入额外等待。
- [类型级 MainActor 标注可能暴露新的跨线程调用] → 逐个修复调用边界，不使用 `nonisolated(unsafe)` 绕过检查。
- [CLI 局部创建格式化器有轻微重复开销] → CLI 命令只解析少量日期，优先选择明确的并发安全边界。
- [工具链或 SDK 不匹配会产生与代码无关的构建错误] → 使用仓库当前选中的、SDK 匹配的 Xcode/Swift 工具链执行最终验证，并区分环境故障与源码诊断。

## Migration Plan

1. 切换 Swift 语言模式并修复 CLI 的全局状态和顶层执行顺序。
2. 为 App 主线程对象添加类型级隔离，修复 Timer 与 Carbon 回调边界。
3. 更新 `AGENTS.md` 的编译模式说明，避免仓库指引继续声称使用 Swift 5 模式。
4. 运行 `swift build`、`make test` 和 `make verify`。
5. 若出现无法接受的运行时回归，整体回退本变更；本迁移不涉及数据或配置迁移，无需数据回滚。
