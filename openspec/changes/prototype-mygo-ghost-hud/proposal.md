# Proposal

## Why

GhostPin 的 macOS 和 Windows 桌面端分别维护界面与窗口逻辑。用 mygo 原生 UI 统一重写前，先在 macOS 上确认 mygo 能承接幽灵 HUD 的穿透隐身、焦点归还与跨 Space 行为。

## What Changes

- 在实验分支新增独立的 macOS HUD 原型，应用代码使用 Go、mygo 原生 `ui` 和 mygo 公开 API，菜单栏提供显示或隐藏、模式切换、置顶、跨 Space 和退出入口。
- 用内置任务演示紧凑列表和键鼠状态推进，验证窗口穿透、完全隐身后恢复、焦点切换、全屏可见性以及双屏拖动和缩放。
- 提供可复现的启动方式与 macOS 桌面验收记录，写明哪些行为通过、哪些出现差异，以及差异涉及的 mygo API。
- 正式投影与四象限、设置页、任务存储、CLI、提醒、快捷键和 Windows 移植留待后续变更。

## Capabilities

### New Capabilities

- `standalone-hud-prototype` 定义隔离运行的 HUD 原型及其窗口行为和验收要求。

### Modified Capabilities

无。

## Impact

- 实验代码和验收说明位于 `experiments/mygo-hud/`，使用独立 Go 模块和原型应用身份。任务和控制状态均保存在内存中。
- 图形验收需要可交互的 macOS 桌面。原型使用独立入口构建，正式应用及其交付链路继续通过现有入口构建。
