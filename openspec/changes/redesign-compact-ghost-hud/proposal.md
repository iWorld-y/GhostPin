# Proposal

## Why

现有 macOS HUD 的卡片内边距、卡间距和渐变占用了较多空间，长标题也会压缩右侧标记的位置。采用已查看的「GhostPin UI 重设计」草案，以紧凑列表呈现任务，让标题、优先级、组别和截止时间更容易扫读。

## What Changes

- 将独立卡片改为细分隔线列表，任务行使用状态按钮、标题与描述、固定宽度元信息三列；标题最多两行，描述最多一行。
- 采用系统材质、14 pt 圆角和浅深色语义颜色，移除现有多层彩色渐变。Doing 使用实心圆，Todo 使用空心圆；高优先级和逾期保留红色语义。
- 将名称与 Doing、Todo 完整计数放在同一行，分区头显示完整计数并支持吸顶；底部展示模式、实际显示条数和范围，快捷键提示只在用户已启用配置时出现。
- 保留草案遗漏的组别标记，仍放在优先级右侧，组名文本宽度不超过三个汉字。
- 默认宽度调整为 380 pt、最小宽度为 320 pt；正文最多展示 396 pt 后滚动。无已保存尺寸时按内容确定初始高度，已保存的窗口尺寸继续优先恢复；空态使用紧凑说明和包含 `--group` 的 CLI 示例。
- 排除「撤销完成」及原型外围的演示按钮。继续沿用现有状态推进、500 ms 点击冷却、Doing 聚焦、显示范围、条数上限、透明度、悬停隐身、跨 Space 与窗口持久化行为。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `ghost-hud`：补充 macOS HUD 的紧凑列表、系统外观、头尾状态和空态要求。
- `task-priority-due-description`：更新任务行的三列布局、标题与描述行数以及优先级颜色，保留组别与截止时间语义。

## Impact

- 主要影响 `Sources/GhostPin/Views/DesktopNotesBoardView.swift` 和 `Sources/GhostPin/App/WindowCoordinator.swift`；仅在实现需要时提取同目录视图组件。
- 继续消费 `TodoStore.hudProjection`，不改变任务模型、存储格式、公开 CLI、设置项和快捷键配置契约，不新增依赖。
- 使用隔离任务目录运行 `make test`、`make verify`，并在原生 App 中检查布局和交互。只有确需新增 Core 行为时才添加并注册相应 Core 检查。
- 本次范围为 macOS；Windows 原生界面的视觉样式不随本次变更同步。
