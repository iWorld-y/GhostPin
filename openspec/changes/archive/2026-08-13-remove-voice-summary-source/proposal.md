# Proposal: 移除语音录入、每日汇总与来源标记

## Why

TodoPin 目前承载了过多低使用率功能,维护成本集中在语音链路(远程 binaryTarget 依赖、模型下载流程、6 个专用文件)。为做减法,移除语音录入、每日汇总与任务来源标记三块功能,让应用回归「文本快捕 + 提醒 + 幽灵 HUD + Agent 通道」的核心,同时消除唯一的联网构建依赖。

## What Changes

- **BREAKING**: 删除语音录入全套 — `AudioCaptureService`、`WhisperEngine`、`VoiceInputController`、`SpeechModelManager`、`VoiceCaptureOverlayView` 五个文件、语音快捷键(F8)、语音语言设置、模型下载 UI 与 `fetch_models.sh`,移除 `WhisperFramework` binaryTarget 依赖与 `AVFoundation` 链接。
- **BREAKING**: 删除每日汇总 — `DailySummary`、`SummaryStore`、21:30 汇总通知、`ReminderSettings.summaryHour/summaryMinute`、`StorageLocations.summariesURL`。
- **BREAKING**: 删除任务来源标记 — `TodoSource` 枚举与 `TodoItem.source` 字段;`todopin-cli list --json` 与 MCP `list_tasks` 的输出移除 `source` 字段(11 → 10 字段)。
- 删除 `HotKeyShortcut.defaultVoiceShortcut` 与 `f8` 预设;快捷键冲突校验仅剩文本录入与 HUD 模式切换。
- `summaries.json` 停止读写;旧 `todos.json` 中多余的 `source` key 由 JSONDecoder 自动忽略,无需数据迁移。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `ghost-hud`: 模式切换快捷键的冲突校验不再涉及语音录入快捷键。
- `todo-cli`: `list --json` 输出字段移除 `source`。
- `todo-mcp-server`: `list_tasks` 返回字段移除 `source`(11 → 10 个)。

## Impact

- **源码**: 删除 8 个 Swift 文件(TodoPin 5 个语音文件 + `TodoSource` + `DailySummary` + `SummaryStore`);修改约 10 个文件(`AppState`、`AppPreferences`、`WindowCoordinator`、`MenuBarContentView`、`QuickAddPanelView`、`ReminderConfirmationView`、`SettingsView`、`TodoItem`、`TodoItemPayload`、`TodoStore`、`ReminderService`、`NotificationService`、`ReminderPolicy`、`ReminderSettings`、`StorageLocations`、`Package.swift`、MCP `Tools`、CLI `main`、测试)。
- **脚本**: 删除 `script/fetch_models.sh`;`build_and_run.sh`、`package_dmg.sh` 移除 whisper.framework 拷贝与 `TODO_PIN_INCLUDE_MODEL` 逻辑。
- **依赖**: 移除远程 `WhisperFramework` binaryTarget,构建不再需要网络。
- **数据**: 旧数据零迁移;`summaries.json` 与 UserDefaults 旧 key 残留无害。
- **文档**: 同步更新 `README.md`、`README.en.md`、`docs/需求-2026-08-13.md`、`AGENTS.md` 中语音与汇总相关描述。
