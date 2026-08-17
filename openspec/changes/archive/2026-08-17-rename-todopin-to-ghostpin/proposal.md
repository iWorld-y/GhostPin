## Why

TodoPin 的产品名称已无法准确表达“常驻桌面的幽灵任务钉”这一产品形态，需要统一更名为 GhostPin。改名必须覆盖 App、CLI、发行物、Skill 和当前文档，同时迁移既有本地数据并保持系统身份连续，避免升级后出现任务或偏好丢失。

## What Changes

- **BREAKING** 将应用、Swift Package 主产物、App Bundle 和用户可见品牌从 `TodoPin` 更名为 `GhostPin`。
- **BREAKING** 将命令行工具从 `todopin-cli` 更名为 `ghostpin-cli`，不保留旧命令别名；Skill 同步更名并固定调用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`。
- 保留 CLI 的截止日期修改、清除能力与逐命令帮助契约，并将所有用法和帮助示例同步为 `ghostpin-cli`。
- 将 DMG、GitHub Release 标题、构建验证和发布环境变量统一为 GhostPin 命名。
- 将默认数据目录改为 `~/Library/Application Support/GhostPin/`；首次使用新目录且发现旧数据时执行一次兼容迁移，保留旧数据用于回退。
- 保留现有 Bundle ID `com.oyuxi.TodoPin` 作为升级兼容标识，使系统偏好、通知授权和登录启动身份保持连续；该历史标识不得出现在用户向文案中。
- 统一当前源码中的品牌前缀、资源文件名、测试目标、README、AGENTS、Skill 和正式规格；保留 `TodoItem`、`TodoStore`、`TodoStatus` 等领域术语。
- 保留归档 OpenSpec 与既有 CHANGELOG 历史中的 TodoPin 名称，只追加本次破坏性更名说明。
- 本变更以 `remove-mcp-support` 完成为实施前置，两项可连续实施，但不得发布只完成其中一项的中间版本。

## Capabilities

### New Capabilities

- `product-identity`: 定义 GhostPin 的产品名称、安装产物、系统身份兼容、本地数据迁移和历史名称边界。

### Modified Capabilities

- `todo-cli`: 将公开命令、逐命令帮助与随 App 分发路径改为 `ghostpin-cli`，并切换到迁移后的 GhostPin 数据目录。
- `hud-live-refresh`: 将外部写入场景切换到 `ghostpin-cli`，并要求 App 监听迁移后的共享存储。
- `github-release-workflow`: 将构建、DMG、验证和 GitHub Release 资产统一为 GhostPin 命名。

## Impact

- Swift Package 与源码：`Package.swift`、`Sources/TodoPin/`、`Sources/TodoPinCore/`、`Sources/TodoPinCLI/`、`Tests/TodoPinCoreChecks/` 及相关 import、类型和路径。
- App 行为：菜单、HUD、通知文案、临时目录、资源名称、登录启动与 `UserDefaults` 身份。
- 数据：`~/Library/Application Support/TodoPin/todos.json` 到 `~/Library/Application Support/GhostPin/todos.json` 的一次性兼容迁移；JSON 格式不变。
- 发行：`script/`、`.github/workflows/release.yml`、`GhostPin.app`、`GhostPin-<version>.dmg` 和 `ghostpin-cli`。
- Agent 入口：`skills/ghostpin-cli/` 及其固定 App Bundle 完整路径。
- 文档与规格：README、AGENTS、CHANGELOG、当前主规格和本变更 delta specs；不改写 `openspec/changes/archive/`。
- 仓库外操作：GitHub 仓库名与本地工作目录可在实现验收后单独重命名，不由仓库内代码自动完成。
