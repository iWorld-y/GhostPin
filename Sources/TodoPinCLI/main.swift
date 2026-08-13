import Foundation
import TodoPinCore
import TodoPinMCP

private let isoFormatter = ISO8601DateFormatter()

private enum ExitCode: Int32 {
    case success = 0
    case runtimeError = 1
    case usageError = 2
}

private struct CLIError: Error {
    let message: String
    let code: ExitCode
}

private struct ParsedArguments {
    var positionals: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []
}

let rawArguments = Array(CommandLine.arguments.dropFirst())
let jsonRequested = rawArguments.contains("--json")

do {
    try run(rawArguments)
} catch let error as CLIError {
    emitFailure(error.message, exitCode: error.code)
} catch {
    emitFailure(error.localizedDescription, exitCode: .runtimeError)
}
exit(ExitCode.success.rawValue)

private func emitFailure(_ message: String, exitCode: ExitCode) -> Never {
    if jsonRequested {
        if let payload = try? jsonString(CLIFailureResponse(error: message)) {
            print(payload)
        }
    } else {
        FileHandle.standardError.write(Data(("错误: " + message + "\n").utf8))
    }
    exit(exitCode.rawValue)
}

private func run(_ arguments: [String]) throws {
    guard let command = arguments.first else {
        printUsage()
        return
    }
    switch command {
    case "--help", "-h", "help":
        printUsage()
    case "--version", "-v", "version":
        print("todopin-cli 0.1.0")
    case "list":
        try runList(Array(arguments.dropFirst()))
    case "add":
        try runAdd(Array(arguments.dropFirst()))
    case "done":
        try runSetCompleted(Array(arguments.dropFirst()), completed: true)
    case "undone":
        try runSetCompleted(Array(arguments.dropFirst()), completed: false)
    case "update":
        try runUpdate(Array(arguments.dropFirst()))
    case "delete":
        try runDelete(Array(arguments.dropFirst()))
    case "mcp":
        runMCPServer()
    default:
        throw CLIError(message: "未知命令: \(command)\n\n\(usageText)", code: .usageError)
    }
}

private func runList(_ arguments: [String]) throws {
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--all", "--json"])
    let store = try makeStore()
    let items = parsed.flags.contains("--all") ? store.items : store.openItems()

    if jsonRequested {
        try printJSON(items.map(TodoItemPayload.init))
    } else {
        for item in items {
            print("\(item.id.uuidString)\t\(item.isCompleted ? "done" : "open")\t\(item.title)")
        }
    }
}

private func runAdd(_ arguments: [String]) throws {
    let parsed = try parseArguments(arguments, valueFlags: ["--reminder"], booleanFlags: ["--json"])
    guard !parsed.positionals.isEmpty else {
        throw CLIError(message: "用法: todopin-cli add <标题> [--reminder <ISO8601>]", code: .usageError)
    }
    let title = parsed.positionals.joined(separator: " ")
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError(message: "任务标题不能为空", code: .usageError)
    }

    var reminderAt: Date?
    if let raw = parsed.values["--reminder"] {
        reminderAt = try parseReminder(raw)
    }

    let store = try makeStore()
    guard let item = try store.add(title: title, reminderAt: reminderAt) else {
        throw CLIError(message: "任务标题不能为空", code: .usageError)
    }
    try successOutput(item)
}

private func runSetCompleted(_ arguments: [String], completed: Bool) throws {
    let commandName = completed ? "done" : "undone"
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--json"])
    guard let idString = parsed.positionals.first else {
        throw CLIError(message: "用法: todopin-cli \(commandName) <id>", code: .usageError)
    }

    let id = try resolveID(idString)
    let store = try makeStore()
    _ = try requireItem(id, in: store)
    try store.setCompleted(id, completed: completed)
    let updated = try requireItem(id, in: store)
    try successOutput(updated)
}

private func runUpdate(_ arguments: [String]) throws {
    let parsed = try parseArguments(
        arguments,
        valueFlags: ["--title", "--reminder"],
        booleanFlags: ["--json", "--clear-reminder"]
    )
    guard let idString = parsed.positionals.first else {
        throw CLIError(
            message: "用法: todopin-cli update <id> [--title <标题>] [--reminder <ISO8601>] [--clear-reminder]",
            code: .usageError
        )
    }

    let hasTitle = parsed.values["--title"] != nil
    let hasReminder = parsed.values["--reminder"] != nil
    let clearsReminder = parsed.flags.contains("--clear-reminder")
    guard hasTitle || hasReminder || clearsReminder else {
        throw CLIError(message: "update 至少需要指定 --title、--reminder 或 --clear-reminder 之一", code: .usageError)
    }

    let id = try resolveID(idString)
    let store = try makeStore()
    let current = try requireItem(id, in: store)

    var newTitle = current.title
    if let title = parsed.values["--title"] {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError(message: "任务标题不能为空", code: .usageError)
        }
        newTitle = title
    }

    var newReminder = current.reminderAt
    if let raw = parsed.values["--reminder"] {
        newReminder = try parseReminder(raw)
    }
    if clearsReminder {
        newReminder = nil
    }

    guard let updated = try store.update(
        id,
        title: newTitle,
        reminderAt: newReminder,
        priority: current.priority,
        dueAt: current.dueAt,
        description: current.description
    ) else {
        throw CLIError(message: "更新失败", code: .runtimeError)
    }
    try successOutput(updated)
}

private func runDelete(_ arguments: [String]) throws {
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--json"])
    guard let idString = parsed.positionals.first else {
        throw CLIError(message: "用法: todopin-cli delete <id>", code: .usageError)
    }

    let id = try resolveID(idString)
    let store = try makeStore()
    _ = try requireItem(id, in: store)
    try store.delete(id)

    if jsonRequested {
        try printJSON(CLIIdSuccessResponse(id: id))
    } else {
        print(id.uuidString)
    }
}

private func parseArguments(
    _ arguments: [String],
    valueFlags: [String],
    booleanFlags: [String]
) throws -> ParsedArguments {
    var parsed = ParsedArguments()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--" {
            parsed.positionals.append(contentsOf: arguments[(index + 1)...])
            break
        }
        if argument.hasPrefix("--") {
            if valueFlags.contains(argument) {
                guard index + 1 < arguments.count else {
                    throw CLIError(message: "缺少参数值: \(argument)", code: .usageError)
                }
                parsed.values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            if booleanFlags.contains(argument) {
                parsed.flags.insert(argument)
                index += 1
                continue
            }
            throw CLIError(message: "未知参数: \(argument)", code: .usageError)
        }
        parsed.positionals.append(argument)
        index += 1
    }
    return parsed
}

private func makeStore() throws -> TodoStore {
    do {
        return try TodoStore()
    } catch {
        throw CLIError(message: "读取任务失败: \(error.localizedDescription)", code: .runtimeError)
    }
}

private func resolveID(_ string: String) throws -> TodoItem.ID {
    guard let id = UUID(uuidString: string.uppercased()) else {
        throw CLIError(message: "无效的任务 id: \(string)", code: .usageError)
    }
    return id
}

private func requireItem(_ id: TodoItem.ID, in store: TodoStore) throws -> TodoItem {
    guard let item = store.items.first(where: { $0.id == id }) else {
        throw CLIError(message: "未找到任务: \(id.uuidString)", code: .runtimeError)
    }
    return item
}

private func parseReminder(_ raw: String) throws -> Date {
    guard let date = isoFormatter.date(from: raw) else {
        throw CLIError(
            message: "无效的提醒时间: \(raw)（应为 ISO8601，如 2026-08-14T09:00:00+08:00）",
            code: .usageError
        )
    }
    return date
}

private func successOutput(_ item: TodoItem) throws {
    if jsonRequested {
        try printJSON(CLISuccessResponse(item: TodoItemPayload(item)))
    } else {
        print(item.id.uuidString)
    }
}

private func printJSON<T: Encodable>(_ value: T) throws {
    print(try jsonString(value))
}

private func runMCPServer() {
    do {
        let server = MCPServer(storeURL: try StorageLocations.todosURL())
        server.run()
    } catch {
        FileHandle.standardError.write(Data(("MCP 启动失败: \(error.localizedDescription)\n").utf8))
        exit(ExitCode.runtimeError.rawValue)
    }
}

private let usageText = """
todopin-cli - TodoPin 命令行工具

命令:
  list                          列出未完成任务（--all 含已完成）
  add <标题> [--reminder <ISO8601>]
                                新增任务
  done <id>                     标记任务完成
  undone <id>                   恢复任务为未完成
  update <id> [--title <标题>] [--reminder <ISO8601>] [--clear-reminder]
                                修改任务（至少指定一项）
  delete <id>                   删除任务
  mcp                           以 MCP stdio 服务器模式运行（供 OpenCode 等 Agent 调用）

选项:
  --json                        以 JSON 输出结果
  -h, --help                    显示帮助
  -v, --version                 显示版本
"""

private func printUsage() {
    print(usageText)
}
