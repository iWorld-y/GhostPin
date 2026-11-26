# Spec Delta

## ADDED Requirements

### Requirement: 四象限拖动调整优先级

macOS HUD 交互模式下，四象限视图 SHALL 将每个完整象限作为落点，包括无任务的象限。将任务放到其他合法象限时，HUD MUST 按目标行设置 `important`。跨列时按目标列设置 `urgent`，同列时保留手动 `urgent`。任务状态、截止时间、组别和其他字段保持原值。目标格按现有规则排序。

#### Scenario: 从稍后处理拖入空的优先处理
- **WHEN** 用户把没有截止时间的「稍后处理」任务拖到空的「优先处理」象限
- **THEN** 任务保存为 `important: true`、`urgent: true`，出现在目标象限的原状态分区，两格计数随之更新

#### Scenario: 将手动紧急的任务拖入不紧急象限
- **WHEN** 用户把明天到期的「优先处理」任务拖到「安排时间」象限
- **THEN** 任务保留 `important: true` 和原截止时间，保存 `urgent: false`，并显示在「安排时间」

#### Scenario: 因截止时间变为紧急的任务在左侧换行
- **WHEN** 用户把一条 `urgent: false` 且今天到期的「及时处理」任务拖到「优先处理」象限
- **THEN** 任务保存为 `important: true`、`urgent: false`，继续因原截止时间显示在左列

#### Scenario: 在原象限放下任务
- **WHEN** 用户在原象限内放下任务，包括放到另一状态分区
- **THEN** HUD 结束拖动，保留任务字段和现有排序

### Requirement: 截止时间限制四象限落点

已逾期或本地今天到期的任务 SHALL 禁止投放到「安排时间」和「稍后处理」。拖过右侧时 HUD MUST 标记目标不可用并说明截止时间原因。在该位置放下时 HUD MUST 拒绝整次投放，即使目标行也发生变化。

#### Scenario: 今天到期的任务拖到右侧
- **WHEN** 用户把本地今天到期的任务拖向任一右侧象限并放下
- **THEN** HUD 告知今天到期的任务不能放入不紧急象限，任务的两个优先级字段和截止时间均维持原值

#### Scenario: 已逾期任务拖到右侧
- **WHEN** 用户把已逾期的任务拖向任一右侧象限并放下
- **THEN** HUD 告知已逾期的任务不能放入不紧急象限，也不因换行而改写重要度

#### Scenario: 拖动期间进入到期日
- **WHEN** 用户拖动原本明天到期的任务，投放时本地日期已进入到期日，且目标是不紧急象限
- **THEN** HUD 按投放时的本地日期拒绝保存，任务按最新日期的有效紧迫程度展示

### Requirement: 单列拖动切换未完成状态

macOS HUD 交互模式下，单列视图 SHALL 在拖动期间提供 Todo 和 Doing 两个落点，包括空分区或因 Doing 聚焦和条数上限被隐藏的分区。拖到另一分区时仅切换未完成状态，任务 MUST 保持未完成，优先级、组别、截止时间及其他字段保持原值。结束后临时落点消失，列表按既有范围、分区、排序和条数规则展示。

#### Scenario: 将第一条 Todo 移入空的 Doing 分区
- **WHEN** 单列当前没有 Doing 任务，用户把一条可见 Todo 拖到 Doing 落点
- **THEN** 任务保存为 Doing，HUD 更新分区与计数

#### Scenario: 在 Doing 聚焦时将任务移回 Todo
- **WHEN** 单列开启 Doing 聚焦且视图中有多条 Doing，用户将其中一条拖到 Todo 落点
- **THEN** 任务保存为 Todo，HUD 反馈「已移到 Todo」，其余 Doing 继续显示，Todo 任务按聚焦规则隐藏

#### Scenario: Doing 占满条数上限
- **WHEN** Doing 聚焦关闭且 Doing 卡片已占满条数上限，用户开始拖动一条 Doing
- **THEN** Todo 落点仍可用，临时落点不计为任务卡片

#### Scenario: 切换逾期任务的未完成状态
- **WHEN** 单列中已逾期的 Doing 任务被拖到 Todo 落点
- **THEN** 任务保存为 Todo，并保留截止时间和逾期标记
