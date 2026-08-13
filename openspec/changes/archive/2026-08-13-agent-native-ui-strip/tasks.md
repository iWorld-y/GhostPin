# Tasks: Agent Native UI 精简

## 1. Core 层清理

- [x] 1.1 删除 `Sources/TodoPinCore/Services/TodoTimeParser.swift`、`Sources/TodoPinCore/Services/ReminderPolicy.swift`、`Sources/TodoPinCore/Models/ReminderSettings.swift`
- [x] 1.2 删除 `Sources/TodoPinCore/Models/HotKeyPreset.swift`(HotKeyShortcut)

## 2. App 层与视图

- [x] 2.1 `TodoPinApp.swift` 托盘改为原生菜单(`menuBarExtraStyle(.menu)`):数量徽标 + 显示/隐藏便签 + 交互模式开关 + 设置 + 退出
- [x] 2.2 删除 `Views/MenuBarContentView.swift` 的任务面板逻辑(输入框/列表/操作),重写为轻量托盘菜单视图
- [x] 2.3 删除 `Views/QuickAddPanelView.swift`、`Views/ReminderConfirmationView.swift`
- [x] 2.4 `WindowCoordinator` 删除 `showQuickAdd`/`quickAddWindow`/`configureFloatingPanel` 中快速新增相关;`showBoard` 保留
- [x] 2.5 `DesktopNotesBoardView` 删除卡片编辑/删除按钮与 `DesktopNoteEditorView`,仅保留勾选完成
- [x] 2.6 `AppState` 删除 `registerHotKeys`、`updateTextHotKey`、`updateHUDModeHotKey`、`showQuickAdd`;`toggleHUDMode` 保留供托盘开关调用
- [x] 2.7 `AppPreferences` 删除 `textHotKeyShortcut`/`hudModeHotKeyShortcut`/`reminderSettings` 属性及加载/保存逻辑
- [x] 2.8 `SettingsView` 仅保留 HUD 参数(透明度/显示范围/最多条数/跨 Space/置顶)与登录启动
- [x] 2.9 `NotificationService` 删除 `sendHourlyReminder`;`ReminderService` 仅保留定时提醒逻辑

## 3. 依赖

- [x] 3.1 `Package.swift` 移除 `linkedFramework("Carbon")`;`AppPreferences`/`SettingsView` 等处移除 `import Carbon`

## 4. 测试

- [x] 4.1 `Tests/TodoPinCoreChecks/main.swift` 删除 HotKeyShortcut 相关用例与 ReminderPolicy 用例;补充定时提醒行为用例(若缺失)

## 5. 验证

- [x] 5.1 `swift build --disable-sandbox` 通过,无残留引用
- [x] 5.2 `swift run --disable-sandbox TodoPinCoreChecks` 全 PASS
- [x] 5.3 手动打包启动验证(应用可启动,托盘菜单可用,无 dyld 问题)
- [x] 5.4 `todopin-cli list --json` 输出不变(10 字段)

## 6. 文档

- [x] 6.1 `README.md`/`README.en.md` 新增「Agent Native 设计理念」章节;删除快捷键相关段落;更新功能列表与设置说明
- [x] 6.2 `AGENTS.md` 更新:删除快捷键/提醒相关描述,补充 Agent native 架构说明
- [x] 6.3 `docs/功能清单与减法建议-2026-08-13.md` 追加本轮减法标注
