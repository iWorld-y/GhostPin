# Spec Delta

## ADDED Requirements

### Requirement: 初始化 Skill

`ghostpin-cli init` SHALL 从当前 CLI 所在 App 的随包资源读取完整 skill，安装到当前用户的 `~/.agents/skills/ghostpin-cli/`。目标不存在时 MUST 创建所需目录；允许覆盖的目标 MUST 整目录替换。命令只接受 `--json`、`-h` 和 `--help`，普通文本成功输出 MUST 包含实际安装目录的绝对路径。

#### Scenario: 首次安装

- **WHEN** 安装路径及其父目录尚不存在，用户执行 `ghostpin-cli init`
- **THEN** 命令创建所需目录，安装完整随包 skill 并以退出码 0 结束，输出实际安装目录的绝对路径

#### Scenario: 重复执行并清除旧文件

- **WHEN** 已有目标具备有效归属标记，且包含旧版文件、本地修改或额外新增文件
- **THEN** 执行 `init` 后目标目录的完整内容与随包 skill 一致，旧版多余文件和本地新增文件被移除，再次执行仍成功

#### Scenario: 初始化独立于任务存储

- **WHEN** App 未运行且任务文件不存在或不可读，用户执行 `ghostpin-cli init`
- **THEN** 初始化仍可完成，不创建、读取、迁移或修改任务文件

#### Scenario: 拒绝额外参数

- **WHEN** 用户执行 `ghostpin-cli init extra` 或传入不支持的选项
- **THEN** 命令以退出码 2 结束，输出参数错误，skill 安装路径和任务文件保持不变

### Requirement: 解析 Skill 安装路径

初始化命令 MUST 在覆盖前解析安装路径中的符号链接，并替换最终真实目录。原安装路径的符号链接和链上中间链接 MUST 保持原样；断开、循环或最终指向非目录的链接 MUST 导致命令以非零退出码结束。

#### Scenario: 更新绝对路径链接的真实目录

- **WHEN** `~/.agents/skills/ghostpin-cli` 是指向具备归属标记目录的绝对路径符号链接
- **THEN** 命令整目录替换链接指向的真实目录，原链接仍为符号链接且链接内容不变

#### Scenario: 解析相对路径和多级链接

- **WHEN** 安装路径使用相对路径符号链接，或经过多个链接及带链接的父目录才能到达具备归属标记的真实目录
- **THEN** 命令更新最终真实目录，保留路径上的全部原链接，成功结果中的安装路径指向最终真实目录

#### Scenario: 拒绝无效链接

- **WHEN** 安装路径是断开的链接、形成链接循环，或最终指向普通文件
- **THEN** 命令报错且退出码非零，不删除链接、不创建替代目录，也不修改任何现有目标

#### Scenario: 拒绝同名普通文件

- **WHEN** `~/.agents/skills/ghostpin-cli` 已存在且是普通文件
- **THEN** 命令报错且退出码非零，原文件保持不变

### Requirement: 校验 Skill 覆盖归属

初始化命令 MUST 在覆盖前检查最终真实目录中名为 `ghostpin-cli` 的普通文件。缺少标记或标记是其他文件类型时 MUST 拒绝覆盖，不得自动补标记后继续。随包来源缺少归属标记、`SKILL.md` 或 `agents/openai.yaml` 时 MUST 在修改安装目标前失败。

#### Scenario: 拒绝未标记的同名目录

- **WHEN** 安装路径是已有目录，但目录内没有名为 `ghostpin-cli` 的普通文件
- **THEN** 命令明确提示缺少归属标记并以非零退出码结束，目录中的全部文件保持不变

#### Scenario: 检查链接指向目录的标记

- **WHEN** 安装路径是符号链接，而最终真实目录没有有效归属标记
- **THEN** 命令拒绝覆盖，符号链接与真实目录均保持不变

#### Scenario: 拒绝伪装成标记的同名路径

- **WHEN** 真实目录内名为 `ghostpin-cli` 的路径是目录、符号链接或其他非普通文件
- **THEN** 命令将目录视为未标记并拒绝覆盖

#### Scenario: 随包来源不完整

- **WHEN** 随包 skill 缺少必需文件，或来源目录不存在
- **THEN** 命令报告随包资源错误并以非零退出码结束，已有安装目录保持不变

### Requirement: Skill 替换失败保护

初始化命令 SHALL 在完整新副本准备成功后才替换旧目录。复制失败时 MUST 保留旧目录，替换失败时 MUST 恢复旧目录。恢复本身失败时 MUST 保留可恢复的旧目录副本并报告其绝对路径，且不得报告安装成功。其他 skill 目录 MUST 保持不变。

#### Scenario: 复制失败保留旧版

- **WHEN** 新副本复制过程中发生文件系统错误
- **THEN** 命令以非零退出码结束，旧 skill 及安装路径中的符号链接保持不变

#### Scenario: 替换失败恢复旧版

- **WHEN** 旧目录已临时保留，但新副本无法提交到真实安装路径
- **THEN** 命令恢复旧目录并以非零退出码结束，原符号链接仍可访问旧 skill

#### Scenario: 恢复失败保留恢复入口

- **WHEN** 替换失败且文件系统错误同时阻止旧目录恢复
- **THEN** 命令保留旧目录副本，报告失败及副本的绝对路径，不返回成功结果

#### Scenario: 保留其他 Skill

- **WHEN** `~/.agents/skills/` 下还存在其他 skill 目录
- **THEN** 初始化及覆盖更新均只处理 GhostPin skill 的安装目标，其他 skill 的文件和链接保持不变

## MODIFIED Requirements

### Requirement: JSON 输出契约

带 `--json` 时，list SHALL 输出 JSON 数组；add/doing/done/undone/update/delete SHALL 输出 `{"ok": true, ...}` 结构；init SHALL 输出 `{"ok": true, "path": "<实际安装目录的绝对路径>"}`。所有日期 MUST 使用 ISO8601 编码。任务对象 MUST 输出整数 `id`、非空字符串 `group` 和 `status`，并保留 `completedAt` 与 `isCompleted` 等既有业务字段；不得将存储文档的版本与下一编号包装到 list 结果中。

#### Scenario: JSON 列表输出

- **WHEN** 用户执行 `ghostpin-cli list --json`
- **THEN** 标准输出为 JSON 数组，每项包含 id、group、title、createdAt、status、completedAt、reminderAt、reminderSentAt、priority、dueAt、description、isCompleted 字段，id 为整数，日期为 ISO8601 字符串

#### Scenario: JSON 成功设置 Doing

- **WHEN** 用户执行 `ghostpin-cli doing 10000 --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`，结果任务的 `id` 为整数 `10000`、状态为 `"doing"`，退出码为 0

#### Scenario: JSON 成功结果

- **WHEN** 用户执行 `ghostpin-cli add "任务" --group 默认 --json` 且操作成功
- **THEN** 标准输出包含 `"ok": true`，`item` 中包含整数 ID 和 `"group": "默认"`，退出码为 0

#### Scenario: JSON 失败结果

- **WHEN** 用户执行带 `--json` 的命令且操作失败，例如 id 不存在
- **THEN** 标准输出包含 `"ok": false` 与 `"error"` 说明，退出码非零

#### Scenario: JSON 删除成功结果

- **WHEN** 用户执行 `ghostpin-cli delete 10000 --json` 且删除成功
- **THEN** 标准输出包含 `"ok": true` 和 `"id": 10000`，id 为整数

#### Scenario: JSON 初始化成功

- **WHEN** 用户执行 `ghostpin-cli init --json` 且安装成功
- **THEN** 标准输出只包含一个 JSON 对象，其中 `ok` 为 true，`path` 为最终真实安装目录的绝对路径，退出码为 0

#### Scenario: JSON 初始化失败

- **WHEN** 用户执行 `ghostpin-cli init --json` 且因缺少标记、链接无效或文件系统错误而失败
- **THEN** 标准输出只包含一个带 `"ok": false` 和 `"error"` 的 JSON 对象，退出码非零，错误说明包含具体原因

### Requirement: 命令级帮助

`ghostpin-cli` 根命令以及 `init`、`list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 命令 MUST 同时支持 `-h` 与 `--help`；帮助请求 SHALL 在业务参数校验和任务存储访问前处理，输出对应命令的用法、位置参数和可用选项，以退出码 0 结束且不得修改任务数据。新增帮助 MUST 明示 `--group` 必填，列表和修改帮助 MUST 说明组别选项，ID 帮助 MUST 说明使用从 `10000` 开始的整数。

#### Scenario: 根命令帮助

- **WHEN** 用户执行 `ghostpin-cli --help` 或 `ghostpin-cli -h`
- **THEN** CLI 输出命令列表与全局选项，以退出码 0 结束，命令列表包含 `init`

#### Scenario: 每条子命令均可查看帮助

- **WHEN** 用户对 `init`、`list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 中任一命令执行 `ghostpin-cli <command> --help` 或 `ghostpin-cli <command> -h`
- **THEN** CLI 输出该命令的专属用法、位置参数和选项，以退出码 0 结束，不要求提供 id、标题或其他业务参数

#### Scenario: 更新命令展示截止日期选项

- **WHEN** 用户执行 `ghostpin-cli update --help`
- **THEN** 帮助包含 `--due <ISO8601>`、`--clear-due` 和 `--group <组名>`，并说明未指定的任务字段保持不变

#### Scenario: 帮助请求无数据副作用

- **WHEN** 用户在任务文件不存在或内容不可读时执行任一帮助请求
- **THEN** CLI 仍正常输出帮助并以退出码 0 结束，不创建、读取或修改任务文件

#### Scenario: 新增和查询帮助说明组别

- **WHEN** 用户分别查看 `add --help` 和 `list --help`
- **THEN** 新增帮助将 `--group <组名>` 展示为必填参数，查询帮助说明该选项可与 `--all` 和 `--json` 组合

#### Scenario: 初始化帮助不触发安装

- **WHEN** 用户在随包 skill 缺失或安装目标不可读时执行 `ghostpin-cli init --help` 或 `ghostpin-cli init -h`
- **THEN** 命令正常展示安装路径、整目录覆盖、链接解析、归属保护和 `--json` 的说明，以退出码 0 结束，不读取随包 skill、不解析目标链接，也不创建或修改 skill 安装目录
