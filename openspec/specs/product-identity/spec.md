## Purpose

定义 GhostPin 对用户和发行系统公开的产品身份，并约束从 TodoPin 升级时的数据、偏好与系统注册兼容行为，确保品牌切换不会造成任务丢失或静默重置。

## Requirements

### Requirement: 公开产品名称

当前版本的应用名称、App Bundle、主程序、用户界面、通知、CLI 帮助、Skill 和用户向文档 SHALL 统一使用 `GhostPin` 品牌，不得继续把 `TodoPin` 作为当前产品名称展示。

#### Scenario: 启动新版本应用

- **WHEN** 用户安装并启动新版本
- **THEN** Applications 中的应用、运行中的主程序、HUD、菜单和通知均显示 `GhostPin`

#### Scenario: 阅读当前使用说明

- **WHEN** 用户查看 README、Agent Skill 或当前发行说明
- **THEN** 安装路径、命令和产品名称均使用 GhostPin 对应名称，不把 TodoPin 描述为当前产品

### Requirement: 系统身份保持连续

GhostPin 的 macOS Bundle ID MUST 继续使用 `com.oyuxi.TodoPin` 作为历史兼容标识；品牌更名 SHALL NOT 因更换 Bundle ID 而重置现有 `UserDefaults`、通知授权或登录启动配置。该历史标识不得作为用户可见产品名称展示。

#### Scenario: 已有用户升级

- **WHEN** 已使用 TodoPin 的用户安装并首次启动 GhostPin
- **THEN** 原有 HUD 位置、显示偏好和登录启动选择保持不变，系统不因产品改名要求重新建立一套应用偏好

#### Scenario: 检查应用身份

- **WHEN** 发行流程检查 `GhostPin.app` 的 Info.plist
- **THEN** `CFBundleName` 和可执行文件名为 `GhostPin`，`CFBundleIdentifier` 仍为 `com.oyuxi.TodoPin`

### Requirement: 本地任务数据迁移

GhostPin SHALL 将 `~/Library/Application Support/GhostPin/todos.json` 作为默认任务文件。首次访问时，若新文件不存在而 `~/Library/Application Support/TodoPin/todos.json` 存在，系统 MUST 将旧文件完整迁移到新位置并保留旧文件；迁移后 App 与 CLI MUST 只使用新文件。

#### Scenario: 从旧数据目录升级

- **WHEN** 新任务文件不存在且旧任务文件包含已有任务
- **THEN** 首次启动 GhostPin App 或执行 `ghostpin-cli` 后，新文件包含旧文件的全部任务与字段，旧文件保持可用于回退

#### Scenario: 新旧文件同时存在

- **WHEN** 新任务文件和旧任务文件均已存在
- **THEN** 系统以 GhostPin 目录中的新文件为准，不使用旧文件覆盖或合并新文件

#### Scenario: 全新安装

- **WHEN** 新旧任务文件均不存在
- **THEN** 首次写入在 `~/Library/Application Support/GhostPin/` 下创建任务文件，不创建 TodoPin 数据目录

#### Scenario: 旧数据迁移失败

- **WHEN** 旧任务文件存在但无法安全复制或解析
- **THEN** 系统不得修改旧文件或以空任务覆盖它，并向当前调用方报告可诊断的错误

### Requirement: 历史名称保留边界

归档 OpenSpec、既有 CHANGELOG 条目和兼容所需的 Bundle ID MAY 保留 TodoPin 名称；当前源码品牌标识、当前规格、README、AGENTS、Skill 和新增发布说明 MUST 使用 GhostPin 名称。领域模型中的 `Todo` 术语不属于品牌名称，MUST 保持原有业务含义。

#### Scenario: 检查当前与历史内容

- **WHEN** 维护者执行改名验收
- **THEN** 当前交付内容中仅兼容 Bundle ID 允许出现旧品牌，归档与旧发布记录未被改写，`TodoItem`、`TodoStore`、`TodoStatus` 等领域术语保持不变
