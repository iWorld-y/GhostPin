import Foundation
import GhostPinCore

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
    case "--help", "-h":
        printUsage()
    case "help":
        let helpArguments = Array(arguments.dropFirst())
        if let commandName = helpArguments.first {
            printCommandHelp(commandName)
        } else {
            printUsage()
        }
    case "--version", "-v":
        print("ghostpin-cli 0.1.0")
    case "version":
        try runVersion(Array(arguments.dropFirst()))
    case "list":
        try runList(Array(arguments.dropFirst()))
    case "add":
        try runAdd(Array(arguments.dropFirst()))
    case "doing":
        try runSetStatus(Array(arguments.dropFirst()), status: .doing, commandName: "doing")
    case "done":
        try runSetStatus(Array(arguments.dropFirst()), status: .done, commandName: "done")
    case "undone":
        try runSetStatus(Array(arguments.dropFirst()), status: .todo, commandName: "undone")
    case "update":
        try runUpdate(Array(arguments.dropFirst()))
    case "delete":
        try runDelete(Array(arguments.dropFirst()))
    default:
        throw CLIError(message: "未知命令: \(command)\n\n\(usageText())", code: .usageError)
    }
}

private func runList(_ arguments: [String]) throws {
    if wantsHelp(arguments) {
        printCommandHelp("list")
        return
    }
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--all", "--json"])
    let store = try makeStore()
    let items = parsed.flags.contains("--all") ? store.items : store.openItems()

    if jsonRequested {
        try printJSON(items.map(TodoItemPayload.init))
    } else {
        for item in items {
            print("\(item.id.uuidString)\t\(item.status.rawValue)\t\(item.title)")
        }
    }
}

private func runAdd(_ arguments: [String]) throws {
    if wantsHelp(arguments) {
        printCommandHelp("add")
        return
    }
    let parsed = try parseArguments(
        arguments,
        valueFlags: ["--reminder", "--priority", "--due", "--description"],
        booleanFlags: ["--json"]
    )
    guard !parsed.positionals.isEmpty else {
        throw CLIError(message: "用法: \(usageText(for: "add"))", code: .usageError)
    }
    let title = parsed.positionals.joined(separator: " ")
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError(message: "任务标题不能为空", code: .usageError)
    }

    var reminderAt: Date?
    if let raw = parsed.values["--reminder"] {
        reminderAt = try parseReminder(raw)
    }
    let priority = try parsePriority(parsed.values["--priority"])
    let dueAt = try parseDueDate(parsed.values["--due"])
    let description = parsed.values["--description"]

    let store = try makeStore()
    guard let item = try store.add(
        title: title,
        reminderAt: reminderAt,
        priority: priority,
        dueAt: dueAt,
        description: description
    ) else {
        throw CLIError(message: "任务标题不能为空", code: .usageError)
    }
    try successOutput(item)
}

private func runSetStatus(_ arguments: [String], status: TodoStatus, commandName: String) throws {
    if wantsHelp(arguments) {
        printCommandHelp(commandName)
        return
    }
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--json"])
    guard let idString = parsed.positionals.first else {
        throw CLIError(message: "用法: \(usageText(for: commandName))", code: .usageError)
    }

    let id = try resolveID(idString)
    let store = try makeStore()
    _ = try requireItem(id, in: store)
    try store.setStatus(id, status: status)
    let updated = try requireItem(id, in: store)
    try successOutput(updated)
}

private func runUpdate(_ arguments: [String]) throws {
    if wantsHelp(arguments) {
        printCommandHelp("update")
        return
    }
    let parsed = try parseArguments(
        arguments,
        valueFlags: ["--title", "--reminder", "--priority", "--due", "--description"],
        booleanFlags: ["--json", "--clear-reminder", "--clear-due"]
    )
    guard let idString = parsed.positionals.first else {
        throw CLIError(message: "用法: \(usageText(for: "update"))", code: .usageError)
    }

    let hasTitle = parsed.values["--title"] != nil
    let hasReminder = parsed.values["--reminder"] != nil
    let clearsReminder = parsed.flags.contains("--clear-reminder")
    let hasPriority = parsed.values["--priority"] != nil
    let hasDue = parsed.values["--due"] != nil
    let clearsDue = parsed.flags.contains("--clear-due")
    let hasDescription = parsed.values["--description"] != nil
    guard hasTitle || hasReminder || clearsReminder || hasPriority || hasDue || clearsDue || hasDescription else {
        throw CLIError(message: "update 至少需要指定一项修改参数", code: .usageError)
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

    var newPriority = current.priority
    if let raw = parsed.values["--priority"] {
        newPriority = try parsePriority(raw)
    }

    var newDue = current.dueAt
    if let raw = parsed.values["--due"] {
        newDue = try parseDueDate(raw)
    }
    if clearsDue {
        newDue = nil
    }

    let newDescription = parsed.values["--description"] ?? current.description

    guard let updated = try store.update(
        id,
        title: newTitle,
        reminderAt: newReminder,
        priority: newPriority,
        dueAt: newDue,
        description: newDescription
    ) else {
        throw CLIError(message: "更新失败", code: .runtimeError)
    }
    try successOutput(updated)
}

private func runDelete(_ arguments: [String]) throws {
    if wantsHelp(arguments) {
        printCommandHelp("delete")
        return
    }
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: ["--json"])
    guard let idString = parsed.positionals.first else {
        throw CLIError(message: "用法: \(usageText(for: "delete"))", code: .usageError)
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

private func runVersion(_ arguments: [String]) throws {
    if wantsHelp(arguments) {
        printCommandHelp("version")
        return
    }
    let parsed = try parseArguments(arguments, valueFlags: [], booleanFlags: [])
    guard parsed.positionals.isEmpty else {
        throw CLIError(message: "用法: \(usageText(for: "version"))", code: .usageError)
    }
    print("ghostpin-cli 0.1.0")
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
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: raw) else {
        throw CLIError(
            message: "无效的提醒时间: \(raw)（应为 ISO8601，如 2026-08-14T09:00:00+08:00）",
            code: .usageError
        )
    }
    return date
}

private func parseDueDate(_ raw: String?) throws -> Date? {
    guard let raw else {
        return nil
    }
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: raw) else {
        throw CLIError(
            message: "无效的截止时间: \(raw)（应为 ISO8601，如 2026-08-14T18:00:00+08:00）",
            code: .usageError
        )
    }
    return date
}

private func parsePriority(_ raw: String?) throws -> Priority {
    guard let raw else {
        return .medium
    }
    guard let priority = Priority(rawValue: raw) else {
        throw CLIError(message: "无效的优先级: \(raw)（可选 high、medium、low）", code: .usageError)
    }
    return priority
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

private func wantsHelp(_ arguments: [String]) -> Bool {
    arguments.contains("-h") || arguments.contains("--help")
}

private func usageText(for command: String) -> String {
    switch command {
    case "list":
        return "ghostpin-cli list [--all] [--json]"
    case "add":
        return "ghostpin-cli add <标题> [--reminder <ISO8601>] [--priority <high|medium|low>] [--due <ISO8601>] [--description <描述>]"
    case "doing", "done", "undone", "delete":
        return "ghostpin-cli \(command) <id>"
    case "update":
        return "ghostpin-cli update <id> [--title <标题>] [--reminder <ISO8601>] [--clear-reminder] [--priority <high|medium|low>] [--due <ISO8601>] [--clear-due] [--description <描述>]"
    case "version":
        return "ghostpin-cli version"
    default:
        return "ghostpin-cli --help"
    }
}

private func printCommandHelp(_ command: String) {
    switch command {
    case "list":
        print("""
        \(usageText(for: "list"))
          列出任务；默认只显示未完成任务，--all 包含已完成任务。
        """)
    case "add":
        print("""
        \(usageText(for: "add"))
          新增任务。日期必须使用 ISO8601，优先级默认为 medium。
        """)
    case "doing", "done", "undone":
        print("""
        \(usageText(for: command))
          将指定任务标记为对应状态。
        """)
    case "update":
        print("""
        \(usageText(for: "update"))
          修改任务；至少指定一项参数，未指定的字段保持不变。
          --clear-reminder 清除提醒时间，--clear-due 清除截止时间。
        """)
    case "delete":
        print("""
        \(usageText(for: "delete"))
          删除指定任务。
        """)
    case "version":
        print("""
        \(usageText(for: "version"))
          显示 CLI 版本。
        """)
    default:
        print("未知命令: \(command)\n\n\(usageText())")
    }
}

private func usageText() -> String {
    """
ghostpin-cli - GhostPin 命令行工具

命令:
  \(usageText(for: "list"))
  \(usageText(for: "add"))
  \(usageText(for: "doing"))
  \(usageText(for: "done"))
  \(usageText(for: "undone"))
  \(usageText(for: "update"))
  \(usageText(for: "delete"))
  \(usageText(for: "version"))

选项:
  --json                        以 JSON 输出结果
  -h, --help                    显示帮助
  -v, --version                 显示版本
"""
}

private func printUsage() {
    print(usageText())
}

do {
    try run(rawArguments)
} catch let error as CLIError {
    emitFailure(error.message, exitCode: error.code)
} catch {
    emitFailure(error.localizedDescription, exitCode: .runtimeError)
}
exit(ExitCode.success.rawValue)
