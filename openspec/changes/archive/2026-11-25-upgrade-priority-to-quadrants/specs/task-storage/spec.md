# Spec Delta

## ADDED Requirements

### Requirement: 优先级模型 v2 到 v3 一次迁移

系统 SHALL 识别 `schemaVersion: 2` 的任务文档，在固定 `.todos.lock` 内于首次成功的数据访问中一次性升级为 `schemaVersion: 3`。迁移 MUST 保留原文档的 `nextID` 以及每条任务的 `id`、`group`、`title`、`createdAt`、`status`、`completedAt`、`reminderAt`、`reminderSentAt`、`dueAt`、`description`；每条任务的旧 `priority` MUST 确定性映射为 `important = (priority == "high")`（缺失旧 `priority` 按 `medium` 即 `important: false` 处理）且 `urgent = false`。

替换 v2 任务文件前，系统 MUST 将 v2 原文件逐字节备份为同目录的 `todos.v2.backup.json`，并遵循与 v1 备份相同的不可覆盖及冲突中止保护。

#### Scenario: 首次访问 v2 文档完成备份与升级

- **WHEN** 存在包含 `high`、`medium`、`low` 任务的合法 `schemaVersion: 2` 文档且首次执行成功查询或写操作
- **THEN** 系统在同目录写出与原 v2 文件逐字节一致的 `todos.v2.backup.json`，将 `todos.json` 原子替换为 `schemaVersion: 3`，原 `high` 任务变为 `important: true, urgent: false`，原 `medium`/`low` 任务变为 `important: false, urgent: false`，全部 ID、组别与 `nextID` 保持不变

#### Scenario: v2 备份内容冲突时中止迁移

- **WHEN** 同目录已存在 `todos.v2.backup.json` 且其字节内容与当前待迁移的 v2 文件不同
- **THEN** 系统报告备份冲突错误，不覆盖备份文件或 `todos.json`

#### Scenario: 升级后合并写操作

- **WHEN** 对尚未迁移的 v2 文件执行一次合法的 `add` 或 `update` 命令
- **THEN** 系统先将迁移前原始 v2 字节写入 `todos.v2.backup.json`，再在一次原子提交中落盘升级后的 v3 文档与本次业务修改

## MODIFIED Requirements

### Requirement: 版本化任务文档

任务文件 SHALL 使用包含 `schemaVersion`、`nextID` 和 `items` 的 JSON 对象，新版本的 `schemaVersion` MUST 为 `3`。`items` 中每条任务 MUST 具有唯一整数 `id`、非空且无首尾空白的字符串 `group`、布尔值 `important` 与布尔值 `urgent`，不再包含旧版 `priority` 字段；`nextID` MUST 不小于 `10000` 且大于全部现存 ID，日期继续使用 ISO 8601。

#### Scenario: 保存新版本任务文件

- **WHEN** 空任务库在 `默认` 组中首次成功新增一条 `important: true, urgent: false` 任务
- **THEN** 文件包含 `schemaVersion: 3`、`nextID: 10001`，且 `items` 包含 `id: 10000`、`group: "默认"`、`important: true`、`urgent: false` 的任务

#### Scenario: 初次读取没有任务文件

- **WHEN** 任务文件不存在且没有可迁移的旧数据
- **THEN** 系统返回空任务集合，下一编号为 `10000`，不因普通查询创建任务文件

### Requirement: 分组与 ID 一次迁移

系统 SHALL 识别旧 v1 UUID 任务数组，在首次成功的数据访问中一次性生成稳定整数 ID、为全部旧任务设置 `group: "默认"`、按 `important = (priority == "high")` 与 `urgent = false` 转换优先级，直接输出 `schemaVersion: 3` 文档并将 `nextID` 设为 `10000` 加旧任务数量。迁移前 MUST 将原始字节备份至 `todos.v1.backup.json`，保留任务标题、状态、创建时间、完成时间、提醒时间、已发送提醒时间、截止时间和描述。

#### Scenario: 同时升级未完成和已完成任务

- **WHEN** 旧数组中存在三条不同状态与旧优先级的任务
- **THEN** 成功迁移后产出 `schemaVersion: 3` 文档并保留三条任务，ID 按稳定顺序从 `10000` 分配、组别均为 `默认`、原 `high` 映为 `important: true` 且其余映为 `important: false`、`urgent` 均为 `false`，下一编号为 `10003`

#### Scenario: 迁移后立即新增任务

- **WHEN** 成功迁移两条历史任务后，新增一条显式指定组别、重要度与紧迫度的任务
- **THEN** 历史任务保持 `10000` 和 `10001`，新任务获得 `10002` 并按 `schemaVersion: 3` 持久化

#### Scenario: 重复访问新格式

- **WHEN** 文件已经是有效的 `schemaVersion: 3` 文档
- **THEN** 系统直接使用已保存的 ID、组别、重要度、紧迫度和下一编号，不再次执行历史迁移或写入备份

### Requirement: 无效文档不得重置

未知存储版本（既非旧数组也非受支持的 v2/v3 文档）、重复或非法 ID、空组别、非法下一编号、v3 任务缺失 `important` 或 `urgent` 布尔字段、v2 文档包含非法旧优先级以及损坏 JSON 内容 MUST 导致加载或写入失败，系统 MUST 报告可诊断错误，不得以空库覆盖原文件或根据现存任务重置下一编号。App 已有有效快照时 MUST 保留该快照。

#### Scenario: 下一编号小于现存 ID

- **WHEN** 文档的 `nextID` 不大于某条现存任务 ID
- **THEN** 系统拒绝文档，不自动修复计数器，不执行后续新增

#### Scenario: 外部文件暂时损坏

- **WHEN** App 已加载有效任务后，外部文件变为无效文档
- **THEN** App 保留最后一次成功加载的任务，原文件不被覆盖，并报告错误

#### Scenario: v3 文档缺少重要度或紧迫度字段

- **WHEN** `schemaVersion: 3` 的任务文件中某条任务缺失 `important` 或 `urgent` 字段（或类型非布尔）
- **THEN** 系统拒绝加载和写入，原文件保持不变并报告可诊断错误

### Requirement: 失败命令不触发迁移

CLI 的帮助和参数错误 MUST 不访问或迁移任务文件（包括缺少 `--group`、`--important`、`--urgent` 或传入已移除的 `--priority`）。业务目标不存在等失败操作 MUST 不提交 v1/v2 迁移、不创建备份、不变更任务或消耗编号；成功查询旧数据时允许执行一次完整迁移。

#### Scenario: 旧任务文件存在但新增缺少组别

- **WHEN** 调用方未提供必填组别而执行新增
- **THEN** 命令失败，旧文件及备份状态保持不变

#### Scenario: 对旧任务库操作不存在的数字 ID

- **WHEN** 根据稳定迁移映射或现存 v2 文档仍找不到指定数字 ID
- **THEN** 命令报错，不写入新格式或备份，不消耗编号

#### Scenario: v2 文件存在但新增缺少重要度或紧迫度

- **WHEN** 存在未迁移的 v2 文件且调用方执行缺少 `--important` 或 `--urgent` 的 `add` 命令
- **THEN** 命令失败，原 v2 文件保持不变且不生成 `todos.v2.backup.json`
