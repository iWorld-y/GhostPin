## Purpose

定义 HUD 展示哪些任务：可在全部未完成与今天新增之间切换，最多展示 N 条，已完成的任务立即从 HUD 消失。

## ADDED Requirements

### Requirement: 显示范围切换
HUD SHALL 支持两种显示范围：全部未完成任务、今天新增的未完成任务。

#### Scenario: 展示今天新增
- **WHEN** 显示范围设为"今天新增"
- **THEN** HUD 只展示创建于今天且未完成的任务

#### Scenario: 展示全部未完成
- **WHEN** 显示范围设为"全部未完成"
- **THEN** HUD 展示所有未完成任务

### Requirement: 条数上限
HUD SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间），超出部分不显示。

#### Scenario: 超出上限截断
- **WHEN** 未完成任务数量超过设定上限
- **THEN** HUD 只展示前 N 条，其余不显示

### Requirement: 完成即消失
任务被标记完成后 SHALL 立即从 HUD 消失。

#### Scenario: 完成任务后消失
- **WHEN** 用户在交互模式下勾选完成一条任务
- **THEN** 该任务立即从 HUD 移除，HUD 重新应用显示范围与条数上限
