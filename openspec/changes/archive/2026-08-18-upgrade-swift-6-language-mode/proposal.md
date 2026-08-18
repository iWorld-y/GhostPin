## Why

GhostPin 当前使用 Swift 6 工具链，却仍以 Swift 5 语言模式编译，因而没有启用 Swift 6 的完整并发安全检查。现在迁移可以尽早暴露主线程隔离与可发送闭包问题，并避免后续功能继续依赖兼容模式。

## What Changes

- 将 Swift Package 的语言模式从 Swift 5 切换为 Swift 6。
- 为 UI、窗口、提醒和快捷键录制对象补充明确的 MainActor 隔离。
- 调整 CLI 日期格式化器、Timer 与 Carbon 热键回调，使其满足 Swift 6 的并发安全要求。
- 保持现有 CLI 参数与 JSON 输出、HUD 行为、数据格式和最低 macOS 版本不变。
- 不新增依赖，不引入破坏性变更。

## Capabilities

### New Capabilities

无。本变更属于编译模式与并发隔离迁移，不引入新的产品能力。

### Modified Capabilities

无。现有规格定义的外部行为不变，因此该变更通过 `.openspec.yaml` 的 `skip_specs: true` 明确跳过 delta spec。

## Impact

- 构建配置：`Package.swift`。
- Agent 指引：`AGENTS.md` 中的语言模式说明。
- CLI：`Sources/GhostPinCLI/main.swift`。
- App 主线程边界：`AppState`、`AppDelegate`、`WindowCoordinator`、`ReminderService`、`HotKeyService` 和 `HotKeyRecorder`。
- 验证：全部 Swift 目标必须在 Swift 6 模式下构建，现有 28 项 `GhostPinCoreChecks` 必须继续通过。
- 不改变公开 API、任务数据迁移、本地通知语义或发布流程。
