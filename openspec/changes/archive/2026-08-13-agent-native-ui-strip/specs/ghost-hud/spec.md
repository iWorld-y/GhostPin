## ADDED Requirements

### Requirement: 托盘开关切换穿透与交互模式

系统 SHALL 在菜单栏托盘提供「交互模式」开关，用于在穿透与交互模式之间切换；应用 SHALL NOT 注册任何全局快捷键。交互模式下 HUD 允许勾选完成、拖动与调整大小；穿透模式下 HUD 只展示任务、不可操作。

#### Scenario: 开关切到交互模式

- **WHEN** 用户点击托盘「交互模式」开关将其打开
- **THEN** HUD 进入交互模式，可以勾选完成、拖动和调整大小

#### Scenario: 开关切回穿透模式

- **WHEN** HUD 处于交互模式且用户关闭托盘「交互模式」开关
- **THEN** HUD 恢复穿透模式，鼠标事件重新传递给下方应用

## MODIFIED Requirements

### Requirement: 不抢焦点

HUD 出现、模式切换与任务列表刷新 SHALL NOT 激活应用或夺取键盘焦点；仅当用户切换到交互模式时，应用才可获得键盘焦点。

#### Scenario: 穿透模式下刷新不抢焦点

- **WHEN** 用户在 VS Code 中工作，HUD 后台刷新任务列表或切换穿透模式
- **THEN** VS Code 保持前台与键盘焦点，HUD 仅更新自身内容与视觉提示

#### Scenario: 交互模式获得键盘焦点

- **WHEN** 用户切换到交互模式
- **THEN** 键盘焦点转移到 HUD，可立即进行勾选操作

## REMOVED Requirements

### Requirement: 全局快捷键切换穿透与交互模式

**Reason**: Agent native 转型移除整个全局快捷键系统（避免与其他软件快捷键冲突）；模式切换改由托盘开关承担。
**Migration**: 穿透/交互切换改点菜单栏托盘「交互模式」开关；原 ⌥⌘T 快捷键不再生效。
