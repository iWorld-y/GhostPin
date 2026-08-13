## Why

TodoPin 目前只能通过 App UI 操作任务。需求文档 `docs/需求-2026-08-13.md` 第二阶段的目标是让 Agent（OpenCode、Codex 等）能程序化读写任务，且外部修改后 HUD 实时刷新。方案 A（第一阶段已确认）：CLI 与 App 共用 `TodoPinCore` 的 `TodoStore`，`todos.json` 文件即真源，CLI 不解析自然语言——时间等信息全部由调用方通过显式参数传入。

## What Changes

- `Package.swift` 新增可执行产品 `todopin-cli` 与 target `TodoPinCLI`（依赖 `TodoPinCore`）。
- CLI 命令：`list`（默认未完成，`--all` 显示全部）、`add <title>`、`done <id>`、`undone <id>`、`update <id>`、`delete <id>`。
- 显式参数：`add`/`update` 支持 `--reminder <ISO8601>`；`update` 支持 `--title`、`--clear-reminder`（至少指定一项）。
- `--json` 输出契约：列表返回数组，单条操作返回 `{"ok": true, ...}`，错误返回 `{"ok": false, "error": "..."}` 且退出码非零；日期一律 ISO8601。
- `TodoStore.load()` 增加"内容未变则不触发发布"的比较语义，支撑外部写入后的安全重载。
- App 层新增文件监听服务：监听 `todos.json` 所在目录，外部写入后 debounce 重载，HUD 秒级自动刷新，全程不抢焦点。

## Capabilities

### New Capabilities

- `todo-cli`: `todopin-cli` 命令行工具的命令集、显式参数、JSON 输出契约与错误处理。
- `hud-live-refresh`: App 对外部写入 `todos.json` 的感知与自动刷新行为（文件监听、防抖、不抢焦点、自身写入不抖动）。

### Modified Capabilities

（无。第一阶段归档的三个能力不受影响。）

## Impact

- 代码：
  - `Package.swift`：新增 `todopin-cli` 可执行产品与 `TodoPinCLI` target。
  - `Sources/TodoPinCLI/`（新增）：参数解析、命令分发、文本与 JSON 输出、错误与退出码。
  - `Sources/TodoPinCore/Stores/TodoStore.swift`：`load()` 增加内容比较语义。
  - `Sources/TodoPin/Services/TodoFileWatcher.swift`（新增）：目录级 DispatchSource 监听 + debounce。
  - `Sources/TodoPin/App/AppState.swift`：启动/停止 watcher，外部变化时 `todoStore.load()`。
  - `Tests/TodoPinCoreChecks/main.swift`：新增 `TodoStore.load()` 重载语义的 checks。
- 依赖：无新增第三方依赖（Foundation DispatchSource）。
- 风险：CLI 与 App 并发写同一文件的竞态（方案 A 已接受，单人本地使用）；外部写入覆盖编辑中状态（记录为已知边界）。
