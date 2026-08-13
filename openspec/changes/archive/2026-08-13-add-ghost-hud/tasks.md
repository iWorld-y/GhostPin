## 1. Core 层：显示范围与模式类型

- [x] 1.1 `TodoPinCore` 新增 `HudScope` 枚举（`all` / `today`，Codable、Sendable），放入 `Sources/TodoPinCore/Models/`
- [x] 1.2 `TodoStore` 新增 `hudItems(scope:maxCount:now:calendar:)`：按范围过滤未完成任务后截断 N 条
- [x] 1.3 `TodoPinCoreChecks` 新增 checks：today 范围日界过滤（东八区固定日历）、all 范围、N 条截断、完成即消失；`swift run TodoPinCoreChecks` 全绿

## 2. 偏好与快捷键预设

- [x] 2.1 `AppPreferences` 新增键：`hudFrame`（JSON 编码）、`hudOpacity`（Double，默认 1.0）、`hudMode`（String，默认穿透）、`hudScope`（String，默认 all）、`hudMaxItems`（Int，默认 8）、`hudAllSpaces`（Bool，默认 true）；置顶沿用现有 `keepBoardOnTop`
- [x] 2.2 `HotKeyPreset` 新增 `.optionCommandT`（keyCode 17，modifiers 2304，显示名 "⌥⌘T"）并加入 `presets`

## 3. 窗口层：HUD 形态与两态模式

- [x] 3.1 `WindowCoordinator` 将 boardWindow `styleMask` 改为 `[.borderless, .resizable]`，移除标题栏相关配置，保留 `isMovableByWindowBackground` 与 minSize
- [x] 3.2 `WindowCoordinator` 新增 `updateHUDMode()`：应用 `ignoresMouseEvents`、`alphaValue`、frame 恢复、collectionBehavior（`hudAllSpaces` 决定是否保留 `.canJoinAllSpaces/.fullScreenAuxiliary`）
- [x] 3.3 `AppState` 新增 `toggleHUDMode()` 并注册第三个全局快捷键（id 3，`⌥⌘T`），三快捷键两两互斥校验与现有逻辑一致
- [x] 3.4 焦点处理：切交互 `makeKeyAndOrderFront` + 激活；切穿透 `resignKey` + `deactivate`，HUD 出现沿用 `orderFrontRegardless`
- [x] 3.5 frame 持久化：`windowDidMove` / `windowDidResize` 保存；恢复时校验与任一 `NSScreen.frame` 相交，否则居中回落

## 4. 视图层：HUD 视觉与交互

- [x] 4.1 `DesktopNotesBoardView` 将 `hudMode` 并入 `isActive` 判断：穿透模式隐藏操作按钮、静止外观；交互模式显示操作按钮
- [x] 4.2 任务列表改用 `hudItems(scope:maxCount:)` 数据源，接入显示范围与条数上限
- [x] 4.3 模式视觉提示：复用现有 active/inactive 双视觉（描边、亮度差异），穿透模式克制、交互模式清晰

## 5. 设置面板

- [x] 5.1 `SettingsView` 窗口区新增：透明度滑块（0.5～1.0）、显示范围 Picker、条数上限 Stepper、跨 Space 开关、"模式切换快捷键"录制行
- [x] 5.2 快捷键冲突校验扩展：文本录入、语音录入、模式切换三者两两互斥，冲突提示与回退逻辑与现有实现一致

## 6. 验证与收尾

- [x] 6.1 `swift build` 通过
- [x] 6.2 `swift run TodoPinCoreChecks` 全绿
- [x] 6.3 `./script/build_and_run.sh --verify` 通过
- [x] 6.4 手动验证 Phase 1 验收三点：默认穿透可点穿到下方应用；`⌥⌘T` 切交互可勾选/拖动/调整大小，切回恢复穿透；重启后位置、尺寸、透明度、模式原样恢复
