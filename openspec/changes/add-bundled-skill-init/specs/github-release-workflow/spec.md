# Spec Delta

## MODIFIED Requirements

### Requirement: macOS 构建与 DMG 校验

发布 Workflow SHALL 在 macOS 构建环境中运行核心行为检查、构建 GhostPin 与 `ghostpin-cli`，生成同时包含 App、CLI 和完整 GhostPin skill 的 DMG，并验证 App 签名、Bundle 身份、CLI 路径、skill 内容与 DMG 完整性。构建目录及只读挂载 DMG 中的 skill MUST 与当前提交的 `skills/ghostpin-cli/` 在全部相对路径、文件类型和文件内容上一致。

#### Scenario: 构建成功

- **WHEN** 版本号校验通过且核心检查、构建、签名、skill 和 DMG 校验均成功
- **THEN** Workflow 产出名称为 `GhostPin-<version>.dmg` 的 DMG，其中包含 `GhostPin.app/Contents/MacOS/GhostPin`、`GhostPin.app/Contents/MacOS/ghostpin-cli` 和 `GhostPin.app/Contents/Resources/skills/ghostpin-cli/`

#### Scenario: Bundle 身份兼容

- **WHEN** Workflow 校验打包后的 `GhostPin.app`
- **THEN** App 名称和主程序为 `GhostPin`，Bundle ID 为历史兼容值 `com.oyuxi.TodoPin`

#### Scenario: 构建或校验失败

- **WHEN** 核心检查、构建、签名、命名、CLI 路径、skill 内容或 DMG 校验任一步骤失败
- **THEN** Workflow 失败且不创建成功状态的 GitHub Release

#### Scenario: 校验构建目录中的完整 Skill

- **WHEN** Workflow 检查构建出的 App Bundle
- **THEN** skill 目录包含 `SKILL.md`、`agents/openai.yaml` 和空普通文件 `ghostpin-cli`，并与当前提交的源 skill 目录完整一致

#### Scenario: 校验 DMG 中的完整 Skill

- **WHEN** Workflow 只读挂载生成的 DMG
- **THEN** 挂载 App 的 skill 目录与当前提交的源目录完整一致，不缺失归属标记、辅助文件或子目录，也没有额外旧文件

#### Scenario: 校验发行 CLI 的初始化帮助

- **WHEN** Workflow 执行随包 CLI 的 `init --help`
- **THEN** 命令成功展示初始化用法，不依赖本机已安装 App，不创建或修改运行用户的 skill 目录
