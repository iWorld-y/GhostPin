## MODIFIED Requirements

### Requirement: HUD 视觉标记

HUD SHALL 展示优先级标记以区分三档；过期任务 SHALL 使用删除线标注；任务的描述 SHALL 以较小字体展示。HUD 任务卡片的时间行 MUST 只展示截止日期 `dueAt`；截止日期为空时 MUST 不显示时间。过期任务的截止时间 MUST 使用与标题删除线相同的红色超时语义。HUD SHALL NOT 展示创建时间或提醒时间。

#### Scenario: 优先级标记

- **WHEN** 一条任务具有「高」优先级
- **THEN** HUD 以可辨识的标记（如颜色或图标）区分其优先级

#### Scenario: 过期删除线

- **WHEN** 一条任务已过期且未完成
- **THEN** HUD 以删除线标注该任务标题

#### Scenario: 描述小字体

- **WHEN** 一条任务具有描述文本
- **THEN** HUD 以小于标题的字体展示该描述

#### Scenario: 有截止日期时显示截止时间

- **WHEN** 一条任务具有截止日期
- **THEN** HUD 以日期与时刻格式展示该截止日期，不展示创建时间与提醒时间

#### Scenario: 无截止日期时不显示时间

- **WHEN** 一条任务没有截止日期
- **THEN** HUD 不显示任何时间

#### Scenario: 过期截止时间变红

- **WHEN** 一条任务已过期且未完成
- **THEN** HUD 以红色展示该任务的截止时间
