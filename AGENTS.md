# AGENTS.md

## 项目概述

GhostPin 是一个 **Agent native** 的本地优先 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager）：任务的新增/修改/删除由 Agent 按 `skills/ghostpin-cli/SKILL.md` 通过随应用分发的 CLI 完成，App 只负责展示（桌面幽灵 HUD，无边框置顶、默认鼠标点击穿透）与本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6（包声明 `swiftLanguageModes: [.v5]`）。

**Agent native 约束（易踩坑）**：UI 上唯一的写入口是 HUD 的「勾选完成」（`setCompleted`）；其余写操作必须先读取 `skills/ghostpin-cli/SKILL.md`，再通过固定 App Bundle 路径中的 `ghostpin-cli` 完成。CLI 支持优先级、截止日期、描述和逐命令帮助。App 通过文件监听秒级刷新。不要给 App 层加任何录入/编辑 UI 或全局快捷键（唯一例外：设置「高级」页中默认关闭的可选交互模式切换快捷键，见 `openspec/specs/ghost-hud`）。

## 架构边界（易错点）

- `Sources/GhostPinCore/`：纯业务逻辑层（Model、TodoStore、JSON 存储），**不得 import AppKit/SwiftUI**，保证可被测试目标独立编译运行。
- `Sources/GhostPin/`：应用层（AppDelegate、窗口管理、托盘菜单、通知、文件监听、可选全局快捷键），`@main` 入口在 `App/GhostPinApp.swift`。默认不注册全局快捷键；可选交互模式切换快捷键仅在用户于「高级」设置启用并配置后注册（Carbon 仅用于该单一注册）。
- `Sources/GhostPinCLI/`：`ghostpin-cli` 可执行工具（参数解析、输出格式化），依赖 GhostPinCore。
- `Tests/GhostPinCoreChecks/`：可执行测试目标，**不是 XCTest**（详见下节）。
- 业务逻辑新增应放入 `GhostPinCore`，App 层通过 `AppState` 薄封装调用。

## 常用命令

```bash
make help                           # 查看常用开发命令
make dev                            # 构建并启动开发版 App
make restart                        # 构建并重启开发版 App
make stop                           # 停止 App
make test                           # 运行核心行为检查（测试）
make verify                         # 构建并验证进程可启动
make logs                           # 启动并跟踪统一日志
make telemetry                      # 启动并跟踪 GhostPin subsystem 日志
make cli ARGS='list --json'         # 执行开发版 CLI
make dmg                            # 构建并校验 DMG
```

需要时也可以直接调用 `swift` 或 `script/` 下的底层命令。

## 测试（最容易猜错）

- 没有 XCTest。测试是 `Tests/GhostPinCoreChecks/main.swift` 里注册的 `checks` 数组，新增用例必须手动加入该数组，否则不会被执行。该目标依赖 GhostPinCore，覆盖任务字段、状态、排序、持久化和文件监听行为。
- 运行：`swift run GhostPinCoreChecks`；任一用例失败输出 `FAIL` 并以退出码 1 结束。
- 用例中时间解析固定使用东八区（GMT+8）zh_CN 日历，不要改动。

## 数据与依赖

- 数据存于 `~/Library/Application Support/GhostPin/`（`todos.json`），偏好存 UserDefaults。路径定义在 `Sources/GhostPinCore/Support/StorageLocations.swift`。
- 提醒为「定时提醒」：`reminderAt` 到点发本地通知并记录 `reminderSentAt`；无每小时提醒、无免打扰时段（ReminderPolicy/ReminderSettings 已删除）。

## 变更流程

- `docs/需求-2026-08-13.md` 的幽灵 HUD 与 CLI 阶段已实现并归档，正式规格在 `openspec/specs/`，新需求可在此基础上另开变更。
- 实现变更走 OpenSpec 流程（`openspec/config.yaml`，schema: spec-driven）：用 `.opencode` / `.claude` 下的 `opsx-propose` → `opsx-apply` → `opsx-archive` skills 或 `/opsx-*` 命令。
- 无 CI、无 lint/formatter 配置（无 swiftlint/swiftformat）；代码风格为无注释、简短直白、类型标注完整，保持现状即可。
- 仓库已索引 CodeGraph（`.codegraph/`），探索代码优先用 codegraph explore。

## 环境要求

- macOS 14+、Xcode 命令行工具、SPM。构建产物 `.build/`、`dist/` 均被 gitignore。
- 应用为 accessory 激活策略（无 Dock 图标），运行验证用 `./script/build_and_run.sh --verify`。
