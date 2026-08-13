# AGENTS.md

## 项目概述

TodoPin 是一个 **Agent native** 的本地优先 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager）：任务的新增/修改/删除一律通过 MCP 由 Agent 完成，App 只负责展示（桌面幽灵 HUD，无边框置顶、默认鼠标点击穿透）与本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6（包声明 `swiftLanguageModes: [.v5]`）。

**Agent native 约束（易踩坑）**：UI 上唯一的写入口是 HUD 的「勾选完成」（`setCompleted`）；其余写操作必须走 MCP/CLI（`todopin-cli mcp` 或 `todopin-cli`），App 通过文件监听秒级刷新。不要给 App 层加任何录入/编辑 UI 或全局快捷键。

## 架构边界（易错点）

- `Sources/TodoPinCore/`：纯业务逻辑层（Model、TodoStore、JSON 存储），**不得 import AppKit/SwiftUI**，保证可被测试目标独立编译运行。
- `Sources/TodoPin/`：应用层（AppDelegate、窗口管理、托盘菜单、通知、文件监听），`@main` 入口在 `App/TodoPinApp.swift`。无全局快捷键（Carbon 已移除）。
- `Sources/TodoPinMCP/`：MCP 服务器协议与工具实现（纯 Foundation 库，不 import AppKit/SwiftUI，可被测试目标 import）。
- `Sources/TodoPinCLI/`：`todopin-cli` 可执行工具（参数解析、输出格式化），依赖 TodoPinCore 与 TodoPinMCP。
- `Tests/TodoPinCoreChecks/`：可执行测试目标，**不是 XCTest**（详见下节）。
- 业务逻辑新增应放入 `TodoPinCore`，App 层通过 `AppState` 薄封装调用。

## 常用命令

```bash
swift build                        # 构建
swift run TodoPinCoreChecks        # 运行核心行为检查（测试）
./script/build_and_run.sh          # 打包 .app 并运行（run 默认）
./script/build_and_run.sh --verify # 打包并验证进程可启动（CI 式验证）
./script/build_and_run.sh --logs   # 运行并跟踪统一日志（--telemetry 按 subsystem 过滤）
./script/package_dmg.sh            # 打包 DMG
swift run todopin-cli list --json   # CLI 查询任务（add/done/undone/update/delete 同理）
swift run todopin-cli mcp           # 以 MCP stdio 服务器模式运行（供 OpenCode 等 Agent）
```

## 测试（最容易猜错）

- 没有 XCTest。测试是 `Tests/TodoPinCoreChecks/main.swift` 里注册的 `checks` 数组，新增用例必须手动加入该数组，否则不会被执行。该目标同时依赖 TodoPinCore 与 TodoPinMCP，MCP 消息编解码与工具行为同样在此覆盖。
- 运行：`swift run TodoPinCoreChecks`；任一用例失败输出 `FAIL` 并以退出码 1 结束。
- 用例中时间解析固定使用东八区（GMT+8）zh_CN 日历，不要改动。

## 数据与依赖

- 数据存于 `~/Library/Application Support/TodoPin/`（`todos.json`），偏好存 UserDefaults。路径定义在 `Sources/TodoPinCore/Support/StorageLocations.swift`。
- 提醒为「定时提醒」：`reminderAt` 到点发本地通知并记录 `reminderSentAt`；无每小时提醒、无免打扰时段（ReminderPolicy/ReminderSettings 已删除）。

## 变更流程

- `docs/需求-2026-08-13.md` 的三阶段规划（幽灵 HUD / CLI / MCP Server）均已实现并归档，正式规格在 `openspec/specs/`（ghost-hud、hud-state-persistence、hud-display-scope、todo-cli、hud-live-refresh、todo-mcp-server 六个能力），新需求可在此基础上另开变更。
- 实现变更走 OpenSpec 流程（`openspec/config.yaml`，schema: spec-driven）：用 `.opencode` / `.claude` 下的 `opsx-propose` → `opsx-apply` → `opsx-archive` skills 或 `/opsx-*` 命令。
- 无 CI、无 lint/formatter 配置（无 swiftlint/swiftformat）；代码风格为无注释、简短直白、类型标注完整，保持现状即可。
- 仓库已索引 CodeGraph（`.codegraph/`），探索代码优先用 codegraph explore。

## 环境要求

- macOS 14+、Xcode 命令行工具、SPM。构建产物 `.build/`、`dist/` 均被 gitignore。
- 应用为 accessory 激活策略（无 Dock 图标），运行验证用 `./script/build_and_run.sh --verify`。
