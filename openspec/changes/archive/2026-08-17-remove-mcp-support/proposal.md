## Why

TodoPin 已有独立 CLI，但 Agent 入口仍混合了协议服务、仓库构建产物和面向开发者的运行方式，导致安装用户可能调用错误二进制。需要把 Agent 操作统一收敛到随正式 App 分发的 CLI，并在删除旧入口前补齐现有任务写入能力。

## What Changes

- 新增随仓库维护的用户向 TodoPin CLI Skill，所有命令固定调用 `/Applications/TodoPin.app/Contents/MacOS/todopin-cli`，不包含协议服务、仓库构建或开发场景说明。
- 扩展 `todopin-cli add/update`，支持优先级、截止时间和描述的新增与修改，并支持清除截止时间，使 CLI 覆盖现有任务管理字段。
- 为根命令及 `list/add/doing/done/undone/update/delete/version` 提供 `-h`、`--help` 命令级帮助，帮助请求不得触发参数错误或数据读写。
- **BREAKING** 删除 `todopin-cli mcp` 子命令、TodoPinMCP Swift target、协议服务器实现和对应行为检查；依赖该子命令或工具协议的客户端需改用 CLI Skill。
- 更新当前 README、AGENTS、正式规格和发布说明入口，使产品定位与示例统一为 Skill + CLI；保留归档 OpenSpec 变更和既有发布历史，不改写历史记录。

## Capabilities

### New Capabilities

- `todo-agent-skill`: 定义面向安装用户的仓库内 Skill、固定 App Bundle CLI 路径、命令执行与失败提示约束。

### Modified Capabilities

- `todo-cli`: 补齐任务字段写入参数和逐命令帮助，删除协议服务器子命令与分发验收，并保持 App 未运行时可独立操作。
- `todo-status`: 将任务状态输出契约收敛为 CLI 输出。
- `hud-live-refresh`: 删除协议工具写入场景，仅保留 CLI 与文件监听行为。
- `todo-mcp-server`: 移除整个协议服务器能力及其全部要求。

## Impact

- 构建与源码：`Package.swift`、`Sources/TodoPinCLI/`、`Sources/TodoPinMCP/`。
- 测试：`Tests/TodoPinCoreChecks/main.swift` 删除协议测试并新增 CLI 参数与字段保持行为检查。
- Agent 入口：`skills/todopin-cli/` 改为安装用户专用，固定使用 App Bundle 内的 CLI。
- 文档与规格：`README.md`、`README.en.md`、`AGENTS.md`、相关主规格及发布说明。
- 兼容性：已注册的协议客户端将失效；`todos.json` 数据格式、App 展示和 CLI 现有命令保持兼容。
