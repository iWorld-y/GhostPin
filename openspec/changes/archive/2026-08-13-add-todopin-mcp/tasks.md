## 1. Package 与 DTO 下沉

- [x] 1.1 `Package.swift` 新增 library target `TodoPinMCP`（依赖 TodoPinCore）；`TodoPinCLI`、`TodoPinCoreChecks` 增加依赖
- [x] 1.2 `TodoItemPayload` 下沉 `TodoPinCore`（八字段显式编码），`TodoPinCLI/CLIOutput.swift` 改引用并删除旧 DTO
- [x] 1.3 `swift build` 通过，CLI JSON 输出逐字节不变（与重构前对比）

## 2. MCP 消息层

- [x] 2.1 `Sources/TodoPinMCP/Messages.swift`：JSONValue（递归 Codable）、JSON-RPC 请求/响应/错误类型、MCPID（Int/String 双形态）
- [x] 2.2 `TodoPinCoreChecks` 新增 checks：消息编解码、非法 JSON 映射 -32700、未知 method 映射 -32601
- [x] 2.3 `swift run TodoPinCoreChecks` 全绿

## 3. MCP 服务器循环

- [x] 3.1 `Sources/TodoPinMCP/Server.swift`：stdin 增量行缓冲、帧切分、dispatch、stdout 单点 writeLine + flush
- [x] 3.2 initialize / notifications/initialized / ping 处理，协议版本常量 2025-06-18
- [x] 3.3 checks：握手往返与 ping（构造帧 → Server 处理 → 断言响应）

## 4. MCP 工具层

- [x] 4.1 `Sources/TodoPinMCP/Tools.swift`：六个工具（list_tasks/create_task/update_task/complete_task/uncomplete_task/delete_task）的 schema 与描述
- [x] 4.2 工具执行：fresh-store-per-call（每次 load→操作→atomic save），参数显式提取校验，ISO8601 解析
- [x] 4.3 错误分层：未知工具 -32602；工具失败 isError content；成功 compact 8 字段 JSON
- [x] 4.4 checks：六个工具在临时目录存储上的行为与错误场景（含非法日期、id 不存在、update 无参数）

## 5. CLI 接入与验证

- [x] 5.1 `TodoPinCLI/main.swift` 增加 `mcp` 子命令分支与帮助文本
- [x] 5.2 `swift build` 通过；`swift run TodoPinCoreChecks` 全绿
- [x] 5.3 `./script/build_and_run.sh --verify` 通过
- [x] 5.4 管道冒烟：`printf 'initialize/tools/list/tools/call...' | todopin-cli mcp` 断言响应序列
- [x] 5.5 OpenCode 配置接入实测：Agent 通过 MCP 完成 list/create/complete 全链路，HUD 秒级刷新
