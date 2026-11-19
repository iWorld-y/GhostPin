# Proposal

## Why

单列适合常驻桌面，但任务多时很难看出哪些工作重要、哪些快到期。macOS HUD 需要能展开为四象限供用户安排工作，回到穿透模式时收为列表，减少桌面占用。

## What Changes

- 交互模式可选择列表或四象限。四象限按现有任务的优先级与截止时间自动分类，每格可单独滚动。
- 四象限显示所选范围内全部未完成任务；列表继续使用条数上限和 Doing 聚焦。
- 切回穿透模式时窗口收为紧凑列表，再进入交互模式时恢复上次主动选择的视图。该选择跨重启保存，首次使用默认列表。

## Capabilities

### New Capabilities

### Modified Capabilities

- `ghost-hud`：定义 macOS HUD 的视图选择、模式切换和窗口收展。
- `hud-display-scope`：定义象限分类、计数与状态分区，并限定列表截断规则的适用范围。
- `hud-state-persistence`：保存交互视图偏好并在启动时按 HUD 模式恢复。

## Impact

涉及 GhostPinCore 的任务投影、macOS HUD、窗口协调与 UserDefaults 偏好。沿用当前任务文件和 CLI 契约。设计参考为 `design/quadrants-draft.html`，本次范围为 macOS。
