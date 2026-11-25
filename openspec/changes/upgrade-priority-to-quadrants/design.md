# Design

## Context

动机见 `proposal.md` 的 Why。当前代码与规格中与本变更直接相关的现状如下：

- `TodoItem`（`Sources/GhostPinCore/Models/TodoItem.swift`）持有线性三档 `priority: Priority`（`high / medium / low`，默认 `.medium`）和可选 `dueAt: Date?`。
- `HudQuadrant.classify`（`Sources/GhostPinCore/Models/HudQuadrant.swift`）用 `priority == .high` 推导重要、用 `dueAt < nextDayStart` 推导紧急；当 `priority` 走默认值且 `dueAt` 为空时全部落入 `generalNotUrgent`（Q4）。
- `TodoStore.isOrderedBefore`（`Sources/GhostPinCore/Stores/TodoStore.swift`）按 `status (Doing 优先) -> 非逾期优先于逾期 -> priority 降序 -> dueAt 升序（nil 在后）-> createdAt 倒序` 排列未完成任务，与四象限中“已逾期=紧急”的语义相反。
- `TaskDocument` 与 `TaskStorage`（`Sources/GhostPinCore/Models/TaskDocument.swift`、`Sources/GhostPinCore/Stores/TaskStorage.swift`）当前固定为 `schemaVersion == 2`，在固定 `.todos.lock` 内支持旧 v1 UUID 数组经 `todos.v1.backup.json` 一次性迁移到 v2。
- `DesktopNotesBoardView`（`Sources/GhostPin/Views/DesktopNotesBoardView.swift`）在任务卡片标题行右侧 84pt 列内并排展示单字优先级标记与三汉字宽度上限的组别标记，且 `AppState` 已监听跨日（`.NSCalendarDayChanged`）与系统唤醒（`NSWorkspace.didWakeNotification`）刷新投影。
- `ghostpin-cli`（`Sources/GhostPinCLI/main.swift`）的 `add` 已强制校验 `--group` 必填，在访问存储前完成参数与帮助校验；`script/check_cli.py` 与 `Tests/GhostPinCoreChecks/main.swift` 覆盖隔离目录迁移与 CLI 契约。

## Goals / Non-Goals

**Goals:**

- 将任务原生优先级模型从一维三档升级为正交双轴（`important: Bool` + `urgent: Bool`），使四象限视图无损直出、单列视图按统一四象限优先级线性投影。
- 保留 `dueAt` 作为可选客观截止时间，在投影层自动将已逾期或本地当天到期的任务提升为有效紧急，且不篡改持久化 `urgent`。
- 将存储平滑升级至 `schemaVersion: 3`，保持固定 `.todos.lock`、逐字节备份不可覆盖和失败命令零迁移副作用等既有安全保证。
- 在 CLI 入口强制显式指定 `--important` 与 `--urgent` 并同步更新 Skill 契约，避免新任务再次静默塌陷到 Q4。

**Non-Goals:**

- 本次不修改 `windows-native/` 及 `windows-ghost-hud` 规格，不依赖 Rust/Windows 工具链。
- 不在 macOS HUD 中新增拖拽改象限、任务编辑表单或分组筛选交互，继续严守「HUD 仅推进状态（Todo -> Doing -> Done）」的 Agent-native 边界。
- 不引入第三方依赖，不保留 `--priority` 兼容别名，不提供自动降级回 v2 的能力。

## Decisions

### 1. 正交双轴 `important` + `urgent` 替代 `Priority` 枚举

在 `TodoItem` 中用 `public var important: Bool` 与 `public var urgent: Bool` 替代 `priority: Priority`，并在构造器与 `TodoStore.add` 中移除两者的默认值（调用方必须显式传入，与 `group` 保持一致）。移除公开 `Priority` 类型，仅在旧版迁移解码层保留内部 `LegacyPriority` 以解析历史 v1/v2 数据。

选择正交双轴而非单个 4 值枚举（如 `quadrant: q1..q4`）的原因：
- **与 `dueAt` 动态紧急升级语义自洽**：有效紧急定义为 `effectiveUrgent = item.urgent || (dueAt != nil && dueAt < nextDayStart)`。一条 `important: true, urgent: false` 且带明天 `dueAt` 的任务在进入当天后自动投射到 Q1，而持久化层仍忠实记录 `urgent: false`，避免“存储写着 Q2、界面显示在 Q1”的歧义；延后或清除 `dueAt` 时自动回落到 Q2。
- **支持单轴局部更新**：`update <id> --urgent true` 可直接翻转紧迫度而不影响重要度。

### 2. 统一有效四象限排序作为 2D -> 1D 单列投影

在 `HudQuadrant` 上定义确定性的列表投影排序权值（`sortRank`）：
1. `.importantUrgent`（Q1：重要 · 紧急）
2. `.importantNotUrgent`（Q2：重要 · 不紧急）
3. `.generalUrgent`（Q3：一般 · 紧急）
4. `.generalNotUrgent`（Q4：一般 · 不紧急）

`HudQuadrant.classify(important: Bool, urgent: Bool, dueAt: Date?, nextDayStart: Date)` 作为唯一分类入口，供四象限投影与单列排序共同调用。`TodoStore.openItems(now:calendar:)` 与 `listItems` 传入日历计算 `nextDayStart`，排序规则统一为：
1. `status`（`doing` 优先于 `todo`）
2. 有效象限 `sortRank`（Q1 -> Q2 -> Q3 -> Q4，采用“重要优先”以防琐碎急事把重要事项挤出单列上限）
3. `dueAt` 升序（有截止日期排在无截止日期之前；更早逾期或更早到期者在前）
4. `createdAt` 倒序（同创建时间按 `id` 降序）

**取消原有“已逾期全局沉底”规则**：已逾期任务本就满足 `dueAt < nextDayStart`，在两套视图中统一按紧急（Q1/Q3）排前，并继续通过卡片红色删除线与红色截止时间做超时警示，消除列表与四象限的语义割裂。

### 3. 存储升级至 `schemaVersion: 3` 与 v2/v1 双路径一次迁移

`TaskDocument` 的 `schemaVersion` 升至 `3`，校验每条任务具备合法整数 `id`、规范化非空 `group`，且 JSON 解码强制要求 `important` 与 `urgent` 为布尔值（缺失或类型错误拒绝加载）。

在 `TaskStorage.readLatest()` 锁内按顶层 JSON 形态分流：
- **JSON 数组（v1 旧格式）**：沿用既有 `LegacyTodoItem` 解码、`createdAt` + 小写 UUID 稳定排序编号、`group = "默认"`，并按 `important = (legacyPriority == .high)`、`urgent = false` 生成 v3 文档；备份文件固定为 `todos.v1.backup.json`。
- **JSON 对象且 `schemaVersion == 2`（v2 旧格式）**：通过独立的 `LegacyV2TaskDocument` / `LegacyV2TodoItem` 校验并解码（校验 v2 的 `nextID`、唯一 ID、组名与旧优先级，缺失旧 `priority` 按 `medium` 兼容），保留 `nextID` 及全部字段不变，按 `important = (legacyPriority == .high)`、`urgent = false` 转换为 v3 文档；备份文件固定为 `todos.v2.backup.json`。
- **JSON 对象且 `schemaVersion == 3`**：直接按新 `TaskDocument` 解码并校验，不产生备份。
- **其他版本或非法结构**：抛出 `TaskStorageError.invalidDocument`，保留原文件与 App 最后一次有效快照。

`preserveBackup(_:fileName:)` 统一复用于 `todos.v1.backup.json` 与 `todos.v2.backup.json`：使用 `O_CREAT | O_EXCL` 写入，若文件已存在且内容逐字节相同则复用，内容不同则抛出 `backupConflict` 中止迁移。写操作先校验业务目标是否存在，失败时直接退出，不写备份、不提交迁移。

### 4. CLI 显式双参数与 JSON 契约

- `add <标题> --group <组名> --important <true|false> --urgent <true|false>`：三项全部必填，在访问存储前完成解析；仅接受精确的 `true` / `false`，避免模糊真值解析导致误判。
- `update <id>`：支持独立可选的 `--important <true|false>` 与 `--urgent <true|false>`，至少指定一项修改参数；未传入的字段保留锁内最新值。
- 移除 `--priority`：在 `add` 与 `update` 中均按未知参数报错（退出码 2），不触发存储迁移。
- `TodoItemPayload` 输出 `important` 与 `urgent`（JSON 布尔值），移除 `priority`；其余字段（含整数 `id`、`group`、`isCompleted`、ISO 8601 日期等）保持不变。
- `list` 默认输出使用 `TodoStore.listItems(includeCompleted:group:now:calendar:)` 的新有效象限排序；`list --all` 仍保持创建时间倒序全量输出。

### 5. macOS HUD 卡片四档标记

`DesktopNoteRowView` 复用同一个有效象限值（由投影时计算的 `HudQuadrant` 或结合 `nextDayStart` 推导），将原单字 `高 / 中 / 低` 替换为双字有效象限标记，保持位于组别标记左侧、整体右对齐于既有 84pt 右侧信息列：
- Q1（`importantUrgent`）：`急重`，红色、semibold
- Q2（`importantNotUrgent`）：`重要`，主色（`.primary.opacity(0.84)`）、semibold
- Q3（`generalUrgent`）：`紧急`，橙色（`.orange`）、semibold
- Q4（`generalNotUrgent`）：`稍后`，次要色（`.secondary`）、regular

双字 10pt 标记宽约 20pt，加上三汉字组名胶囊（约 38pt）与 4pt 间距合计约 62pt，稳妥落在 84pt 列宽内，无需拓宽卡片或破坏最小 320pt 列表宽度布局。

### 6. Agent Skill 与文档同步

- 更新 `skills/ghostpin-cli/SKILL.md`：明确新增必填 `--group`、`--important`、`--urgent`，上下文不明确时合并询问（附带可选截止时间），修改与查询示例全部切换为新参数并核对返回的 `important` / `urgent`。
- 更新 `docs/task-storage.md`：记录 `schemaVersion: 3` 格式、v2 -> v3 迁移规则、`todos.v2.backup.json` 备份与回退边界，以及 Windows 端留待后续适配的说明。

## Risks / Trade-offs

- [升级后旧版 CLI 或 Windows 端无法读写 v3 文件] -> 升级前退出旧 macOS App 与 CLI，随 App Bundle 同步更新 `ghostpin-cli` 并运行 `init` 更新 Skill；Windows 端本次不改动，在 `docs/task-storage.md` 中明确标注版本边界与后续适配计划。
- [存量 v2 任务的 `medium` 全部迁为 `important: false, urgent: false` 后，未完成任务初始仍在 Q4] -> 这是最安全无损的机械映射（不擅自猜测业务重要度）；迁移完成后用户可直接通过更新后的 Agent Skill 一次性梳理现存未完成任务，后续全部新任务在入口即完成四象限分类。
- [新增必填参数增至 3 个增加口头录入摩擦] -> 在 `SKILL.md` 中要求 Agent 优先从明确上下文推断并显式传入，仅在信息确实不足时用一句话合并确认组别、重要/紧急与可选 deadline，避免多轮追问。
- [取消“逾期全局沉底”改变既有列表习惯] -> 逾期任务仍保留红色标题删除线与红色截止时间，且进入 Q1/Q3 前部与四象限视图行为完全统一，避免紧急任务因刚过截止时刻突然从单列视野消失。

## Migration Plan

1. 在临时隔离目录中构造 v1 旧数组、v2 文档（含 `high`/`medium`/`low` 与缺失 `priority`）和 v3 文档测试夹具，覆盖成功迁移、冲突备份、失败命令零副作用、跨日紧急升级与单列排序。
2. 正式升级前退出旧版 GhostPin App 与运行中的旧 CLI，安装包含新版本 App 与随包 `ghostpin-cli` 的构建，并执行 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli init --json` 同步 Agent Skill。
3. 首次成功访问时在 `.todos.lock` 内自动生成 `todos.v2.backup.json` 并原子升级 `todos.json` 至 `schemaVersion: 3`；随后通过 `list --json` 核对任务总数、ID、`nextID` 与字段完整性。
4. 如需回退：先退出新进程并另存当前 v3 `todos.json`，再视需要恢复 `todos.v2.backup.json` 为 `todos.json` 并切回旧版本程序（回退不含升级后新增或修改的数据，不提供自动降级）。
