# Proposal

## Why

GhostPin 的任务目前集中在一个列表中，Agent 无法按项目或事项筛选，操作时还需要引用较长的 UUID。本变更同时增加任务分组和从 `10000` 开始递增的整数 ID，通过一次数据升级完成历史任务归组与编号转换。

## What Changes

- 每条任务必须属于一个分组，内置分组名为 `默认`。现有全部任务，包括已完成任务，迁入 `默认`；后续新增任务必须显式指定组别，不能自动补默认组。
- CLI 支持创建时归组、修改任务组别和按组查询。HUD 保持跨组的统一列表，沿用既有状态分区、排序、计数和显示范围；卡片标题行右侧依次展示优先级与组别标记，两个标记作为整体右对齐，组名文本最多占三个字符宽度，超出部分在宽度内尾部省略。
- **BREAKING**：任务 ID 从 UUID 改为整个本地任务库内唯一的递增整数，从 `10000` 开始。历史任务按创建时间升序稳定编号，换组不改 ID，删除不复用编号；CLI 参数和 JSON 的 `id` 同步切换，不提供 UUID 操作别名。
- **BREAKING**：任务存储升级为带版本、下一编号和任务集合的 JSON 文档。分组与整数 ID 在同一次可重入迁移中生成，迁移前保留原始备份；所有写入口通过进程间锁串行执行，避免重复编号和旧快照覆盖。
- Windows 原生端同步任务模型、新格式加载、迁移、状态写回和卡片标记，以保留分组与编号计数器并对齐标记展示；不增加 Windows CLI 或分组录入 UI。

## Capabilities

### New Capabilities

- `task-grouping`: 必填单组、内置 `默认`、名称语义及保持跨组统一列表的分组查询规则。
- `task-identifiers`: 本地任务库的整数 ID、稳定历史编号、持久化分配与删除后不复用规则。
- `task-storage`: 版本化任务文档、旧数据升级、原始备份和覆盖所有写入口的事务边界。

### Modified Capabilities

- `todo-cli`: 必填 `--group`、组内查询和换组、数字 ID 参数以及新的任务 JSON 字段。
- `todo-agent-skill`: 使用真实整数 ID、显式组别和组内查询的 Agent 操作流程。
- `product-identity`: 保留 TodoPin 原始源文件，并衔接 GhostPin 新任务格式的升级。
- `task-priority-due-description`: 在优先级右侧展示组别标记，两个标记整体右对齐，限制组名的展示宽度。
- `windows-ghost-hud`: 兼容分组与整数 ID，状态写回保留完整存储元数据，卡片标记遵循相同位置与宽度规则。

## Impact

- Swift Core：`TodoItem`、`TodoItemPayload`、`TodoStore`、`JSONFile`、`StorageLocations` 和新增的存储文档、迁移与锁实现。
- macOS App：适配整数 ID 的状态点击记录和通知标识，状态推进与提醒回写使用统一存储事务；调整 `DesktopNotesBoardView.swift` 中卡片标记的位置与组名展示，不增加分组筛选或编辑入口。
- CLI：`Sources/GhostPinCLI/main.swift` 和 `CLIOutput.swift` 的参数、帮助、输出与错误处理。
- Windows：`windows-native/src/core.rs`、`codec.rs`、`storage.rs` 及状态推进调用链的格式兼容，以及 `render.rs` 的卡片标记布局；其余视觉与任务投影规则保持原样。
- 检查与说明：Core checks、隔离的 CLI 与并发检查、`script/build_and_run.sh` 的验证隔离、卡片视觉检查、Windows 存储检查、`skills/ghostpin-cli/SKILL.md`、`AGENTS.md`、README 和新增 CHANGELOG 条目。无新增第三方依赖，不调整发布流程。
