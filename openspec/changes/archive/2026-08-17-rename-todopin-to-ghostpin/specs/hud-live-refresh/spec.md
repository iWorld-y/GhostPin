## MODIFIED Requirements

### Requirement: CLI 外部写入自动刷新

GhostPin App 运行期间，`~/Library/Application Support/GhostPin/todos.json` 被 CLI 修改后，HUD SHALL 在数秒内自动反映最新任务数据，无需重启 App；任务状态变化 MUST 触发对应的 HUD 分区和可见性更新。

#### Scenario: CLI 新增任务后 HUD 刷新
- **WHEN** App 运行中且 Agent 通过 `ghostpin-cli add` 新增任务
- **THEN** 数秒内 HUD 自动显示该任务，无需任何手动操作

#### Scenario: CLI 完成任务后 HUD 刷新
- **WHEN** Agent 通过 `ghostpin-cli done <id>` 完成某任务
- **THEN** 数秒内该任务从 HUD 消失

#### Scenario: CLI 设置 Doing 后 HUD 刷新
- **WHEN** Agent 通过 `ghostpin-cli doing <id>` 将 Todo 任务设置为 Doing
- **THEN** 数秒内该任务出现在 Doing 区域，并从 Todo 区域移除

#### Scenario: 迁移旧数据后继续监听
- **WHEN** GhostPin 首次启动时从旧 TodoPin 目录迁移任务文件
- **THEN** HUD 显示迁移后的任务，并持续监听 GhostPin 数据目录中的后续 CLI 写入
