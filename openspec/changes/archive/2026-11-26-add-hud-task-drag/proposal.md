# Proposal

## Why

GhostPin 的四象限视图能显示任务优先级，但调整优先级需要使用 CLI。单列视图可以通过圆形按钮把 Todo 推进到 Doing，却缺少直接将 Doing 放回 Todo 的交互。

## What Changes

- 在 macOS HUD 交互模式下为任务卡片提供拖拽手柄。四象限视图支持拖到其他象限以调整优先级，单列视图支持拖到 Todo 或 Doing 以切换状态。
- 今天到期或已逾期的任务无法放入右侧两个不紧急象限。拖动时提示原因，取消或拒绝投放时保留已保存的任务。
- 单列开始拖动时临时显示 Todo 和 Doing 落点，即使对应分区没有卡片。投放后按现有范围、排序、条数上限和 Doing 聚焦重新展示。

## Capabilities

### New Capabilities

### Modified Capabilities

- `ghost-hud` 增加任务拖动入口、取消行为和持久化结果反馈，保留圆形状态按钮和窗口操作。
- `hud-display-scope` 定义两种视图的落点、字段更新和日期限制。

## Impact

改动涉及 macOS 的 `DesktopNotesBoardView`、`AppState` 和 `GhostPinCore` 的任务写入。实现沿用任务文件锁和刷新机制。对外 CLI、任务文档格式和 Windows HUD 沿用现有契约。
