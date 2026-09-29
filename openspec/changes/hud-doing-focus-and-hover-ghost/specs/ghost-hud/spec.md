# Spec Delta

## ADDED Requirements

### Requirement: 非交互模式指针移入隐身

穿透模式下，指针进入 HUD 窗口覆盖区域时 HUD MUST 完全不可见（透明度为 0），指针离开该区域后 SHALL 恢复为用户设置的 HUD 透明度。该隐身过程 MUST NOT 修改或持久化 HUD 透明度偏好，也 MUST NOT 改变穿透模式不接收鼠标事件、不夺取键盘焦点的既有行为。交互模式下 HUD MUST NOT 隐身。

#### Scenario: 指针移入即隐身

- **WHEN** HUD 处于穿透模式，指针从 HUD 覆盖区域之外移入该区域
- **THEN** HUD 变为完全不可见，指针下方的应用内容不再被遮挡，且 HUD 仍不接收鼠标事件

#### Scenario: 指针移出后恢复

- **WHEN** HUD 处于穿透模式且已因指针移入而隐身，指针随后离开 HUD 覆盖区域
- **THEN** HUD 恢复为设置中配置的透明度值

#### Scenario: 隐身不写回偏好

- **WHEN** HUD 处于穿透模式并因指针移入而隐身
- **THEN** 设置中的 HUD 透明度保持不变，重新显示或重启应用后仍为该值

#### Scenario: 交互模式不隐身

- **WHEN** HUD 处于交互模式，指针移入 HUD 覆盖区域
- **THEN** HUD 保持完全可见，并继续响应鼠标操作

#### Scenario: 切换到穿透模式时指针已在区域内

- **WHEN** 指针位于 HUD 覆盖区域内，用户将 HUD 从交互模式切换为穿透模式
- **THEN** HUD 进入穿透模式后立即处于隐身状态，无需指针先行离开再移入
