# Spec Delta

## ADDED Requirements

### Requirement: 新增任务显式指定重要度与紧迫度

Skill SHALL 在所有新增命令中同时显式传入 `--group <组名>`、`--important <true|false>` 与 `--urgent <true|false>`，不再使用 `--priority`。当用户或既有上下文已明确任务的重要度与紧迫度时，Agent SHALL 直接推断并显式传入，并在结果中如实汇报；当上下文无法可靠判断时，Agent MUST 与组别及可选截止时间一并向用户简洁确认，不得静默全部设为 `false`。

#### Scenario: 上下文清晰时直接显式传入四象限维度

- **WHEN** 用户明确要求“立即上线今天必须完成的 37 产线复审修复”，且组别已明确为 `37 自动化`
- **THEN** Agent 使用包含 `--group "37 自动化" --important true --urgent true --json` 的正式安装 CLI 命令，并在回复中说明任务 ID、组别与所属象限

#### Scenario: 上下文不明时合并确认维度与可选截止时间

- **WHEN** 用户仅说“帮我记一个待办：整理 Wiki 方案”，上下文未明确组别、重要度与紧迫度
- **THEN** Agent 一次性简洁确认组别、重要/紧急定位以及是否设置截止时间，不直接执行省略必选参数或全设为 `false` 的新增命令

## MODIFIED Requirements

### Requirement: 分组与整数 ID 操作说明

Skill SHALL 提供按组查询、以整数 ID 修改组别、修改重要度/紧迫度和使用默认组新增的示例。所有示例 MUST 继续使用正式安装 CLI 的完整路径并采用 `--important` / `--urgent` 参数，不再包含 `--priority`。成功结果 MUST 同时核对整数 ID、组别、`important`、`urgent` 与退出码。

#### Scenario: 阅读换组示例

- **WHEN** 安装用户阅读 Skill 的任务组别与象限修改说明
- **THEN** 示例使用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --group GhostPin --json` 与 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --important true --urgent true --json`，不含 `--priority`，并说明 ID 应来自真实查询

#### Scenario: 检查新增返回结果

- **WHEN** CLI 成功返回新增任务
- **THEN** Agent 从 `item` 中核对真实整数 ID、请求组别以及 `important` / `urgent` 布尔值，不能仅凭退出码报告字段已正确保存
