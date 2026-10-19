# Spec Delta

## MODIFIED Requirements

### Requirement: 安全定位并修改任务

Skill SHALL 使用 `--json` 获取机器可读结果；修改已有任务前 MUST 通过 `list --all --json` 或显式指定组别的全量 JSON 查询获取真实整数 ID，不得使用旧 UUID、列表序号或推测编号。标题匹配不唯一时 MUST 请求用户消歧，删除后 MUST 再次查询确认目标 ID 不存在。

#### Scenario: 同名任务需要消歧

- **WHEN** 用户按标题要求修改任务且查询结果中存在多个同名任务
- **THEN** Agent 列出候选任务的整数 ID 和组别并等待用户选择，不擅自修改

#### Scenario: 删除后确认

- **WHEN** Agent 成功执行删除命令
- **THEN** Agent 再次执行全量 JSON 查询并确认对应整数 ID 已不存在后才报告完成

#### Scenario: 按组定位任务

- **WHEN** 用户明确要求修改 `GhostPin` 组内的任务
- **THEN** Agent 可使用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --group GhostPin --all --json` 获取真实整数 ID 后操作

## ADDED Requirements

### Requirement: 新增任务显式指定组别

Skill SHALL 在所有新增命令中显式传入 `--group <组名>`。用户或既有明确上下文未确定组别时，Agent MUST 先确认组别，不得因为存在 `默认` 而自动选择默认组；用户已明确选择 `默认` 时可以直接使用。

#### Scenario: 用户指定默认组

- **WHEN** 用户要求在 `默认` 组新增任务
- **THEN** Agent 使用包含 `--group 默认` 和 `--json` 的正式安装 CLI 命令

#### Scenario: 尚未确定新增任务的组别

- **WHEN** 新增请求及既有明确上下文均未确定组别
- **THEN** Agent 先询问组别，不执行省略 `--group` 的新增命令

### Requirement: 分组与整数 ID 操作说明

Skill SHALL 提供按组查询、以整数 ID 修改组别和使用默认组新增的示例。所有示例 MUST 继续使用正式安装 CLI 的完整路径，成功结果 MUST 同时核对整数 ID、组别与退出码。

#### Scenario: 阅读换组示例

- **WHEN** 安装用户阅读 Skill 的任务组别修改说明
- **THEN** 示例使用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --group GhostPin --json`，并说明 ID 应来自真实查询

#### Scenario: 检查新增返回结果

- **WHEN** CLI 成功返回新增任务
- **THEN** Agent 从 `item` 中核对真实整数 ID 与请求组别，不能仅凭退出码报告字段已正确保存
