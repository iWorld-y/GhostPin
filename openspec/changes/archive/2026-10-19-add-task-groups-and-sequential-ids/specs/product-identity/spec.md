# Spec Delta

## MODIFIED Requirements

### Requirement: 本地任务数据迁移

GhostPin SHALL 将 `~/Library/Application Support/GhostPin/todos.json` 作为默认任务文件。首次成功访问时，若新文件不存在而 `~/Library/Application Support/TodoPin/todos.json` 存在，系统 MUST 将全部旧任务迁入新位置并保留源文件原始内容。目标文件 MUST 同时遵守 `task-storage` 的版本升级规则，生成整数 ID 和 `默认` 组别，保留其他业务字段与既有缺省语义；迁移后 App 与 CLI MUST 只使用新文件。

#### Scenario: 从旧数据目录升级

- **WHEN** 新任务文件不存在且旧任务文件包含已有任务
- **THEN** 首次成功启动 GhostPin App 或查询任务后，新文件包含全部旧任务，组别为 `默认`、ID 按稳定规则转换，其他业务字段保持不变，旧文件保持原样可用于回退

#### Scenario: 新旧文件同时存在

- **WHEN** 新任务文件和旧任务文件均已存在
- **THEN** 系统以 GhostPin 目录中的新文件为准，只按需升级新文件的格式，不使用旧文件覆盖或合并新文件

#### Scenario: 全新安装

- **WHEN** 新旧任务文件均不存在
- **THEN** 首次成功写入在 `~/Library/Application Support/GhostPin/` 下创建版本化任务文件，第一条任务 ID 为 `10000`，不创建 TodoPin 数据目录

#### Scenario: 旧数据迁移失败

- **WHEN** 旧任务文件存在但无法安全读取、备份、解析或提交新格式
- **THEN** 系统不得修改旧文件或以空任务覆盖它，不发布迁移成功，并向当前调用方报告可诊断的错误

#### Scenario: 新旧目录均有数据而命令失败

- **WHEN** 用户的 CLI 命令缺少必填组别或请求不存在的任务 ID
- **THEN** 失败命令不触发目录间任务迁移或存储格式升级
