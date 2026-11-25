# Proposal

## Why

当前任务模型使用一维线性优先级（`high / medium / low`，默认 `medium`）并搭配稀疏的可选截止时间 `dueAt`。在单列视图中可以低摩擦记录，但切换到四象限视图时，由于缺少紧迫度输入且默认走 `medium` + 无 `dueAt`，真实任务几乎全部塌陷到右下角「稍后处理（一般 · 不紧急）」，导致四象限失效且列表与四象限对逾期任务的排序语义相互冲突。将任务的原生优先级模型升维为四象限（重要度 × 紧迫度）后，四象限视图成为无损展示，单列视图成为确定性的降维投影，从数据模型根源统一两种视图。

## What Changes

- **BREAKING** 用正交双轴（`important: Bool` 重要度 + `urgent: Bool` 紧迫度）替代原有线性三档 `priority`（`high / medium / low`）；`dueAt` 保留为可选截止时间，当任务已逾期或本地当天到期时在投影层自动视为紧急，不改写存储中的 `urgent`。
- **BREAKING** 将 macOS 任务存储文档从 `schemaVersion: 2` 升级为 `schemaVersion: 3`，在固定 `.todos.lock` 内支持从 v2 文档一次性备份（`todos.v2.backup.json`）并迁移到 v3（原 `high` 映为 `important: true`，`medium/low` 映为 `important: false`，`urgent` 初始为 `false`），同时保留旧 v1 UUID 数组经 `todos.v1.backup.json` 直接迁移到 v3 的路径。
- **BREAKING** 统一四象限向单列列表的线性投影排序：同状态（Doing 在 Todo 前）内按 `Q1(重要·紧急) > Q2(重要·不紧急) > Q3(一般·紧急) > Q4(一般·不紧急)` 排序，同象限内按 `dueAt` 升序（无截止时间排后）与创建时间倒序；取消原有「已逾期任务全局沉底」规则，使列表与四象限对逾期语义一致。
- **BREAKING** 更新 `ghostpin-cli`：`add` 强制显式传入 `--important <true|false>` 与 `--urgent <true|false>`（与 `--group` 一致，不静默默认落入 Q4），`update` 支持独立修改 `--important` 与 `--urgent`，移除 `--priority` 参数；JSON 输出以布尔字段 `important` 与 `urgent` 替代 `priority`。
- 更新 `skills/ghostpin-cli/SKILL.md` 的 Agent 操作契约，明确新增任务时显式提供重要度、紧迫度与可选截止时间的确认及结果核对规则。
- 更新 macOS HUD 任务卡片标记：由 `高 / 中 / 低` 升级为四档有效象限标记（`急重 / 重要 / 紧急 / 稍后`），保持在组别标记左侧并整体右对齐。
- 本次范围限定为 macOS（Core、CLI、macOS App、Skill、文档与检查），不修改 `windows-native/` 及 Windows 规格。

## Capabilities

### New Capabilities

（无新增顶层能力，本次在现有能力规格上演进。）

### Modified Capabilities

- `task-priority-due-description`：以正交双轴 `important` / `urgent` 与有效象限替代线性三档优先级，更新单列投影排序（重要优先，取消逾期沉底）及 macOS HUD 卡片标记规范。
- `task-storage`：将版本化任务文档升级至 `schemaVersion: 3`，定义 v2 -> v3（含 `todos.v2.backup.json`）与 v1 -> v3（含 `todos.v1.backup.json`）的一次性锁内迁移及校验规则。
- `hud-display-scope`：更新四象限自动分类输入（`important` 与 `urgent || 当天到期/已逾期`），统一四象限与列表同状态排序规则。
- `todo-cli`：将 `add` / `update` / `list --json` / 帮助文本与参数校验从 `--priority` 切换为 `--important` 与 `--urgent`，并强制新增显式传参。
- `todo-agent-skill`：要求 Agent 新增任务时显式提供 `--important` 与 `--urgent`、上下文不明时与组别合并确认，并核对返回 JSON 字段。

## Impact

- **Core（Swift）**：`Sources/GhostPinCore/` 中的 `TodoItem`、`TaskDocument`、`TaskStorage`、`TodoItemPayload`、`LegacyTodoItem`、`HudQuadrant`、`TodoStore`（移除公开 `Priority` 类型，仅在旧版迁移解码层保留私有兼容枚举）。
- **macOS App & CLI**：`Sources/GhostPin/Views/DesktopNotesBoardView.swift`、`Sources/GhostPinCLI/main.swift`、`skills/ghostpin-cli/SKILL.md`、`docs/task-storage.md`。
- **测试与校验**：`Tests/GhostPinCoreChecks/main.swift`、`script/check_cli.py`。
- **非本次范围**：`windows-native/` 与 `windows-ghost-hud` 不在本次变更内，后续在具备 Rust/Windows 工具链的变更中另行适配 `schemaVersion: 3`。
