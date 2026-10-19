# Spec Delta

## MODIFIED Requirements

### Requirement: Windows 任务数据兼容

系统 SHALL 使用 `%LOCALAPPDATA%\GhostPin\todos.json` 作为 Windows 任务真源，并 MUST 支持 `task-storage` 定义的版本化文档、整数 ID、必填组别、三态状态值和 ISO 8601 日期。旧 UUID 数组 MUST 按相同规则备份并迁移为 `默认` 组和稳定整数 ID。首次没有任务目录或文件时 SHALL 以空列表继续运行；文件暂时无效或版本不受支持时 MUST 保留最后一次成功加载的列表、报告错误且不得覆盖文件或崩溃。

#### Scenario: 读取兼容任务文件

- **WHEN** Windows 任务文件包含新版本 GhostPin JSON 文档
- **THEN** HUD 正确读取任务整数标识、组别、标题、状态、优先级、截止时间和描述，并保留存储版本与下一编号

#### Scenario: 首次启动没有任务文件

- **WHEN** Windows 数据目录或任务文件尚不存在
- **THEN** HUD 显示空状态并保持运行，后续文件创建后仍可加载任务

#### Scenario: 任务文件暂时损坏

- **WHEN** 任务文件变为无法完整解析的内容
- **THEN** HUD 保留最后一次成功加载的任务列表、报告可诊断错误且不退出，不以空列表覆盖任务文件

#### Scenario: 读取旧 UUID 任务数组

- **WHEN** Windows 首次成功读取旧 UUID 任务数组
- **THEN** 原始内容被备份，全部任务按跨平台相同的稳定规则转换为整数 ID 和 `默认`，日期与其他业务字段保持不变

#### Scenario: 不同分组在 HUD 中显示

- **WHEN** 新版本任务文档包含多个组的未完成任务
- **THEN** HUD 继续按原有跨组统一列表投影，不增加分组筛选或编辑入口

### Requirement: Windows HUD 状态推进

交互模式下，HUD 任务卡片的圆形按钮 SHALL 将 Todo 推进为 Doing，并将 Doing 推进为 Done。状态变化 MUST 按整数 ID 在进程间锁内重新读取的最新任务文档中执行，原子写回后更新投影，保留组别、下一编号和其他未请求修改的字段。一次成功变化后的 500ms 内，系统 MUST 忽略同一任务的后续推进请求。

#### Scenario: Todo 推进为 Doing

- **WHEN** 用户在交互模式下点击 Todo 任务的圆形按钮
- **THEN** 系统将任务状态写为 `doing`，任务立即移动到 Doing 分区，整数 ID 和组别保持不变

#### Scenario: Doing 推进为 Done

- **WHEN** 用户在交互模式下点击 Doing 任务的圆形按钮且该任务不在冷却窗口内
- **THEN** 系统将任务状态写为 `done`、记录完成时间，并立即从 HUD 移除该任务，保留存储元数据

#### Scenario: 冷却窗口内重复点击

- **WHEN** 同一任务成功推进后 500ms 内再次收到推进请求
- **THEN** 系统忽略该请求且任务状态不发生第二次变化

#### Scenario: 外部写入后使用旧视图推进状态

- **WHEN** 外部进程已经新增任务或修改目标任务组别，HUD 随后推进已有任务状态
- **THEN** 状态写回保留外部新增任务、最新组别和最新下一编号，不覆盖旧视图没有的内容

#### Scenario: 目标任务已经被删除

- **WHEN** 外部进程已删除目标任务或任务文件，HUD 随后请求状态推进
- **THEN** 系统不重建已删除任务或文件，并报告状态推进未成功

## ADDED Requirements

### Requirement: Windows 任务卡片组别标记

Windows HUD SHALL 在任务标题行右侧依次展示优先级与组别标记，两个标记整体右对齐，并遵循 `task-priority-due-description` 的标记位置与组名展示宽度规则。默认组 MUST 显示为 `默认`；超长组名的显示省略 MUST 不改变完整组名，标记 MUST 不作为分组筛选或编辑入口。

#### Scenario: 展示默认组标记

- **WHEN** Windows HUD 展示属于 `默认` 组的任务
- **THEN** 优先级位于组别左侧，组别标记显示 `默认`，两个标记共同对齐到卡片右侧内容边界

#### Scenario: 长组名和不同窗口宽度

- **WHEN** 完整组名超过三个汉字宽度，或用户调整 HUD 宽度
- **THEN** 组名在上限内单行尾部省略，两个标记保持右对齐且不覆盖标题，存储中的组名不被截断
