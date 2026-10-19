import Foundation

/// 任务与下一编号共同持久化，避免删除或清空任务后复用 ID。
public struct TaskDocument: Codable, Equatable, Sendable {
    public static let firstID: Int64 = 10000
    // Windows JSON 数字也能精确表示，并给下一编号保留一个位置。
    public static let maximumID: Int64 = 9_007_199_254_740_990

    public let schemaVersion: Int
    public var nextID: Int64
    public var items: [TodoItem]

    public init(nextID: Int64 = firstID, items: [TodoItem] = []) {
        self.schemaVersion = 2
        self.nextID = nextID
        self.items = items
    }

    public func validate() throws {
        guard schemaVersion == 2 else {
            throw TaskStorageError.invalidDocument("不支持的任务存储版本：\(schemaVersion)")
        }
        guard nextID >= Self.firstID, nextID <= Self.maximumID + 1 else {
            throw TaskStorageError.invalidDocument("下一任务编号无效")
        }
        var identifiers: Set<Int64> = []
        for item in items {
            guard item.id >= Self.firstID, item.id <= Self.maximumID,
                  item.id < nextID, identifiers.insert(item.id).inserted else {
                throw TaskStorageError.invalidDocument("任务 ID 重复、越界或不小于下一编号")
            }
            guard try TaskGroup.normalize(item.group) == item.group else {
                throw TaskStorageError.invalidDocument("存储中的组名含首尾空白")
            }
        }
    }
}

public enum TaskStorageError: LocalizedError {
    case invalidDocument(String)
    case itemNotFound(Int64)
    case backupConflict(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidDocument(message):
            return message
        case let .itemNotFound(id):
            return "未找到任务：\(id)"
        case let .backupConflict(url):
            return "迁移备份与当前旧数据不一致：\(url.path)"
        }
    }
}
