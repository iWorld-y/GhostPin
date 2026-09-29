# Spec Delta

## MODIFIED Requirements

### Requirement: 显示配置持久化
系统 SHALL 持久化 HUD 的显示范围（全部未完成 / 今天新增）、条数上限与「有 Doing 时只显示 Doing」偏好，并在重启后恢复。「有 Doing 时只显示 Doing」在无已保存状态时的默认值 MUST 为开启。

#### Scenario: 重启恢复显示范围
- **WHEN** 用户将显示范围设为"今天新增"并设定条数上限后重启应用
- **THEN** HUD 按相同范围与上限展示任务

#### Scenario: 首次启动默认聚焦 Doing
- **WHEN** 用户首次启动应用且无已保存的 HUD 状态
- **THEN** 「有 Doing 时只显示 Doing」为开启状态，HUD 在存在 Doing 任务时只展示 Doing

#### Scenario: 重启恢复聚焦开关
- **WHEN** 用户关闭「有 Doing 时只显示 Doing」后重启应用
- **THEN** 该偏好保持关闭，HUD 同时展示 Doing 区域与 Todo 区域
