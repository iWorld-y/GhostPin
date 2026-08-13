## Context

- `TodoPinCore` 提供全部任务操作；`todopin-cli` 已具备 6 个子命令与稳定的 8 字段 JSON 契约（DTO 目前在 `TodoPinCLI/CLIOutput.swift`，合成 Codable 会漏字段，已用手写 encode 解决）。
- `TodoPinCoreChecks` 是可执行 check 框架，只能 import 库 target（可执行 target 不可被依赖）——这是 MCP 逻辑需要独立 library target 的原因。
- `hud-live-refresh` 能力已就绪：外部进程写 todos.json 后 App 秒级刷新，MCP 写文件自然复用该链路。
- 项目零第三方 Swift 依赖（唯一 binaryTarget 是 whisper 框架）。

## Goals / Non-Goals

**Goals:**

- stdio MCP Server 最小协议子集，Agent 可结构化发现并调用六个工具。
- MCP 协议与工具逻辑可被现有 check 框架自动测试。
- 零新依赖；与 CLI、App 共用 TodoPinCore 与同一 JSON 契约。

**Non-Goals:**

- 不做 HTTP/SSE 传输；不做 resources/prompts 等其他 MCP 能力；不引入 MCP SDK。
- 不解析自然语言时间（延续 CLI 决策，时间一律显式 ISO8601）。
- 不做鉴权/多用户（本地单用户场景）。

## Decisions

### 1. `todopin-cli mcp` 子命令而非独立二进制

单入口、单配置点：OpenCode/Codex 配置里一条 `command: ["todopin-cli", "mcp"]`。替代方案（独立 `todopin-mcp` 二进制）多一个产品与安装面，无实际收益，否决。

### 2. 手写 JSON-RPC 子集，不引入 MCP SDK

只需 initialize/tools/list/tools/call/ping/notifications 五类消息与两层错误约定，约 200 行；首个 Swift 第三方依赖与项目零依赖现状冲突。MCP 核心消息稳定，演进风险可控；协议版本声明为 `2025-06-18`（客户端普遍支持，后续可按需升级）。

### 3. MCP 逻辑放独立 library target `TodoPinMCP`（可测性核心决策）

可执行 target 不可被依赖，测试框架 import 不到。`TodoPinMCP` 纯 Foundation：Messages（Codable 类型与任意 JSON 值）、Server（行缓冲循环）、Tools（工具定义与执行）。`TodoPinCLI` 与 `TodoPinCoreChecks` 都依赖它。

### 4. DTO 下沉 Core：`TodoItemPayload`

8 字段契约（含 isCompleted、null 显式）从 TodoPinCLI 移到 `TodoPinCore/Models/TodoItemPayload.swift`，CLI 与 MCP 共用。替代方案（MCP 自建 DTO）造成两份契约漂移，否决。todo-cli 规格无行为变化，不产生 MODIFIED delta。

### 5. fresh-store-per-call（数据新鲜度）

MCP 是长驻进程，若缓存 store，App/CLI 并发写入后 MCP 视图陈旧。每次工具调用新建 `TodoStore(fileURL:)`（load → 操作 → atomic save）后丢弃，代价是读一个小 JSON 文件，可忽略。测试注入临时目录 fileURL 即可隔离。

### 6. 错误分层

- 协议层：非法 JSON → -32700；未知 method → -32601；未知工具名 → -32602。
- 工具层：参数非法/id 不存在 → `{"content":[{"type":"text","text":"..."}],"isError":true}`，会话不断。
  理由：MCP 客户端把 isError 呈现给模型，让 Agent 能自我纠错重试；协议错误则视为客户端 bug。

### 7. 传输帧：增量行缓冲 + 单点写出

stdin 用 `FileHandle.standardInput.read(upToCount:)` 增量缓冲，按 `\n` 切分完整帧（防超长行）；stdout 只经一个 `writeLine` 函数输出并立即 flush；一切日志走 stderr。MCP stdio 要求消息不含内嵌换行，Compact JSON 编码保证单行。

### 8. 工具参数模型

`params` 解码为 `[String: JSONValue]`（手写递归 JSONValue Codable）；每个工具声明 JSON Schema（draft-07 风格 inputSchema）供客户端做结构化参数填充；执行时按字段类型显式提取校验，缺参/类型错 → isError 工具错误。

### 9. 结果文本

工具成功返回 `{"content":[{"type":"text","text":"<compact 8 字段 JSON>"}]}`；list_tasks 的 text 为任务数组 compact JSON。compact 单行，便于模型读取。

## Risks / Trade-offs

- [stdout 污染破坏协议] → 协议输出收敛到单一 writeLine；Server 不依赖 print；checks 覆盖编解码不回写日志。
- [手写协议随 MCP 演进需维护] → 只实现必需子集；版本声明集中在一个常量，升级点明确。
- [MCP/App/CLI 并发写] → 方案 A 已接受（atomic 写保证读者看到完整文件）；fresh-store-per-call 消除长驻进程的陈旧视图。
- [JSONValue 手写递归与 Codable 细节] → checks 覆盖嵌套参数编解码。

## Migration Plan

- 无数据迁移；DTO 下沉为纯重构（字段与顺序不变，CLI 输出逐字节兼容）。
- 回滚：移除 TodoPinMCP target 与 mcp 子命令分支即可，数据不受影响。
