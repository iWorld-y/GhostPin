## Purpose

定义 GhostPin 随仓库维护、面向已安装应用用户的 Agent Skill，使 Agent 通过固定的 App Bundle CLI 全路径稳定查询和管理本地任务。

## Requirements

### Requirement: 固定使用正式安装 CLI

GhostPin CLI Skill SHALL 直接调用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`；所有命令示例 MUST 使用该完整路径，且不得通过环境变量、PATH、符号链接或其他候选路径发现 CLI。

#### Scenario: 执行查询命令

- **WHEN** Agent 按 Skill 查询未完成任务
- **THEN** Agent 执行 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --json`

#### Scenario: CLI 不存在

- **WHEN** `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli` 不存在或不可执行
- **THEN** Agent 停止操作并提示用户将 GhostPin.app 安装到 `/Applications`，不尝试其他入口

### Requirement: Skill 内容面向安装用户

Skill SHALL 只描述安装用户可执行的任务管理流程；`SKILL.md` MUST NOT 包含大小写不敏感的 `mcp`、`.build`、`swift run`、`<repo-root>` 或源码开发运行说明。

#### Scenario: 静态检查 Skill 内容

- **WHEN** 发布前检查 `skills/ghostpin-cli/SKILL.md`
- **THEN** 文件不包含被禁止的术语或开发入口，且全部命令使用正式安装 CLI 的完整路径

### Requirement: 安全定位并修改任务

Skill SHALL 使用 `--json` 获取机器可读结果；修改已有任务前 MUST 通过 `list --all --json` 获取真实 UUID，标题匹配不唯一时 MUST 请求用户消歧，删除后 MUST 再次查询确认目标不存在。

#### Scenario: 同名任务需要消歧

- **WHEN** 用户按标题要求修改任务且查询结果中存在多个同名任务
- **THEN** Agent 列出候选任务并等待用户选择，不擅自修改

#### Scenario: 删除后确认

- **WHEN** Agent 成功执行删除命令
- **THEN** Agent 再次执行全量 JSON 查询并确认对应 UUID 不存在后才报告完成
