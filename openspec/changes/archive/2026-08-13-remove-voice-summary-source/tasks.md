# Tasks: 移除语音录入、每日汇总与来源标记

## 1. Core 层(数据模型与存储)

- [x] 1.1 删除 `Sources/TodoPinCore/Models/TodoSource.swift`;从 `TodoItem` 删除 `source` 属性、init 参数与 decode 行
- [x] 1.2 删除 `Sources/TodoPinCore/Models/DailySummary.swift` 与 `Sources/TodoPinCore/Stores/SummaryStore.swift`
- [x] 1.3 `ReminderPolicy` 删除 `shouldGenerateDailySummary`
- [x] 1.4 `ReminderSettings` 删除 `summaryHour`/`summaryMinute`
- [x] 1.5 `StorageLocations` 删除 `summariesURL`
- [x] 1.6 `TodoStore.add` 删除 `source` 参数

## 2. App 层与视图

- [x] 2.1 `AppPreferences` 删除 `voiceHotKeyShortcut`/`speechLanguage` 属性及加载/保存/冲突兜底逻辑;`hudModeFallback` 简化为仅与文本快捷键比较
- [x] 2.2 `HotKeyPreset` 删除 `defaultVoiceShortcut` 与 `f8`;`presets` 收敛为 `[optionSpace, optionN, optionCommandT]`
- [x] 2.3 `AppState` 删除 `speechModelManager`、`summaryStore` 相关属性与初始化、`startVoiceCapture`、`updateVoiceHotKey`、`showSummary`、`generateTodaySummary`、`addTodo` 的 `source` 参数、快捷键注册 id=2
- [x] 2.4 `WindowCoordinator` 删除 `showVoiceCapture`/`voiceCaptureWindow` 与 `showSummary`
- [x] 2.5 删除语音 5 个文件:`AudioCaptureService.swift`、`WhisperEngine.swift`、`VoiceInputController.swift`、`SpeechModelManager.swift`、`VoiceCaptureOverlayView.swift`
- [x] 2.6 `ReminderService` 移除 `summaryStore` 依赖与 evaluate() 中汇总段
- [x] 2.7 `NotificationService` 删除 `sendSummary`
- [x] 2.8 `MenuBarContentView` 删除两个麦克风按钮与 `item.source` 的「语音录入」标签及 source 参数传递
- [x] 2.9 `QuickAddPanelView`/`ReminderConfirmationView` 删除 `source` 参数与 `PendingReminderDraft.source`
- [x] 2.10 `SettingsView` 删除语音录入快捷键行、语音语言输入框、「本地语音模型」Section 及语音快捷键冲突校验

## 3. MCP 与 CLI

- [x] 3.1 `TodoItemPayload` 删除 `source` 编码
- [x] 3.2 MCP `Tools.swift` 删除 `source: .text`
- [x] 3.3 CLI `main.swift` 删除 `source: .text`

## 4. 依赖与脚本

- [x] 4.1 `Package.swift` 移除 `WhisperFramework` binaryTarget、TodoPin target 依赖与 `linkedFramework("AVFoundation")`
- [x] 4.2 删除 `script/fetch_models.sh`
- [x] 4.3 `build_and_run.sh`/`package_dmg.sh` 移除 whisper.framework 拷贝与 `TODO_PIN_INCLUDE_MODEL` 相关逻辑

## 5. 测试与验证

- [x] 5.1 `Tests/TodoPinCoreChecks/main.swift` 清理全部 `source:` 参数、`.voice` 用例与 `defaultVoiceShortcut` 用例
- [x] 5.2 `swift build --disable-sandbox` 通过,无残留引用
- [x] 5.3 `swift run TodoPinCoreChecks` 全 PASS
- [x] 5.4 `todopin-cli list --json` 输出确认 10 字段(无 source)
- [x] 5.5 `./script/build_and_run.sh --verify` 打包启动验证

## 6. 文档同步

- [x] 6.1 `README.md`/`README.en.md` 移除语音与汇总相关段落(功能、快捷键、语音模型、构建说明)
- [x] 6.2 `docs/需求-2026-08-13.md` 与 `AGENTS.md` 更新语音/汇总描述
- [x] 6.3 `docs/功能清单与减法建议-2026-08-13.md` 标注已实施项
