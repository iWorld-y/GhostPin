# Tasks

## 1. Core 模型与有效四象限投影

- [x] 1.1 将 `Sources/GhostPinCore/Models/TodoItem.swift` 中的 `priority: Priority` 替换为必填布尔字段 `important: Bool` 与 `urgent: Bool`，更新 `TodoItemPayload` 输出 `important` / `urgent`（移除 `priority`），移除公开 `Priority.swift`（旧版迁移私有枚举收口至迁移解码层），并在 `Tests/GhostPinCoreChecks/main.swift` 中新增与注册编解码及缺失字段拒绝用例，运行 `make test` 验证通过
- [x] 1.2 更新 `Sources/GhostPinCore/Models/HudQuadrant.swift` 与 `Sources/GhostPinCore/Stores/TodoStore.swift`：`HudQuadrant.classify(important:urgent:dueAt:nextDayStart:)` 统一作为有效象限分类入口并定义 `sortRank`（Q1 > Q2 > Q3 > Q4）；更新 `TodoStore.add` / `update` 签名与 `openItems(now:calendar:)`、`listItems`、`hudProjection`、`hudQuadrantProjection` 的排序与投影（取消已逾期全局沉底），并在 `Tests/GhostPinCoreChecks/main.swift` 中更新并新增跨日紧急升级、无截止日期紧急任务及 Q1→Q2→Q3→Q4 排序用例，运行 `make test` 验证通过

## 2. 存储格式 v3 升级与 v2/v1 迁移

- [x] 2.1 更新 `Sources/GhostPinCore/Models/TaskDocument.swift`、`Sources/GhostPinCore/Models/LegacyTodoItem.swift` 与 `Sources/GhostPinCore/Stores/TaskStorage.swift`：将 `schemaVersion` 升级为 `3`，实现锁内 v2 文档备份为 `todos.v2.backup.json` 并迁移至 v3（保留 ID、`nextID`、组别与其余字段，`high` -> `important: true`，`medium/low`/缺失 -> `important: false`，`urgent: false`），同时支持旧 v1 UUID 数组经 `todos.v1.backup.json` 直接迁移到 v3，并拒绝缺失 `important`/`urgent` 或未知版本的文档；在 `Tests/GhostPinCoreChecks/main.swift` 中补齐 v2→v3、v1→v3、备份冲突、损坏文档拒绝与并发锁写回用例并运行 `make test` 验证通过
- [x] 2.2 更新 `docs/task-storage.md`，记录 `schemaVersion: 3` 文档示例、v2→v3 与 v1→v3 迁移规则、`todos.v2.backup.json` 回退边界以及 Windows 端待后续同步适配的说明，并对照代码核对文档与字段名称完全一致

## 3. CLI 参数契约与 Agent Skill 更新

- [x] 3.1 更新 `Sources/GhostPinCLI/main.swift`：`add` 强制显式传入 `--important <true|false>` 与 `--urgent <true|false>`，`update` 支持可选 `--important` 与 `--urgent`，移除 `--priority`（报错且退出码为 2），同步更新全部子命令帮助与错误提示；在 `script/check_cli.py` 中补充 v2→v3 迁移、v1→v3 迁移、失败命令零迁移副作用、必填布尔校验与 JSON 字段契约测试，执行 `make build && python3 script/check_cli.py` 验证通过
- [x] 3.2 更新 `skills/ghostpin-cli/SKILL.md`，将新增、修改与核对示例全部切换为 `--important` 与 `--urgent`，明确上下文不明时合并确认组别、重要度、紧迫度与可选截止时间的规则并清除全部 `--priority` 引用，确认不引入禁用术语且通过 `python3 script/check_cli.py` 中的 Skill 校验

## 4. macOS HUD 卡片四档有效象限标记

- [x] 4.1 更新 `Sources/GhostPin/Views/DesktopNotesBoardView.swift` 的 `DesktopNoteRowView`，将单字 `高 / 中 / 低` 替换为四档有效象限标记（`急重` 红色、`重要` 主色、`紧急` 橙色、`稍后` 次要色），保持位于组别标记左侧并整体右对齐于 84pt 右侧信息列，同时保留逾期删除线、红色截止时间及跨日/唤醒刷新行为；执行 `make verify` 验证 App 可构建并正常启动

## 5. 端到端回归验证

- [x] 5.1 在隔离环境中完整执行 `make build && make test && python3 script/check_cli.py && make verify`，确认全部核心检查、CLI 集成检查与 macOS App 启动验证通过，且未触碰真实用户任务文件
- [x] 5.2 复核 `git status --short` 与 `git diff`，确认本次改动未修改 `windows-native/` 且覆盖 `proposal.md` 与 5 份 delta specs 中的全部需求与场景

## Workflow follow-up

- 完成实现与人工验收后，归档 `upgrade-priority-to-quadrants` 变更并将 5 份 delta specs 同步至正式规格。
- 正式升级前退出旧版 GhostPin App 与 CLI，安装新构建并执行 `ghostpin-cli init --json` 更新本地 Skill。
