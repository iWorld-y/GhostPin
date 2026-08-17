## REMOVED Requirements

### Requirement: stdio 传输与协议握手
**Reason**: TodoPin 的 Agent 操作入口统一为用户向 CLI Skill，不再维护常驻协议服务。
**Migration**: 直接调用 `/Applications/TodoPin.app/Contents/MacOS/todopin-cli` 的相应命令。

### Requirement: 工具发现
**Reason**: 删除协议工具注册和发现机制，任务能力由 Skill 中的 CLI 命令说明提供。
**Migration**: 读取 `skills/todopin-cli/SKILL.md` 并调用其中列出的 CLI 命令。

### Requirement: list_tasks 工具
**Reason**: 查询能力收敛到 CLI。
**Migration**: 使用 `todopin-cli list --json` 或 `todopin-cli list --all --json`。

### Requirement: create_task 工具
**Reason**: 创建能力收敛到已补齐字段参数的 CLI。
**Migration**: 使用 `todopin-cli add` 及 `--reminder`、`--priority`、`--due`、`--description` 参数。

### Requirement: complete_task 与 uncomplete_task 工具
**Reason**: 完成与恢复能力收敛到 CLI。
**Migration**: 分别使用 `todopin-cli done <id>` 和 `todopin-cli undone <id>`。

### Requirement: start_task 工具
**Reason**: 设置 Doing 的能力收敛到 CLI。
**Migration**: 使用 `todopin-cli doing <id>`。

### Requirement: update_task 工具
**Reason**: 修改能力收敛到已补齐字段参数的 CLI。
**Migration**: 使用 `todopin-cli update <id>` 及对应字段参数。

### Requirement: delete_task 工具
**Reason**: 删除能力收敛到 CLI。
**Migration**: 使用 `todopin-cli delete <id>`。

### Requirement: 协议错误与工具错误分层
**Reason**: 协议层被删除，不再存在协议错误与工具错误的分层契约。
**Migration**: 以 CLI 非零退出码和 `--json` 失败响应判断错误。

### Requirement: 数据新鲜度与一致性
**Reason**: 不再通过长驻服务器读取任务数据；每次 CLI 调用直接加载并保存共享存储。
**Migration**: 每个 Agent 操作独立调用 CLI，App 继续通过文件监听刷新。
