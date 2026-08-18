## Context

动机见 `proposal.md`。当前 `GhostPinApp.swift` 在 `applicationDidFinishLaunching` 中执行 `NSApp.setActivationPolicy(.accessory)`，应用全程以菜单栏常驻形态运行。设置窗口是 SwiftUI `Settings` scene，其内容为 `SettingsView`。HUD 是独立 `NSPanel`（floating 层级），交互模式下的 key 状态由 `WindowCoordinator.applyHUDInteraction()` 管理。

## Goals / Non-Goals

**Goals:**

- 设置窗口打开期间让应用以 `.regular` 形态出现在 Cmd+Tab 与调度中心（含图标）。
- 设置窗口关闭后恢复 `.accessory`，不常驻 Dock。
- 不改动 HUD、托盘、快捷键注册等其他行为。

**Non-Goals:**

- 不新增 Dock 菜单或更改应用图标。
- 不修改 `WindowCoordinator`、`AppState`、Core 与 CLI。

## Decisions

### 1. 用 Settings scene 内容视图的生命周期钩子切换激活策略

在 `GhostPinApp` 的 `SettingsView` 外层使用 SwiftUI `onAppear`/`onDisappear`：打开时 `NSApp.setActivationPolicy(.regular)`，关闭时恢复 `.accessory`。

- 备选：`NSWindowDelegate` 监听设置窗口开关——SwiftUI `Settings` scene 不直接暴露 `NSWindow` 引用，需要额外桥接。
- 备选：监听 `NSApplication` 激活/失活通知——间接且容易误触发（HUD 交互也会激活应用）。
- 选 `onAppear`/`onDisappear`：与设置场景生命周期一一对应，改动最小、无桥接代码。

### 2. 只切换激活策略，不主动激活或停用应用

切换仅调用 `setActivationPolicy`（异步生效，系统在切换器刷新时体现），不调用 `NSApp.activate`，避免抢占当前前台应用焦点；恢复 `.accessory` 时不调用 `deactivate`，避免干扰交互模式下处于 key 状态的 HUD 窗口。HUD 的显示层级与穿透行为由 `WindowCoordinator` 独立管理，与激活策略无关。

## Risks / Trade-offs

- [设置关闭动画期间恢复 accessory 可能造成切换器条目闪烁] → 实机验证；若明显则改为关闭后短延时恢复。
- [设置打开期间 Dock 短暂显示图标] → 这是方案 B 的预期代价（与 Raycast 等菜单栏应用一致），在 README 不做承诺、由用户体验。
- [`.regular` 期间 Cmd+Tab 切走、设置窗口保持打开] → 正常系统行为，设置仍在切换器中，可切回。

## Migration Plan

- 无数据迁移；回滚即移除两个生命周期钩子，恢复全程 accessory。
- 验证：`make dev` 后打开设置 → Cmd+Tab 可见、调度中心有图标；关闭设置 → 恢复无 Dock；HUD 交互模式焦点与穿透不受影响。
