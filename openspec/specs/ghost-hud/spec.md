## Purpose

让 GhostPin 的常驻任务窗口以"幽灵 HUD"形态存在：无边框、默认置顶、透明度可调，默认不拦截鼠标事件，用户可通过托盘开关在穿透与交互模式之间切换，且全程不抢占其他应用的键盘焦点。

## Requirements

### Requirement: HUD 窗口无边框且默认置顶
HUD 窗口 SHALL 无标题栏、无可见窗口边框，SHALL 默认位于普通应用窗口之上；系统 MUST 允许用户在设置中关闭置顶行为。

#### Scenario: 无边框默认置顶
- **WHEN** HUD 处于显示状态
- **THEN** 窗口不显示标题栏与系统边框，且保持在所有普通应用窗口之上

#### Scenario: 关闭置顶
- **WHEN** 用户在设置中关闭 HUD 置顶
- **THEN** HUD 回到普通窗口层级，可被其他应用窗口覆盖

### Requirement: HUD 支持调整背景透明度
系统 SHALL 允许用户在设置中调整 HUD 背景透明度，范围为 0.5 至 1.0。

#### Scenario: 调整透明度即时生效
- **WHEN** 用户在设置中拖动透明度滑块
- **THEN** HUD 透明度立即更新，且应用重启后仍保持该值

### Requirement: HUD 默认鼠标穿透
HUD 默认 SHALL 不接收鼠标事件；用户点击 HUD 覆盖区域时，事件 MUST 传递给其下方的应用窗口。

#### Scenario: 穿透模式下点击 HUD
- **WHEN** HUD 处于穿透模式且用户点击 HUD 覆盖区域
- **THEN** 点击事件作用于 HUD 下方的应用（如 VS Code、浏览器），HUD 不产生任何响应

### Requirement: 托盘开关切换穿透与交互模式
系统 SHALL 在菜单栏托盘提供「交互模式」开关，用于在穿透与交互模式之间切换；应用 SHALL NOT 注册任何全局快捷键。交互模式下 HUD 允许通过圆形按钮推进任务状态、拖动与调整大小；穿透模式下 HUD 只展示任务、不可操作。

#### Scenario: 开关切到交互模式
- **WHEN** 用户点击托盘「交互模式」开关将其打开
- **THEN** HUD 进入交互模式，可以通过圆形按钮将 Todo 任务置为 Doing 或将 Doing 任务标记完成，并可拖动和调整大小

#### Scenario: 开关切回穿透模式
- **WHEN** HUD 处于交互模式且用户关闭托盘「交互模式」开关
- **THEN** HUD 恢复穿透模式，鼠标事件重新传递给下方应用

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

### Requirement: 模式视觉提示
HUD SHALL 以轻微、克制的视觉差异提示当前处于穿透模式还是交互模式。

#### Scenario: 两种模式外观可区分
- **WHEN** HUD 在穿透模式与交互模式之间切换
- **THEN** 外观出现可察觉但克制的变化（如描边、亮度或操作按钮可见性的差异），用户能分辨当前模式

### Requirement: 不抢焦点
HUD 出现、模式切换与任务列表刷新 SHALL NOT 激活应用或夺取键盘焦点；仅当用户切换到交互模式时，应用才可获得键盘焦点。

#### Scenario: 穿透模式下刷新不抢焦点
- **WHEN** 用户在 VS Code 中工作，HUD 后台刷新任务列表或切换穿透模式
- **THEN** VS Code 保持前台与键盘焦点，HUD 仅更新自身内容与视觉提示

#### Scenario: 交互模式获得键盘焦点
- **WHEN** 用户切换到交互模式
- **THEN** 键盘焦点转移到 HUD，可立即进行勾选操作

### Requirement: 跨 Space 与全屏显示可开关
HUD SHALL 默认显示在所有 macOS Spaces，并在其他应用全屏时仍然可见；系统 MUST 允许用户在设置中关闭此行为。

#### Scenario: 跨 Space 显示
- **WHEN** 跨 Space 显示开启且用户切换到其他 Space 或使其他应用进入全屏
- **THEN** HUD 仍保持可见

#### Scenario: 关闭跨 Space 显示
- **WHEN** 用户在设置中关闭跨 Space 显示
- **THEN** HUD 只出现在其所在的 Space，且其他应用全屏时被遮挡
