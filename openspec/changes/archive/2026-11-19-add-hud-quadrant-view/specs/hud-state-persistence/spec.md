# Spec Delta

## ADDED Requirements

### Requirement: 记住交互模式下的视图选择

macOS HUD MUST 持久化用户在交互模式最后一次主动选择的视图，缺少该偏好时 SHALL 使用列表。自动收为列表 MUST 保留此偏好。

#### Scenario: 首次进入交互模式

- **WHEN** 首次安装或从未保存视图偏好的版本升级后进入交互模式
- **THEN** HUD 使用列表

#### Scenario: 从穿透模式重启

- **WHEN** 用户选择四象限，切回穿透模式，退出并重新启动
- **THEN** HUD 以穿透列表启动，进入交互模式后恢复四象限

#### Scenario: 从交互模式重启

- **WHEN** 用户在交互模式选择列表或四象限并重启应用
- **THEN** HUD 恢复交互模式与所选视图，包括用户从四象限主动改回列表的情况
