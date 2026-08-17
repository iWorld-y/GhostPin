## Purpose

定义 GhostPin App 对外部写入 `todos.json` 的感知与刷新行为：Agent 通过 CLI 修改任务后，HUD 秒级自动刷新，无需重启 App，且全程不抢占用户焦点。

## Requirements

### Requirement: CLI 外部写入自动刷新

GhostPin App 运行期间，`~/Library/Application Support/GhostPin/todos.json` 被 CLI 修改后，HUD SHALL 在数秒内自动反映最新任务数据，无需重启 App；任务状态变化 MUST 触发对应的 HUD 分区和可见性更新。

#### Scenario: CLI 新增任务后 HUD 刷新

- **WHEN** GhostPin App 运行中且 Agent 通过 `ghostpin-cli add` 新增任务
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

### Requirement: 刷新不抢焦点

外部写入触发的刷新 SHALL NOT 激活 App 或夺取键盘焦点。

#### Scenario: 刷新时用户焦点不变

- **WHEN** 用户正在 VS Code 中工作且 HUD 因外部写入而刷新
- **THEN** VS Code 保持前台与键盘焦点，HUD 仅更新任务列表

### Requirement: 自身写入不引起抖动

App 自身修改任务引发的文件变化 SHALL NOT 触发无意义的重载与视图刷新。

#### Scenario: App 内操作不闪烁

- **WHEN** 用户在 HUD 交互模式下勾选完成任务
- **THEN** 任务列表平滑更新，不出现重载导致的闪烁或列表跳动

### Requirement: 监听容错

文件监听 SHALL 在存储文件暂时缺失、目录未创建或文件损坏时保持可用，不得导致 App 崩溃。

#### Scenario: App 先于首次存储运行

- **WHEN** 存储目录与 `todos.json` 尚不存在时 App 启动
- **THEN** App 正常运行，CLI 首次创建文件后 HUD 同样自动刷新

#### Scenario: 文件短暂异常

- **WHEN** 重载时文件缺失或内容暂时无法解析
- **THEN** App 保持运行，当前任务列表不被破坏，文件恢复后继续正常刷新
