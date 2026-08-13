import Foundation
import TodoPinCore

public enum JSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "不支持的 JSON 值"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public enum MCPID: Equatable, Sendable, Codable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "id 必须是整数或字符串"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

public struct MCPRequest: Codable, Sendable {
    public let id: MCPID
    public let method: String
    public let params: JSONValue?
}

public struct MCPNotification: Codable, Sendable {
    public let method: String
    public let params: JSONValue?
}

public struct MCPSuccessResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: MCPID
    public let result: JSONValue

    public init(id: MCPID, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
    }
}

public struct MCPErrorDetail: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct MCPErrorResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: MCPID?
    public let error: MCPErrorDetail

    public init(id: MCPID?, code: Int, message: String) {
        self.jsonrpc = "2.0"
        self.id = id
        self.error = MCPErrorDetail(code: code, message: message)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(error, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case error
    }
}

public enum MCPErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

public enum MCPFrame {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var frame = try JSONEncoder().encode(value)
        frame.append(0x0A)
        return frame
    }
}

public func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder.todoPin.encode(value)
    return try JSONDecoder.todoPin.decode(JSONValue.self, from: data)
}
