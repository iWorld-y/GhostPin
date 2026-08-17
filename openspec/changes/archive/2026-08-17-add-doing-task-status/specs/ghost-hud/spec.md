## MODIFIED Requirements

### Requirement: 托盘开关切换穿透与交互模式

系统 SHALL 在菜单栏托盘提供「交互模式」开关，用于在穿透与交互模式之间切换；应用 SHALL NOT 注册任何全局快捷键。交互模式下 HUD 允许通过圆形按钮推进任务状态、拖动与调整大小；穿透模式下 HUD 只展示任务、不可操作。

#### Scenario: 开关切到交互模式
- **WHEN** 用户点击托盘「交互模式」开关将其打开
- **THEN** HUD 进入交互模式，可以通过圆形按钮将 Todo 任务置为 Doing 或将 Doing 任务标记完成，并可拖动和调整大小

#### Scenario: 开关切回穿透模式
- **WHEN** HUD 处于交互模式且用户关闭托盘「交互模式」开关
- **THEN** HUD 恢复穿透模式，鼠标事件重新传递给下方应用

## ADDED Requirements

### Requirement: 圆形按钮推进任务状态

交互模式下，HUD 任务卡片的现有圆形按钮 SHALL 按任务当前状态推进状态：Todo 第一次有效点击进入 Doing，Doing 下一次有效点击进入 Done；状态变化 MUST 立即反映在 HUD 分区中。

#### Scenario: Todo 点击进入 Doing
- **WHEN** 用户在交互模式下点击 Todo 任务的圆形按钮一次
- **THEN** 任务立即变为 Doing，并从 Todo 区域移动到 Doing 区域

#### Scenario: Doing 点击完成
- **WHEN** 用户在交互模式下点击 Doing 任务的圆形按钮一次，且距离上次状态变化已超过 500ms
- **THEN** 任务变为 Done，并从 HUD 中消失

### Requirement: 状态点击冷却

HUD 在一次圆形按钮状态变化成功后 500ms 内 SHALL 忽略同一任务卡片的后续点击，避免短时间连续点击将 Todo 误推进为 Done。

#### Scenario: 冷却窗口内重复点击
- **WHEN** 用户完成一次状态点击后在 500ms 内再次点击同一任务的圆形按钮
- **THEN** 任务状态不再变化，HUD 不执行第二次状态转换

#### Scenario: 冷却窗口结束后再次点击
- **WHEN** 用户完成一次状态点击后等待超过 500ms，再次点击同一任务的圆形按钮
- **THEN** 点击按任务当前状态执行下一次允许的状态转换
