# Changelog

## Unreleased

### Changed

- CLI 补齐优先级、截止日期和描述的新增与修改，并为根命令及每条子命令提供 `-h` / `--help`。
- Agent 任务操作统一使用已安装应用内的 CLI Skill 和完整路径。
- 产品更名为 GhostPin：App、CLI、Skill、DMG 和当前使用说明统一采用 GhostPin 名称。
- CLI 更名为 `ghostpin-cli`，旧的 `todopin-cli` 不再随 App 分发；完整路径为 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`。
- 首次升级时将 `~/Library/Application Support/TodoPin/todos.json` 迁移到 `~/Library/Application Support/GhostPin/todos.json`，保留旧文件作为回退快照；新文件创建后不再双写。

### Migration

- 升级前退出旧 TodoPin.app 并将其从 `/Applications` 移除，再安装 GhostPin.app，避免两个版本同时运行。
- 若需要回退，先停止 App 并备份两个目录中的 `todos.json`，确认要回退的数据后再手动复制；GhostPin 的新任务不会自动写回旧目录。

## v0.0.1 - 2026-08-13

Agent native 版发布:任务的新增、修改、删除全部通过 MCP 完成,应用退化为纯展示壳(桌面幽灵 HUD + 托盘 + 本地通知)。

### Added

- Agent native 设计理念:所有写操作收敛到 MCP Server(`todopin-cli mcp`),App 仅负责展示与通知。
- 托盘原生菜单:未完成数量徽标、显示/隐藏桌面便签、交互模式开关、设置、退出。
- HUD「勾选完成」作为唯一 UI 写入口,其余操作走 MCP。
- 一键发布脚本 `script/release.sh` + `script/VERSION` 版本号管理(`TodoPin-<版本>.dmg`)。

### Changed

- 幽灵 HUD 退化为只读展示:标题、优先级、截止时间、描述、过期删除线。
- 穿透/交互模式切换从全局快捷键改为托盘「交互模式」开关。
- 托盘图标改用 SF Symbol 大头针(`mappin.circle.fill`),菜单栏模板化环境稳定显示。
- 设置页仅保留 HUD 展示参数与登录启动。

### Removed

- 语音录入全套:whisper.cpp 依赖、语音快捷键、语音语言与模型下载(含 `script/fetch_models.sh`)。
- 每日汇总:`DailySummary`/`SummaryStore`/21:30 汇总通知。
- 来源标记:`TodoSource` 与 `TodoItem.source` 字段(CLI/MCP JSON 输出 11→10 字段,旧数据零迁移)。
- 全部 UI 操作入口:文本快速录入面板、中文时间解析、菜单栏任务面板、HUD 编辑交互。
- 全局快捷键系统:`HotKeyService`/`HotKeyShortcut`/Carbon 注册。
- 每小时未完成提醒(`ReminderPolicy`/`ReminderSettings`)。

## v0.1.0 - 2026-06-14

Initial open source release of TodoPin.

### Added

- Local-first macOS menu bar todo app built with SwiftUI and Swift Package Manager.
- Quick text capture with editable todos and reminder time parsing.
- Optional local voice capture through whisper.cpp.
- Separate global shortcuts for text quick-add and voice capture.
- Desktop sticky notes with a quieter inactive visual state.
- Local JSON storage under Application Support.
- Local macOS notifications for reminders and unfinished todos.
- Settings for shortcuts, voice model installation, launch at login, and desktop note behavior.
- DMG packaging script with optional model bundling.

### Privacy

- No cloud sync, account system, analytics, or telemetry.
- Voice input works locally when the optional model is installed.
- The release DMG does not bundle the speech model by default.
