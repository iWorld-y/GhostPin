# Design: 移除语音录入、每日汇总与来源标记

## Context

见 proposal.md - Why。当前代码中语音与汇总逻辑与核心待办链路交错在 `AppState` / `AppPreferences` / `ReminderService` / `SettingsView` 等文件,删除时需同步清理全部触点;`TodoItem.source` 是必填 decode 字段,删除需保证旧 `todos.json` 可继续解析。

## Goals / Non-Goals

**Goals**
- 删除后 `swift build` 与 `swift run TodoPinCoreChecks` 全绿,不残留对已删符号的引用。
- 旧数据零迁移:既有 `todos.json` 无需转换即可加载。
- CLI/MCP 输出契约同步收敛(字段减少 `source`)。

**Non-Goals**
- 不动「每小时未完成提醒」「免打扰时段」「HUD 配置项」——它们是下一批减法候选,本变更保持现状。
- 不清理用户磁盘上残留的 `summaries.json` 与 UserDefaults 旧 key(无害,见 Risks)。

## Decisions

### D1: `TodoItem.source` 直接删字段,零迁移
从 `TodoItem` 删除 `source` 属性、init 参数与 decode 行;`JSONDecoder` 默认忽略未知 key,旧数据中的 `"source"` 会被自动丢弃,无需迁移脚本。
- 备选:保留字段但恒为 `.text` —— 拒绝,等于留死字段,与减法目标矛盾。
- 备选:自定义 decode 兼容 —— 不需要,默认行为已覆盖。

### D2: 语音快捷键偏好与加载逻辑整体删除
`AppPreferences` 删除 `voiceHotKeyShortcut`/`speechLanguage` 两个属性及其加载/保存分支;init 中「语音与文本冲突时用 optionN 兜底」的分支删除;`hudModeFallback` 校验简化为只与 `textHotKeyShortcut` 比较。`HotKeyShortcut` 删除 `defaultVoiceShortcut` 与 `f8`,`presets` 收敛为 `[optionSpace, optionN, optionCommandT]`(optionN 保留,仍是文本快捷键冲突兜底)。

### D3: 汇总链路从 App 与 Core 同时摘除
`DailySummary`/`SummaryStore`/`summariesURL` 删除;`ReminderService` 移除 summaryStore 依赖与 evaluate() 中汇总段;`ReminderPolicy` 删除 `shouldGenerateDailySummary`;`ReminderSettings` 删除 `summaryHour`/`summaryMinute`。`AppState.showSummary()`、`WindowCoordinator.showSummary()`、`generateTodaySummary()` 已确认无调用方,一并删除。

### D4: 脚本与依赖同步
`Package.swift` 移除 `WhisperFramework` binaryTarget 与 TodoPin target 的依赖、`linkedFramework("AVFoundation")`(全仓仅语音文件使用);`script/fetch_models.sh` 删除;`build_and_run.sh`/`package_dmg.sh` 移除 whisper.framework 拷贝与 `TODO_PIN_INCLUDE_MODEL` 相关分支。打包产物不再需要 `@rpath/whisper.framework`。

## Risks / Trade-offs

- **CLI/MCP 输出字段变化** → `list --json` 与 `list_tasks` 不再返回 `source`;当前 Agent 流程未消费该字段,但外部脚本若依赖需同步调整。specs 已更新为 10 字段契约。
- **旧偏好残留** → UserDefaults 中的 `voiceHotKeyShortcut`/`speechLanguage` 不再被读取,残留无害;不主动清理,避免误伤。
- **`summaries.json` 残留** → 不再读写,文件保留在磁盘;应用启动不再生成缺失汇总,无副作用。
- **遗漏引用导致编译失败** → 删除面跨 5 个 target(约 20 处调用点),以编译错误为哨兵逐文件清理,并以 `TodoPinCoreChecks` 回归兜底。

## Migration Plan

1. 在 `simplify-features` 分支实施,先改 Core(模型/存储/策略)→ 再改 App 层与视图 → 再改 MCP/CLI → 最后脚本与文档。
2. 每阶段 `swift build --disable-sandbox` 验证(本机 SPM manifest 沙箱问题,见 AGENTS.md 备注)。
3. 全量回归 `swift run TodoPinCoreChecks`;用 `todopin-cli list --json` 确认输出为 10 字段。
4. 打包验证 `./script/build_and_run.sh --verify`。

## Open Questions

无。
