## Purpose

保证 HUD 的窗口几何、外观、模式与显示配置在应用重启后自动恢复，用户无需每次重新摆放窗口或重复配置。

## ADDED Requirements

### Requirement: HUD 窗口几何持久化
系统 SHALL 持久化 HUD 窗口的位置与尺寸，并在应用重启后恢复。

#### Scenario: 重启恢复位置与尺寸
- **WHEN** 用户在交互模式下调整 HUD 位置与尺寸后重启应用
- **THEN** HUD 以相同的位置与尺寸出现

### Requirement: HUD 外观与模式持久化
系统 SHALL 持久化 HUD 的透明度、置顶开关、跨 Space 开关与穿透/交互模式。

#### Scenario: 重启恢复模式
- **WHEN** 用户将 HUD 置于交互模式（或穿透模式）后重启应用
- **THEN** HUD 以相同模式启动

#### Scenario: 重启恢复外观设置
- **WHEN** 用户修改透明度、置顶或跨 Space 设置后重启应用
- **THEN** 这些设置原样生效

### Requirement: 显示配置持久化
系统 SHALL 持久化 HUD 的显示范围（全部未完成 / 今天新增）与条数上限，并在重启后恢复。

#### Scenario: 重启恢复显示范围
- **WHEN** 用户将显示范围设为"今天新增"并设定条数上限后重启应用
- **THEN** HUD 按相同范围与上限展示任务

### Requirement: 默认穿透启动
HUD 在无已保存状态时（首次启动）SHALL 默认处于穿透模式。

#### Scenario: 首次启动为穿透
- **WHEN** 用户首次启动应用且无已保存的 HUD 状态
- **THEN** HUD 以穿透模式显示
