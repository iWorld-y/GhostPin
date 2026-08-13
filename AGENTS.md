# AGENTS.md

## 项目概述

TodoPin 是一个本地优先的 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager），支持文本快速录入、可选本地语音识别（whisper.cpp）、桌面便签与本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6（包声明 `swiftLanguageModes: [.v5]`）。

## 架构边界（易错点）

- `Sources/TodoPinCore/`：纯业务逻辑层（Model、TodoStore、ReminderPolicy、TodoTimeParser、JSON 存储），**不得 import AppKit/SwiftUI**，保证可被测试目标独立编译运行。
- `Sources/TodoPin/`：应用层（AppDelegate、窗口管理、全局快捷键、通知、语音录制），`@main` 入口在 `App/TodoPinApp.swift`。
- `Tests/TodoPinCoreChecks/`：可执行测试目标，**不是 XCTest**（详见下节）。
- 业务逻辑新增应放入 `TodoPinCore`，App 层通过 `AppState` 薄封装调用。

## 常用命令

```bash
swift build                        # 构建
swift run TodoPinCoreChecks        # 运行核心行为检查（测试）
./script/build_and_run.sh          # 打包 .app 并运行（run 默认）
./script/build_and_run.sh --verify # 打包并验证进程可启动（CI 式验证）
./script/build_and_run.sh --logs   # 运行并跟踪统一日志（--telemetry 按 subsystem 过滤）
./script/package_dmg.sh            # 打包 DMG；TODO_PIN_INCLUDE_MODEL=1 捆绑语音模型
./script/fetch_models.sh           # 下载语音模型到 Sources/TodoPin/Resources/Models/
```

## 测试（最容易猜错）

- 没有 XCTest。测试是 `Tests/TodoPinCoreChecks/main.swift` 里注册的 `checks` 数组，新增用例必须手动加入该数组，否则不会被执行。
- 运行：`swift run TodoPinCoreChecks`；任一用例失败输出 `FAIL` 并以退出码 1 结束。
- 用例中时间解析固定使用东八区（GMT+8）zh_CN 日历，不要改动。

## 数据与依赖

- 数据存于 `~/Library/Application Support/TodoPin/`（`todos.json`、`summaries.json`），偏好存 UserDefaults。路径定义在 `Sources/TodoPinCore/Support/StorageLocations.swift`。
- 语音模型 `ggml-base-q5_1.bin` 被 gitignore，需 `./script/fetch_models.sh` 下载（SHA-256 校验）；模型缺失时应用仍可手动输入。
- `WhisperFramework` 是远程 binaryTarget（whisper.cpp 预编译 XCFramework），首次构建需要网络；不要修改其 checksum。
- 全局快捷键：文本快速录入默认 `Option + Space`、语音 `F8`（Carbon 注册），两者不可相同，App 层会校验。

## 变更流程

- 未来需求规划见 `docs/需求-2026-08-13.md`（HUD 悬浮/点击穿透/CLI/MCP Server 等），**均为规划，尚未实现**，不要当作已存在功能。
- 实现变更走 OpenSpec 流程（`openspec/config.yaml`，schema: spec-driven）：用 `.opencode` / `.claude` 下的 `opsx-propose` → `opsx-apply` → `opsx-archive` skills 或 `/opsx-*` 命令。
- 无 CI、无 lint/formatter 配置（无 swiftlint/swiftformat）；代码风格为无注释、简短直白、类型标注完整，保持现状即可。
- 仓库已索引 CodeGraph（`.codegraph/`），探索代码优先用 codegraph explore。

## 环境要求

- macOS 14+、Xcode 命令行工具、SPM。构建产物 `.build/`、`dist/` 均被 gitignore。
- 应用为 accessory 激活策略（无 Dock 图标），运行验证用 `./script/build_and_run.sh --verify`。
