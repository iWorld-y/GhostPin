# Spec Delta

## ADDED Requirements

### Requirement: macOS HUD 的交互视图与收展

macOS HUD SHALL 在交互模式提供列表和四象限选择。穿透模式 MUST 使用紧凑列表。通过菜单栏或已配置的模式快捷键切换时，HUD SHALL 按同一规则收展，并保留原有穿透及指针隐身行为。

#### Scenario: 从四象限往返

- **WHEN** 用户在交互模式选择四象限，切回穿透模式
- **THEN** HUD 收为列表，窗口恢复列表尺寸，点击穿透至下方应用
- **WHEN** 用户再次进入交互模式
- **THEN** HUD 展开为四象限窗口

#### Scenario: 从列表往返

- **WHEN** 用户在交互模式选择列表，切回穿透模式后再进入交互模式
- **THEN** HUD 始终显示列表

#### Scenario: 指针离开

- **WHEN** 用户保持交互模式并将指针移出四象限窗口
- **THEN** 四象限保持展开
