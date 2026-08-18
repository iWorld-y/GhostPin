## 1. 激活策略切换实现

- [x] 1.1 在 `GhostPinApp.swift` 的 Settings scene 内容上增加打开/关闭生命周期钩子：打开设置时 `NSApp.setActivationPolicy(.regular)`，关闭时恢复 `.accessory`。
- [x] 1.2 确认切换只改激活策略，不调用 `activate`/`deactivate`，不影响 HUD 穿透与交互焦点逻辑。

## 2. 文档与规格同步

- [x] 2.1 在实现完成后将 `product-identity` delta spec 同步合并到主规格。

## 3. 验证

- [x] 3.1 执行 `swift build` 与 `swift run GhostPinCoreChecks`，确认构建与核心逻辑不受影响。
- [x] 3.2 手动验证：打开设置后应用出现在 Cmd+Tab 与调度中心（含图标）；关闭设置后恢复无 Dock 图标形态；HUD 交互模式焦点与穿透行为不变。
