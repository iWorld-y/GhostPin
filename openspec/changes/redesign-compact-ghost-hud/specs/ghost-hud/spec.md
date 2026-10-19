# Spec Delta

## ADDED Requirements

### Requirement: macOS HUD 紧凑列表

macOS HUD SHALL 使用细分隔线列表呈现任务，不再为每条任务绘制独立的圆角卡片和渐变。面板圆角 SHALL 为 14 pt，默认宽度 SHALL 为 380 pt，最小宽度 SHALL 为 320 pt。正文滚动区域 SHALL 不超过 396 pt，Doing 与 Todo 分区头 SHALL 在滚动时吸顶。无已保存尺寸时，初始高度 SHALL 随实际内容确定；已有窗口尺寸 SHALL 继续按持久化规则恢复。

#### Scenario: 首次展示列表

- **WHEN** HUD 没有已保存的窗口尺寸且显示多条任务
- **THEN** HUD 使用 380 pt 宽的紧凑列表，各任务之间以细线分隔，正文高度按内容确定且不超过 396 pt

#### Scenario: 任务内容超出正文高度

- **WHEN** 当前允许展示的任务内容超过正文可见高度
- **THEN** 正文允许滚动，当前分区头吸顶，底部淡出提示不得阻止任务按钮的操作

#### Scenario: 恢复已有窗口

- **WHEN** 用户此前已调整并保存 HUD 窗口尺寸后重启应用
- **THEN** HUD 保留已保存的尺寸，并在窗口内应用紧凑列表布局

### Requirement: macOS HUD 头尾信息

macOS HUD SHALL 在头部同一行展示应用标识、名称、显示范围内的完整 Doing 与 Todo 计数及隐藏窗口按钮。分区头 SHALL 展示各状态在当前范围内的完整计数。底部 SHALL 展示当前模式、实际渲染条数与范围内总条数、当前范围；仅在模式快捷键已启用且存在有效配置时展示对应快捷键。HUD SHALL 不提供撤销完成入口。

#### Scenario: Doing 聚焦隐藏 Todo

- **WHEN** Doing 聚焦已开启，当前范围内同时存在 Doing 与 Todo
- **THEN** 头部仍展示两种状态的完整计数，Doing 分区头展示完整 Doing 计数，底部展示实际渲染条数与两种状态合计条数

#### Scenario: 条数上限截断

- **WHEN** 当前范围内任务总数超过设置的条数上限
- **THEN** 头部与分区计数不被截断，底部的实际渲染条数只统计按上限保留的任务

#### Scenario: 没有启用模式快捷键

- **WHEN** 模式快捷键关闭或尚未配置
- **THEN** HUD 底部不展示任何固定或推测的快捷键

#### Scenario: 完成任务

- **WHEN** Doing 任务被推进为 Done
- **THEN** 任务立即消失且计数更新，HUD 不出现撤销或重开按钮

### Requirement: macOS HUD 系统外观

macOS HUD SHALL 使用系统材质和随系统浅深色外观变化的语义颜色。行悬停 SHALL 提供轻微背景反馈，键盘聚焦 SHALL 提供可辨认的焦点提示。穿透模式 SHALL 隐藏关闭按钮但保留其布局位置；模式透明度与指针进入后的隐身 SHALL 继续使用现有设置和行为，不采用原型写死的不透明度。

#### Scenario: 切换系统外观

- **WHEN** 系统在浅色与深色外观之间切换
- **THEN** HUD 的材质、文字、分隔线与状态控件同步适配，任务信息保持可辨认

#### Scenario: 切换穿透模式

- **WHEN** HUD 从交互模式切换为穿透模式
- **THEN** 关闭按钮隐藏且头部其余信息不移位，窗口继续使用用户设置的穿透透明度

#### Scenario: 穿透模式下移入指针

- **WHEN** 指针移入穿透模式 HUD 后再移出
- **THEN** HUD 按现有规则隐身并恢复，保存的透明度设置不被改写

### Requirement: macOS HUD 紧凑空态

当实际渲染集合为空时，macOS HUD SHALL 显示紧凑的「没有未完成待办」说明，以及包含显式 `--group` 的 CLI 新增示例。空态正文 SHALL 以 80 pt 为初始内容高度，继续展示头尾信息；已保存或用户调整的窗口尺寸 SHALL 优先。空态 SHALL 不新增任务录入控件。

#### Scenario: 首次展示空态

- **WHEN** 当前显示范围内没有未完成任务且没有保存窗口尺寸
- **THEN** HUD 按紧凑空态内容确定初始高度，展示说明、有效的 CLI 示例和零条数信息

#### Scenario: 今天范围为空

- **WHEN** 其他日期仍有未完成任务但今天新增范围为空
- **THEN** HUD 展示空态，底部范围仍为今天新增，条数以当前范围计算

### Requirement: macOS HUD 状态控件外观

macOS HUD SHALL 用实心圆表示 Doing、空心圆表示 Todo。状态按钮的命中区域 SHALL 不小于 27 pt 高，且不得覆盖标题文字。交互模式下按钮 SHALL 可通过键盘触发，并继续使用既有状态推进及 500 ms 点击冷却。

#### Scenario: 区分任务状态

- **WHEN** HUD 同时展示 Doing 与 Todo 任务
- **THEN** 两种状态的圆形按钮轮廓不同，Doing 使用实心圆，Todo 使用空心圆

#### Scenario: 键盘推进状态

- **WHEN** 交互模式下状态按钮获得键盘焦点并被触发
- **THEN** 执行与点击相同的单次状态推进，冷却窗口内重复触发不继续推进
