## Context

- `TodoPinCore` 已提供全部任务操作：`TodoStore`（add/setCompleted/updateTitle/update/delete/openItems/hudItems）、`StorageLocations.todosURL`、`JSONFile`（atomic 写入、ISO8601 编码）。方案 A 已定：CLI 与 App 共用该层，`todos.json` 即真源。
- 现有 `TodoStore.load()` 无条件赋值 `items`，任何重载都会触发 `objectWillChange`。
- App 层 `AppState` 是服务装配中心；`WindowCoordinator` 只管理窗口。测试为 `TodoPinCoreChecks`（可执行 check 框架，依赖仅 TodoPinCore）。
- 第一阶段已归档能力：ghost-hud（不抢焦点要求）、hud-state-persistence、hud-display-scope。

## Goals / Non-Goals

**Goals:**

- CLI 是给 Agent 用的机器接口：显式参数、稳定 JSON、明确退出码，不解析自然语言。
- App 对外部写入秒级响应、不抢焦点、自身写入零抖动。
- 不引入任何第三方依赖（手写参数解析）。

**Non-Goals:**

- 不做 MCP Server（第三阶段变更）。
- 不做 IPC / 服务进程（方案 A）。
- CLI 不解析自然语言时间；提醒时间一律 `--reminder <ISO8601>`。
- 不做任务搜索、批量操作、列表管理等扩展命令。

## Decisions

### 1. CLI 直连 TodoPinCore，文件即真源

CLI 进程每次运行独立 `TodoStore(fileURL:)` + `load()`，操作后 `save()`（atomic）退出。App 用文件监听感知变化。替代方案（App 内 IPC 服务）在第二阶段被否决（见第一阶段 interview，方案 A）。

### 2. 手写参数解析，不引入 ArgumentParser

命令集固定且小（6 个子命令 + 5 个标志），手写解析约 100 行，避免首个 Swift 第三方依赖。解析规则：第一个参数为子命令；`--flag value` 成对解析；位置参数在标志前。`add` 的标题 = 剩余位置参数以空格连接（支持不加引号的输入）。

### 3. 日期参数：ISO8601 显式传入

`--reminder` 用 `ISO8601DateFormatter`（`withInternetDateTime`）解析，接受 `2026-08-14T09:00:00Z` 与 `...+08:00` 两种形态，与存储编码策略一致。解析失败 → 用法错误（退出码 2），不写数据。

### 4. id 匹配：UUID 全等（大小写归一）

id 先 `uppercased()` 再 `UUID(uuidString:)` 解析，失败或不存在 → 错误退出码 1。不做前缀匹配——Agent 从 `list --json` 拿全量 id，全等最可靠。

### 5. update 语义

`--title` 单独指定时保留原提醒（等价 `updateTitle`）；`--reminder` 单独指定时保留原标题；`--clear-reminder` 清除提醒。实现先 `items.first(id)` 取现值再调 `update(id, title:, reminderAt:)`。三者皆无 → 用法错误（退出码 2）。

### 6. JSON 输出直接复用 TodoItem 的 Codable

`list --json` 直接 `JSONEncoder.todoPin.encode([TodoItem])`（ISO8601、prettyPrinted、sortedKeys）。单条操作用三个小结构：`CLISuccess(item)`、`CLIIdSuccess(id)`、`CLIFailure(error)`，输出 `{"ok":true,...}` / `{"ok":false,"error":...}`。错误在 JSON 模式写 stdout、文本模式写 stderr；退出码 0/1（运行错）/2（用法错）。

### 7. 文件监听：目录级 DispatchSource + debounce

监听 `todos.json` 所在**目录**的 `.write` 事件（atomic 写入 = 临时文件 + rename，目录事件必然触发；监听文件 fd 会因 rename 失效）。事件回调在主队列，用 `DispatchWorkItem` debounce 0.5 秒合并连发事件后执行 `todoStore.load()`。打开目录用 `open(path, O_EVTONLY)`，stop 时 cancel + close。文件暂时缺失/解析失败只上报 `lastErrorMessage`，不崩溃、不破坏当前列表。

### 8. 自身写入零抖动：load() 比较语义

`TodoStore.load()` 改为解码 + 排序后与当前 `items` 比较，相等则不赋值（不触发 `objectWillChange`）。App 自身写入引起的目录事件 → reload 内容相等 → 无视图更新；外部写入 → 内容不同 → 正常刷新。启动时同样受益（首次加载与初始值相等时无多余发布）。

### 9. 刷新链路

`AppState.start()` 创建 `TodoFileWatcher(todosURL)` 并回调 `todoStore.load()`；`stop()` 销毁。ReminderService 无需改动（每 60 秒 evaluate 读最新 items）。HUD 显示范围（hudItems）基于同一 store，刷新自动应用 Today/上限规则。

## Risks / Trade-offs

- [CLI 与 App 并发写竞态] → 方案 A 已接受；atomic 写入保证读者永远看到完整文件，单人本地场景概率与影响都可控。
- [外部写入覆盖编辑中状态] → HUD 交互模式编辑中若外部删除了该任务，编辑器随 item 消失；记录为已知边界，不做冲突合并。
- [DispatchSource 目录事件遗漏] → kqueue 在 APFS/HFS+ 上对目录 .write 事件支持稳定；debounce 合并事件，不依赖事件计数。
- [损坏的 todos.json 使 App 无法加载] → 仅上报错误信息，不覆盖当前列表；用户可自行修复文件或重启后处理。

## Migration Plan

- 无数据迁移：不改变存储格式与路径；`TodoStore.load()` 的语义变化对现有行为无影响（首次加载前后 items 相等不会发生，因为初始为空）。
- 回滚：删除 `todopin-cli` 产品与 TodoPinCLI target、移除 watcher 装配即可，数据不受影响。
