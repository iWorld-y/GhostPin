## Purpose

定义 HUD 展示哪些任务：可在全部未完成与今天新增之间切换，最多展示 N 条，已完成的任务立即从 HUD 消失。

## Requirements

### Requirement: 显示范围切换
HUD SHALL 支持两种显示范围：全部未完成任务、今天新增的未完成任务。未完成任务包括状态为 Todo 或 Doing 的任务。

#### Scenario: 展示今天新增
- **WHEN** 显示范围设为"今天新增"
- **THEN** HUD 只展示创建于今天且状态为 Todo 或 Doing 的任务

#### Scenario: 展示全部未完成
- **WHEN** 显示范围设为"全部未完成"
- **THEN** HUD 展示所有状态为 Todo 或 Doing 的任务

### Requirement: 未完成任务分区

列表视图 SHALL 将未完成任务分为 Doing 和 Todo 两个区域；当「有 Doing 时只显示 Doing」关闭时，Doing 区域 MUST 位于 Todo 区域上方，空区域 MUST 不展示。当该偏好开启且存在 Doing 任务时，列表视图 MUST 只展示 Doing 区域。每个区域内部 SHALL 沿用统一的有效四象限投影排序规则（`Q1 → Q2 → Q3 → Q4`，同象限按截止日期升序再按创建时间倒序）。

#### Scenario: 两个区域均有任务

- **WHEN** 「有 Doing 时只显示 Doing」关闭，且列表视图显示范围内同时存在 Doing（Q4「一般 · 不紧急」）和 Todo（Q1「重要 · 紧急」）任务
- **THEN** 列表视图先展示 Doing 区域，再展示 Todo 区域，且 Doing 区域中的 Q4 任务仍排在所有 Todo 任务之前

#### Scenario: 只有一个区域有任务

- **WHEN** 列表视图显示范围内只有 Doing 或只有 Todo 任务
- **THEN** 列表视图只展示有任务的区域，不展示空区域

#### Scenario: 完成 Doing 任务

- **WHEN** Doing 任务被标记为 Done
- **THEN** 任务从列表视图中消失，列表视图重新应用显示范围、分区和条数上限

#### Scenario: 同分区内按四象限投影排序

- **WHEN** Todo 区域内同时存在 Q1、Q2、Q3、Q4 任务
- **THEN** Todo 区域按 Q1 → Q2 → Q3 → Q4 依次展示

### Requirement: 条数上限跨区域生效

列表视图 SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间）。条数上限 MUST 只作用于 列表视图 实际渲染的任务集合：「有 Doing 时只显示 Doing」开启且存在 Doing 任务时作用于 Doing 任务，否则先保留 Doing 区域任务、再保留 Todo 区域任务。

#### Scenario: 聚焦 Doing 时截断 Doing

- **WHEN** 「有 Doing 时只显示 Doing」开启，Doing 任务数量超过 N
- **THEN** 列表视图 只展示按区域内排序规则排列的前 N 个 Doing 任务

#### Scenario: Doing 任务占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量不少于 N
- **THEN** 列表视图 只展示按区域内排序规则排列的前 N 个 Doing 任务，不展示 Todo 区域

#### Scenario: Doing 任务未占满上限

- **WHEN** 「有 Doing 时只显示 Doing」关闭，Doing 任务数量少于 N 且 Todo 任务数量超过剩余容量
- **THEN** 列表视图 展示全部 Doing 任务和按区域内排序规则排列的 Todo 任务，合计不超过 N 条

### Requirement: 条数上限
列表视图 SHALL 最多展示 N 条任务（N 可在设置中调整，默认值位于 5 至 10 之间），超出部分不显示。

#### Scenario: 超出上限截断
- **WHEN** 列表中未完成任务数量超过设定上限
- **THEN** HUD 只展示前 N 条，其余不显示

### Requirement: 完成即消失
任务被标记完成后 SHALL 立即从 HUD 消失。

#### Scenario: 完成任务后消失
- **WHEN** 用户在交互模式下勾选完成一条任务
- **THEN** 该任务立即从 HUD 移除，HUD 更新计数，并按当前视图的范围、分类与条数规则重新展示

### Requirement: 四象限自动分类

macOS 四象限视图 SHALL 将所选范围内每条未完成任务恰好显示一次。重要程度由任务的 `important` 决定（`true` 为重要，`false` 为一般）；紧急程度由任务的 `urgent` 与 `dueAt` 共同决定（`urgent == true`，或 `dueAt` 已逾期/本地今天到期，均为紧急；其余为不紧急）。

#### Scenario: 按重要程度和紧急程度入格

- **WHEN** 当前范围内同时存在以下四条任务：`important: true, urgent: true`（无截止日期）、`important: true, urgent: false`（无截止日期）、`important: false, urgent: false`（今天到期）、`important: false, urgent: false`（明天到期）
- **THEN** 四条任务依次出现在左上「优先处理」、右上「安排时间」、左下「及时处理」、右下「稍后处理」

#### Scenario: 跨日和任务变更

- **WHEN** 一条 `urgent: false` 且明天零点后到期的任务进入到期日，或 CLI 修改 `important`、`urgent` 或 `dueAt`
- **THEN** HUD 按当前本地日期和最新任务值更新所属象限及列表顺序

### Requirement: 四象限完整展示

四象限视图 SHALL 显示当前范围内全部 Todo 和 Doing，忽略列表条数上限及 Doing 聚焦。每格 SHALL 展示任务数并独立滚动，Doing 排在 Todo 前面，同状态沿用列表排序。空格保留标题、零计数和空状态。

#### Scenario: 范围筛选与独立滚动

- **WHEN** 选择「今天新增」，列表上限为 3 且 Doing 聚焦开启，今天创建的 6 条未完成任务集中在同一格
- **THEN** 此格可滚动查看全部 6 条，其他三格保留空状态，昨天创建的任务不计入任何象限

#### Scenario: 状态推进与计数

- **WHEN** 用户在四象限中通过任务圆钮将 Todo 推进到 Doing，随后按现有冷却规则推进到 Done
- **THEN** 第一次推进只改变格内分区，第二次从该格移除任务，格内计数和头部状态计数同步更新

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
