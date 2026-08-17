## 1. 核心状态模型与持久化

- [x] 1.1 在 `TodoPinCore` 增加 `TodoStatus`（`todo`、`doing`、`done`）并扩展 `TodoItem`、`TodoItemPayload` 的编码/解码与状态输出，保持 `completedAt` 和 `isCompleted` 兼容。
- [x] 1.2 为旧任务实现状态推导：缺少 `status` 且有 `completedAt` 映射为 Done，否则映射为 Todo；覆盖旧字段完整保留和新字段写入测试。
- [x] 1.3 在 `TodoStore` 增加统一状态变更能力，保证 Todo/Doing/Done 转换、完成时间设置/清除、未知任务处理和保存行为符合 spec；保留 `setCompleted` 兼容入口。
- [x] 1.4 调整未完成任务排序和 HUD 条数截断：先按 Doing→Todo，再按既有优先级、截止时间、逾期状态和创建时间规则；补充多个 Doing 与跨区域上限测试。
- [x] 1.5 更新 `Tests/TodoPinCoreChecks/main.swift` 的 checks 注册，覆盖三态转换、旧数据兼容、`isCompleted`/`completedAt` 一致性、提醒/逾期语义和状态排序。

## 2. CLI 状态操作

- [x] 2.1 增加 `todopin-cli doing <id>` 命令、参数校验、错误退出码、文本输出和 `--help` 用法说明。
- [x] 2.2 更新 CLI 的 `list`、`done`、`undone` 和 JSON 输出，使默认结果包含 Todo/Doing、Doing 排在 Todo 前，并输出 `status` 字段；确认 `undone` 将 Done/Doing 恢复为 Todo。
- [x] 2.3 在核心行为检查中覆盖 CLI 状态生命周期、重复设置 Doing、无效 id、JSON 成功/失败结构和旧命令兼容行为。

## 3. MCP 状态工具

- [x] 3.1 增加 `start_task` 工具声明与执行逻辑，更新 `tools/list` 的七工具契约、输入 schema 和错误映射。
- [x] 3.2 更新 `list_tasks`、`create_task`、`complete_task`、`uncomplete_task` 的状态字段、筛选和恢复语义，确保所有任务 payload 包含 `status`、`completedAt` 与 `isCompleted`。
- [x] 3.3 扩展 MCP 行为检查，覆盖 start/complete/uncomplete 生命周期、Doing 默认查询、重复 start、未知 id、工具列表数量和外部写入后的新鲜读取。

## 4. HUD 分区与交互

- [x] 4.1 在 `AppState` 增加 Todo→Doing→Done 的按钮推进逻辑，并按任务 id 实现 500ms 单调时钟点击冷却；冷却内点击不得触发第二次写入。
- [x] 4.2 更新 HUD 视图按 Doing、Todo 分区渲染，隐藏空区域，保留每区现有排序，并让圆形按钮根据任务状态推进到下一状态。
- [x] 4.3 验证交互模式/穿透模式边界、分区移动、完成后消失、状态点击不抢焦点和列表无闪烁；必要时补充可执行的行为检查或手动验收步骤。

## 5. 集成验证与交付检查

- [x] 5.1 运行 `swift run TodoPinCoreChecks`，确认核心、CLI 和 MCP 行为检查全部通过。
- [x] 5.2 运行 `swift build`，确认 TodoPin、todopin-cli 和 MCP 相关目标编译通过。
- [x] 5.3 按 HUD live refresh 场景验证 CLI/MCP 设置 Doing 后 App 数秒内重新分区，且外部刷新不抢焦点。
- [x] 5.4 用旧格式 `todos.json` 做一次读取与保存回归，确认 Todo/Done 兼容，并记录旧版本回滚时 Doing 可能退化为 Todo 的限制。
