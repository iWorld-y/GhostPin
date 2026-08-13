## Why

需求文档 `docs/需求-2026-08-13.md` 第三阶段：让 OpenCode、Codex、Claude Code 等 Agent 通过 MCP 直接管理 TodoPin。MCP 不单独维护任务逻辑——在 `TodoPinCore` 与既有 CLI 能力之上薄封装，`todopin-cli mcp` 子命令以 stdio 传输提供 MCP Server。

## What Changes

- `Package.swift` 新增 library target `TodoPinMCP`（纯 Foundation，依赖 `TodoPinCore`）；`TodoPinCLI` 与 `TodoPinCoreChecks` 增加对它的依赖。
- `todopin-cli mcp` 子命令：长驻 stdio 进程，newline-delimited JSON-RPC 2.0，实现 initialize / notifications/initialized / ping / tools/list / tools/call 最小协议子集（协议版本 2025-06-18）。
- 六个 MCP 工具：`list_tasks`、`create_task`、`update_task`、`complete_task`、`uncomplete_task`、`delete_task`，参数显式（提醒时间 ISO8601，不解析自然语言），带完整 inputSchema。
- 工具结果复用稳定的 8 字段任务 JSON 契约：该 DTO 从 CLI target 下沉到 `TodoPinCore`（`TodoItemPayload`），CLI 与 MCP 共用，避免双份契约漂移。
- 错误分层：协议错误走 JSON-RPC error（-32700 解析错、-32601 方法不存在、-32602 无效参数）；工具执行失败返回 `{"content":[...],"isError":true}`，会话不断。
- 数据新鲜度：每次工具调用重新 load 存储再操作再 atomic 保存（长驻进程不缓存陈旧数据）。
- `TodoPinCoreChecks` 新增对 MCP 消息编解码、工具 schema、工具执行（临时目录注入存储）的 checks。

## Capabilities

### New Capabilities

- `todo-mcp-server`: MCP stdio 服务器的协议行为、六个工具及其输入/输出契约、错误分层与数据一致性。

### Modified Capabilities

（无。`todo-cli` 的 JSON 契约不变，仅 DTO 实现位置下沉，行为无变化。）

## Impact

- 代码：
  - `Package.swift`：`TodoPinMCP` library target 及依赖关系。
  - `Sources/TodoPinMCP/`（新增）：Messages（JSON-RPC 类型）、Server（行缓冲循环与分发）、Tools（六个工具定义与执行）。
  - `Sources/TodoPinCore/Models/TodoItemPayload.swift`（新增）：从 TodoPinCLI 下沉的 8 字段 DTO；`Sources/TodoPinCLI/CLIOutput.swift` 改引用。
  - `Sources/TodoPinCLI/main.swift`：新增 `mcp` 子命令分支与帮助文本。
  - `Tests/TodoPinCoreChecks/main.swift`：MCP 相关 checks。
- 依赖：无新增第三方依赖（Foundation 手写协议）。
- 风险：手写协议子集需随 MCP 演进维护；stdout 必须保持协议纯净（日志只走 stderr）。
