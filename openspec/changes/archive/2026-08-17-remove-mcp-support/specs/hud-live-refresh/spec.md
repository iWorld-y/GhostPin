## ADDED Requirements

### Requirement: CLI 外部写入自动刷新

App 运行期间，`todos.json` 被 CLI 修改后，HUD SHALL 在数秒内自动反映最新任务数据，无需重启 App；任务状态变化 MUST 触发对应的 HUD 分区和可见性更新。

#### Scenario: CLI 新增任务后 HUD 刷新
- **WHEN** App 运行中且 Agent 通过 `todopin-cli add` 新增任务
- **THEN** 数秒内 HUD 自动显示该任务，无需任何手动操作

#### Scenario: CLI 完成任务后 HUD 刷新
- **WHEN** Agent 通过 `todopin-cli done <id>` 完成某任务
- **THEN** 数秒内该任务从 HUD 消失

#### Scenario: CLI 设置 Doing 后 HUD 刷新
- **WHEN** Agent 通过 `todopin-cli doing <id>` 将 Todo 任务设置为 Doing
- **THEN** 数秒内该任务出现在 Doing 区域，并从 Todo 区域移除

## REMOVED Requirements

### Requirement: 外部写入自动刷新
**Reason**: 原要求包含已删除入口的场景，刷新契约现统一由新的“CLI 外部写入自动刷新”要求承载。
**Migration**: 使用 `todopin-cli` 修改任务；App 继续通过相同的文件监听机制刷新 HUD。
