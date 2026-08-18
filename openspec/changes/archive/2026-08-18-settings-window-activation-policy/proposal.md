## Why

GhostPin 以 accessory 激活策略运行（菜单栏应用，无 Dock 图标），因此设置窗口不会出现在 Cmd+Tab 应用切换器中，调度中心里也不显示应用图标；用户在其他应用工作时打开设置后，很难通过系统切换器找回该窗口。

## What Changes

- 设置窗口打开期间，应用激活策略临时切换为 `.regular`，使设置窗口出现在 Cmd+Tab 应用切换器中，并在调度中心显示应用图标。
- 设置窗口关闭后，应用恢复 `.accessory`，不常驻 Dock 图标，保持菜单栏应用定位。
- 未打开设置时的默认行为不变：无 Dock 图标、不进入 Cmd+Tab。
- HUD 的穿透/交互模式、窗口层级与键盘焦点行为不变。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `product-identity`: 新增「设置窗口期间的应用切换器可见性」要求：设置打开时应用出现在系统应用切换器中，关闭后恢复菜单栏常驻形态。

## Impact

- 修改 `Sources/GhostPin/App/GhostPinApp.swift`：在 Settings scene 的打开与关闭时机切换 `NSApplication` 激活策略。
- 不影响 Core、CLI、HUD 窗口管理与快捷键注册逻辑。
- 验证覆盖：设置打开时 Cmd+Tab 可见、调度中心显示图标、关闭设置后恢复 accessory、HUD 焦点与穿透行为不变。
