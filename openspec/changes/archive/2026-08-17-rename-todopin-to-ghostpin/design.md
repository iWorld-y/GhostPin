## Context

当前 Swift Package 的包名、App/CLI/Core target、源码目录和检查目标都使用 TodoPin 前缀；打包脚本在运行时生成 Info.plist，并以 `com.oyuxi.TodoPin` 作为 Bundle ID。App 与 CLI 通过 `StorageLocations.todosURL()` 共享 `~/Library/Application Support/TodoPin/todos.json`，App 偏好使用 `UserDefaults.standard`，登录启动使用 `SMAppService.mainApp`。

仓库同时存在尚未实施的 `remove-mcp-support` 变更。该变更将先完成 CLI 能力补齐和旧入口删除，再由本变更基于收敛后的 CLI、Skill 与正式规格执行改名；参见 proposal.md 与本变更 delta specs。

## Goals / Non-Goals

**Goals:**

- 让源码、构建产物、当前文档和用户操作入口使用一致的 GhostPin 品牌。
- 由 Core 提供 App 与 CLI 共用的数据目录选择和旧数据迁移，避免两套迁移逻辑。
- 维持 macOS 应用身份，使偏好、通知权限和登录启动选择在升级时连续。
- 让自动化检查能够区分必须清理的旧名称与允许保留的历史兼容标识。

**Non-Goals:**

- 不重新设计 Logo；现有无文字图形继续使用，仅调整资源名称。
- 不修改 Todo 领域模型名称或 `todos.json` 数据结构。
- 不提供 `todopin-cli` 兼容包装、符号链接或 PATH 安装。
- 不自动删除旧 `TodoPin.app`、重命名本地仓库目录或操作 GitHub 仓库设置。
- 不改写归档 OpenSpec、旧 CHANGELOG 条目或 Git 历史。

## Decisions

### 1. 以前置变更的最终状态作为改名基线

先完成并归档 `remove-mcp-support`，但不发布中间版本；随后实施、校验并归档本变更。这样本变更的 `todo-cli` 和 `hud-live-refresh` delta 可以基于已经收敛的 CLI 契约，不需要在改名变更中再次处理即将删除的模块。

备选方案是把改名并入已有变更，但会把入口移除、CLI 功能补齐、数据迁移和全产品更名混在同一审阅单元中，因此不采用。另一个备选方案是并行实施后一次归档，但两个变更会同时修改相同规格，归档顺序难以验证，也不采用。

### 2. 只重命名品牌标识，保留 Todo 领域术语

Swift Package、App product/target、Core module、CLI target、检查目标和对应目录统一改为 `GhostPin`、`GhostPinCore`、`GhostPinCLI`、`GhostPinCoreChecks`；公开可执行文件改为 `GhostPin` 与 `ghostpin-cli`。`TodoPinApp`、Logo 类型、编码器扩展、日历辅助方法、测试临时目录等品牌前缀同步改为 GhostPin。

`TodoItem`、`TodoStore`、`TodoStatus`、`todos.json` 等描述业务领域而非品牌的名称保持不变。备选方案是只改用户文案，但会让 Package、源码路径和维护文档长期保留两个产品名；全量替换所有 `Todo` 又会误改领域语义，因此采用品牌前缀边界。

### 3. 保留 Bundle ID，显式协调登录启动状态

打包脚本继续写入 `com.oyuxi.TodoPin`，但 `CFBundleName`、`CFBundleExecutable`、App Bundle 文件名和进程名使用 GhostPin。保留 Bundle ID 可让 `UserDefaults.standard` 与通知授权沿用原应用身份，不额外复制偏好键。

GhostPin 启动时根据保存的登录启动偏好与 `SMAppService.mainApp` 当前状态做一次协调；原偏好为开启时确保新的 App Bundle 注册生效，关闭时不得自行开启。具体调用只放在登录启动服务中，AppState 继续只负责流程编排。

改用 `com.oyuxi.GhostPin` 虽然命名更整洁，但会让 macOS 视为新的应用身份，需要迁移偏好、重新请求通知权限并处理旧登录项，收益不足，因此不采用。

### 4. 在 Core 中执行只迁移一次、旧文件只读保留的数据切换

`StorageLocations` 将 GhostPin 目录作为默认目录，并保留仅供迁移使用的旧 TodoPin 路径。解析默认任务 URL 时遵循以下顺序：

1. GhostPin 任务文件已存在时直接使用，不再读取旧文件。
2. 新文件不存在、旧文件存在时，先验证旧 JSON 可读取，再写入新目录中的临时文件，并以不覆盖既有目标的方式发布为 `todos.json`。
3. 若并发调用发现另一进程已经生成新文件，则将新文件视为权威结果，不再覆盖。
4. 新旧文件均不存在时只返回 GhostPin 路径，由首次写入正常创建文件。

迁移保留旧文件且之后不做双写。这样回退旧版本时仍能看到升级前快照，但 GhostPin 中的新修改不会自动同步回旧目录；发布说明需要明确，真正回退前应备份并按需复制新文件。双写虽能改善回退体验，却会制造两个权威数据源和并发一致性问题，因此不采用。

App 和 CLI 均通过同一 Core API 获取路径，App 的文件监听在路径解析完成后直接监听 GhostPin 目录。临时目录 fallback 同样改用 GhostPin 名称，但不得在迁移失败时静默转到空临时存储。

### 5. App、CLI、Skill 和发行物在同一提交链完成切换

Package 产品名、CLI 帮助、Skill 目录/frontmatter、App 内文案、通知标识、打包脚本和 GitHub Workflow 一起改名。Skill 只调用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`，不探测旧命令或旧 App 路径。

CLI 改名时保留前置变更建立的逐命令帮助分派：根命令与每条用户命令继续支持 `-h`、`--help`，专属帮助中的可执行名称统一改为 `ghostpin-cli`，其中 update 帮助必须继续列出修改和清除截止日期的选项。品牌替换不得退化为只保留根帮助。

发行环境变量改为 `GHOST_PIN_VERSION` 与 `GHOST_PIN_SIGN_IDENTITY`；兼容 Bundle ID 变量值仍保留旧 ID。DMG 验收同时检查 App、主程序、CLI、Info.plist 和 Release 资产名称，避免只改到其中一层。

### 6. 用白名单检查旧品牌残留

实现完成后，对当前源码、脚本、README、AGENTS、Skill、主规格和新发布说明执行旧品牌扫描。允许项仅包括：兼容 Bundle ID、旧数据迁移路径、归档 OpenSpec 和既有 CHANGELOG 历史。迁移常量应集中在存储模块，Bundle ID 应集中在打包脚本，减少不可解释的散落例外。

文件名检查与正文检查分开执行，因为 Swift 目录、Logo 资源和 Skill 目录也需要更名。`.codegraph` 属于生成索引，不在实现中手工编辑，文件移动完成后由维护者按项目流程决定是否刷新。

## Risks / Trade-offs

- [旧 `TodoPin.app` 与 `GhostPin.app` 可同时存在，可能分别写入不同目录] → 发行说明要求升级前退出并移除旧 App；不自动删除用户 Applications 中的文件。
- [数据迁移与 CLI/App 并发启动发生竞争] → 使用临时文件和不覆盖已存在目标的发布方式，竞争失败方重新读取 GhostPin 文件。
- [迁移成功后回退旧版本看不到 GhostPin 新增任务] → 保留旧数据作为升级前快照，并在发布说明给出回退前备份/复制说明，不引入长期双写。
- [登录启动项仍指向旧 App 路径] → GhostPin 首次启动按保存偏好协调 `SMAppService.mainApp` 状态，并增加定向验收。
- [两个 OpenSpec 变更修改相同规格] → 强制先完成并归档 `remove-mcp-support`，再实施和归档本变更，期间不发布。
- [大范围文件移动造成遗漏或索引陈旧] → 分层提交式执行、构建和旧名白名单扫描；不把 `.codegraph` 索引更新混入产品改名。

## Migration Plan

1. 完成、验证并归档 `remove-mcp-support`，确认主规格已反映最终 CLI 契约；不发布该中间状态。
2. 先在 Core 增加隔离目录下的数据迁移检查，再切换默认路径，验证新装、旧数据、双文件、损坏文件和并发竞争。
3. 重命名 Swift Package、targets、源码目录与品牌前缀，保持 Todo 领域模型和 JSON 格式不变。
4. 同步 App 文案、CLI、Skill、打包脚本、Workflow、README、AGENTS、主规格 delta 和 CHANGELOG 新条目。
5. 运行核心检查、Swift 构建、App 启动验证、CLI 截止日期与逐命令帮助冒烟、DMG/Info.plist 验收和旧品牌白名单扫描。
6. 发布 GhostPin 版本，说明 CLI 路径、旧 App 清理、数据迁移和回退限制；发布验证后再由维护者重命名 GitHub 仓库与本地目录。

若改名前验证失败，回退代码即可，旧数据尚未改变。若 GhostPin 已完成迁移后需要回退，先停止两个版本，备份两份 `todos.json`，再由用户选择是否把 GhostPin 文件复制回 TodoPin 目录；不得由旧版本自动覆盖新数据。
