# Spec Delta

## ADDED Requirements

### Requirement: Skill 随版本完整分发

GhostPin SHALL 将当前版本的完整 `skills/ghostpin-cli/` 目录分发到 App 的 `Contents/Resources/skills/ghostpin-cli/`。开发 App 与发布 DMG MUST 使用相同目录结构，并保留 skill 中全部文件的相对路径与内容。

#### Scenario: 发布包含完整 Skill

- **WHEN** 用户查看某个版本的 GhostPin App Bundle
- **THEN** `Contents/Resources/skills/ghostpin-cli/` 包含该版本的 `SKILL.md`、`agents/openai.yaml`、归属标记及源 skill 目录中的其他文件

#### Scenario: 新增辅助文件随版本分发

- **WHEN** 当前版本的 `skills/ghostpin-cli/` 新增辅助文件
- **THEN** 开发 App 与发布 DMG 中的 skill 均包含该文件及其原有相对路径，不依赖固定文件名单复制

### Requirement: Skill 归属标记

GhostPin skill 根目录 MUST 包含一个名为 `ghostpin-cli` 的空普通文件，作为允许整目录覆盖的归属标记。目录、符号链接和其他类型的同名文件 MUST NOT 被视为有效标记。

#### Scenario: 分发归属标记

- **WHEN** 打包或安装 GhostPin skill
- **THEN** 完整 skill 根目录包含名为 `ghostpin-cli` 的空普通文件

#### Scenario: 同名路径不能替代归属标记

- **WHEN** 待覆盖目录中名为 `ghostpin-cli` 的路径是目录或符号链接
- **THEN** 初始化命令拒绝覆盖该目录，不将同名路径当作有效归属标记

## MODIFIED Requirements

### Requirement: Skill 内容面向安装用户

Skill SHALL 只描述安装用户可执行的初始化和任务管理流程，并说明通过 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli init` 安装或覆盖更新 skill。`SKILL.md` MUST NOT 包含大小写不敏感的 `mcp`、`.build`、`swift run`、`<repo-root>` 或源码开发运行说明。

#### Scenario: 静态检查 Skill 内容

- **WHEN** 发布前检查 `skills/ghostpin-cli/SKILL.md`
- **THEN** 文件不包含被禁止的术语或开发入口，且全部命令使用正式安装 CLI 的完整路径

#### Scenario: 阅读初始化与升级说明

- **WHEN** 安装用户阅读 skill 的初始化说明
- **THEN** 说明包含正式安装 CLI 的 `init` 命令、默认安装路径、整目录覆盖及符号链接处理规则，并说明已有目录缺少归属标记时会拒绝覆盖
