import Foundation

/// 任务组名的统一校验；默认组只供调用方显式选择或历史迁移使用。
public enum TaskGroup {
    public static let defaultName = "默认"

    public static func normalize(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TaskStorageError.invalidDocument("组名不能为空")
        }
        return trimmed
    }
}
