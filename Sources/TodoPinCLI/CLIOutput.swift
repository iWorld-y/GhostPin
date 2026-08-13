import Foundation
import TodoPinCore

struct CLISuccessResponse: Encodable {
    let ok = true
    let item: TodoItemPayload
}

struct CLIIdSuccessResponse: Encodable {
    let ok = true
    let id: TodoItem.ID
}

struct CLIFailureResponse: Encodable {
    let ok = false
    let error: String
}

func jsonString<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder.todoPin.encode(value)
    return String(decoding: data, as: UTF8.self)
}
