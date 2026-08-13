import Foundation
import TodoPinCore

public struct MCPToolError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

public struct ToolDefinition {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    let execute: (JSONValue, URL) throws -> JSONValue
}

private let isoFormatter = ISO8601DateFormatter()

public func toolDefinitions() -> [ToolDefinition] {
    [
        listTasksTool,
        createTaskTool,
        updateTaskTool,
        completeTaskTool,
        uncompleteTaskTool,
        deleteTaskTool
    ]
}

private let listTasksTool = ToolDefinition(
    name: "list_tasks",
    description: "查询任务。默认只返回未完成任务，include_completed 为 true 时返回全部。",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "include_completed": .object([
                "type": .string("boolean"),
                "description": .string("是否包含已完成任务，默认 false")
            ])
        ])
    ])
) { arguments, storeURL in
    let object = try argumentsObject(arguments)
    let includeCompleted = optionalBool(object, "include_completed") ?? false
    let store = try makeStore(at: storeURL)
    let items = includeCompleted ? store.items : store.openItems()
    return try jsonValue(items.map(TodoItemPayload.init))
}

private let createTaskTool = ToolDefinition(
    name: "create_task",
    description: "创建任务。title 必填；reminder_at 为可选提醒时间（ISO8601）；priority 可选 high/medium/low，默认 medium；due_at 为可选截止时间（ISO8601）；description 为可选描述。不解析自然语言时间。",
    inputSchema: .object([
        "type": .string("object"),
        "required": .array([.string("title")]),
        "properties": .object([
            "title": .object([
                "type": .string("string"),
                "description": .string("任务标题")
            ]),
            "reminder_at": .object([
                "type": .string("string"),
                "description": .string("提醒时间，ISO8601 格式")
            ]),
            "priority": .object([
                "type": .string("string"),
                "enum": .array([.string("high"), .string("medium"), .string("low")]),
                "description": .string("优先级：high/medium/low，默认 medium")
            ]),
            "due_at": .object([
                "type": .string("string"),
                "description": .string("截止时间，ISO8601 格式")
            ]),
            "description": .object([
                "type": .string("string"),
                "description": .string("描述文本")
            ])
        ])
    ])
) { arguments, storeURL in
    let object = try argumentsObject(arguments)
    let title = try requireString(object, "title")
    let reminderAt = try optionalDate(object, "reminder_at")
    let priority = try optionalPriority(object, "priority") ?? .medium
    let dueAt = try optionalDate(object, "due_at")
    let description = optionalString(object, "description")
    let store = try makeStore(at: storeURL)
    guard let item = try store.add(
        title: title,
        source: .text,
        reminderAt: reminderAt,
        priority: priority,
        dueAt: dueAt,
        description: description
    ) else {
        throw MCPToolError("任务标题不能为空")
    }
    return try jsonValue(TodoItemPayload(item))
}

private let updateTaskTool = ToolDefinition(
    name: "update_task",
    description: "修改任务。title、reminder_at、clear_reminder、priority、due_at、clear_due、description 至少提供一项；未提供的字段保持不变。",
    inputSchema: .object([
        "type": .string("object"),
        "required": .array([.string("id")]),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("任务 id")
            ]),
            "title": .object([
                "type": .string("string"),
                "description": .string("新标题")
            ]),
            "reminder_at": .object([
                "type": .string("string"),
                "description": .string("新提醒时间，ISO8601 格式")
            ]),
            "clear_reminder": .object([
                "type": .string("boolean"),
                "description": .string("为 true 时清除提醒时间")
            ]),
            "priority": .object([
                "type": .string("string"),
                "enum": .array([.string("high"), .string("medium"), .string("low")]),
                "description": .string("新优先级：high/medium/low")
            ]),
            "due_at": .object([
                "type": .string("string"),
                "description": .string("新截止时间，ISO8601 格式")
            ]),
            "clear_due": .object([
                "type": .string("boolean"),
                "description": .string("为 true 时清除截止时间")
            ]),
            "description": .object([
                "type": .string("string"),
                "description": .string("新描述文本")
            ])
        ])
    ])
) { arguments, storeURL in
    let object = try argumentsObject(arguments)
    let id = try requireID(object)
    let hasTitle = object["title"] != nil
    let hasReminder = object["reminder_at"] != nil
    let clearReminder = optionalBool(object, "clear_reminder") ?? false
    let hasPriority = object["priority"] != nil
    let hasDue = object["due_at"] != nil
    let clearDue = optionalBool(object, "clear_due") ?? false
    let hasDescription = object["description"] != nil
    guard hasTitle || hasReminder || clearReminder || hasPriority || hasDue || clearDue || hasDescription else {
        throw MCPToolError("update_task 至少需要提供 title、reminder_at、clear_reminder、priority、due_at、clear_due 或 description 之一")
    }

    let store = try makeStore(at: storeURL)
    guard let current = store.items.first(where: { $0.id == id }) else {
        throw MCPToolError("未找到任务: \(id.uuidString)")
    }

    var newTitle = current.title
    if let title = optionalString(object, "title") {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPToolError("任务标题不能为空")
        }
        newTitle = trimmed
    }

    var newReminder = current.reminderAt
    if let raw = optionalString(object, "reminder_at") {
        newReminder = try parseISO8601(raw)
    }
    if clearReminder {
        newReminder = nil
    }

    var newPriority = current.priority
    if let priority = try optionalPriority(object, "priority") {
        newPriority = priority
    }

    var newDue = current.dueAt
    if let raw = optionalString(object, "due_at") {
        newDue = try parseISO8601(raw)
    }
    if clearDue {
        newDue = nil
    }

    var newDescription = current.description
    if let description = optionalString(object, "description") {
        newDescription = description
    }

    guard let updated = try store.update(
        id,
        title: newTitle,
        reminderAt: newReminder,
        priority: newPriority,
        dueAt: newDue,
        description: newDescription
    ) else {
        throw MCPToolError("更新失败")
    }
    return try jsonValue(TodoItemPayload(updated))
}

private let completeTaskTool = ToolDefinition(
    name: "complete_task",
    description: "将指定任务标记为完成。",
    inputSchema: .object([
        "type": .string("object"),
        "required": .array([.string("id")]),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("任务 id")
            ])
        ])
    ])
) { arguments, storeURL in
    try setCompleted(arguments, storeURL: storeURL, completed: true)
}

private let uncompleteTaskTool = ToolDefinition(
    name: "uncomplete_task",
    description: "将已完成任务恢复为未完成。",
    inputSchema: .object([
        "type": .string("object"),
        "required": .array([.string("id")]),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("任务 id")
            ])
        ])
    ])
) { arguments, storeURL in
    try setCompleted(arguments, storeURL: storeURL, completed: false)
}

private let deleteTaskTool = ToolDefinition(
    name: "delete_task",
    description: "删除指定任务。",
    inputSchema: .object([
        "type": .string("object"),
        "required": .array([.string("id")]),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("任务 id")
            ])
        ])
    ])
) { arguments, storeURL in
    let object = try argumentsObject(arguments)
    let id = try requireID(object)
    let store = try makeStore(at: storeURL)
    guard store.items.contains(where: { $0.id == id }) else {
        throw MCPToolError("未找到任务: \(id.uuidString)")
    }
    try store.delete(id)
    return .object([
        "deleted": .bool(true),
        "id": .string(id.uuidString)
    ])
}

private func setCompleted(_ arguments: JSONValue, storeURL: URL, completed: Bool) throws -> JSONValue {
    let object = try argumentsObject(arguments)
    let id = try requireID(object)
    let store = try makeStore(at: storeURL)
    guard store.items.contains(where: { $0.id == id }) else {
        throw MCPToolError("未找到任务: \(id.uuidString)")
    }
    try store.setCompleted(id, completed: completed)
    guard let updated = store.items.first(where: { $0.id == id }) else {
        throw MCPToolError("未找到任务: \(id.uuidString)")
    }
    return try jsonValue(TodoItemPayload(updated))
}

private func makeStore(at storeURL: URL) throws -> TodoStore {
    let store = TodoStore(fileURL: storeURL)
    try store.load()
    return store
}

private func argumentsObject(_ arguments: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let object) = arguments else {
        throw MCPToolError("参数必须是对象")
    }
    return object
}

private func requireString(_ object: [String: JSONValue], _ key: String) throws -> String {
    guard case .string(let value)? = object[key], !value.isEmpty else {
        throw MCPToolError("缺少或无效参数: \(key)")
    }
    return value
}

private func requireID(_ object: [String: JSONValue]) throws -> TodoItem.ID {
    let raw = try requireString(object, "id")
    guard let id = UUID(uuidString: raw.uppercased()) else {
        throw MCPToolError("无效的任务 id: \(raw)")
    }
    return id
}

private func optionalString(_ object: [String: JSONValue], _ key: String) -> String? {
    guard case .string(let value)? = object[key] else {
        return nil
    }
    return value
}

private func optionalBool(_ object: [String: JSONValue], _ key: String) -> Bool? {
    guard case .bool(let value)? = object[key] else {
        return nil
    }
    return value
}

private func optionalDate(_ object: [String: JSONValue], _ key: String) throws -> Date? {
    guard let raw = optionalString(object, key) else {
        return nil
    }
    return try parseISO8601(raw)
}

private func optionalPriority(_ object: [String: JSONValue], _ key: String) throws -> Priority? {
    guard let raw = optionalString(object, key) else {
        return nil
    }
    guard let priority = Priority(rawValue: raw) else {
        throw MCPToolError("无效的优先级: \(raw)（应为 high/medium/low）")
    }
    return priority
}

private func parseISO8601(_ raw: String) throws -> Date {
    guard let date = isoFormatter.date(from: raw) else {
        throw MCPToolError("无效的日期时间: \(raw)（应为 ISO8601，如 2026-08-14T09:00:00+08:00）")
    }
    return date
}
