## 1. 构建配置与 CLI

- [x] 1.1 将 `Package.swift` 的语言模式切换为 `.v6`，不添加降级并发检查参数
- [x] 1.2 移除 CLI 共享 `ISO8601DateFormatter`，并调整顶层执行顺序以消除不可达代码警告

## 2. App 主线程隔离

- [x] 2.1 为 `AppState`、`AppDelegate`、`WindowCoordinator` 和 `HotKeyRecorder` 添加类型级 MainActor 隔离
- [x] 2.2 为 `ReminderService` 添加 MainActor 隔离，并在 Timer 回调中显式切回 MainActor
- [x] 2.3 将 `HotKeyService` 的 action 声明为 MainActor、Sendable 闭包，并在 Carbon 回调后安全调度执行

## 3. 仓库指引

- [x] 3.1 更新 `AGENTS.md`，明确全部目标使用 Swift 6 语言模式编译

## 4. 验证

- [x] 4.1 运行 `swift build`，确认全部 SwiftPM 目标在 Swift 6 模式下构建成功
- [x] 4.2 运行 `make test`，确认全部 `GhostPinCoreChecks` 通过
- [x] 4.3 运行 `make verify`，确认开发版 App 可以构建并启动
