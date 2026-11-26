import Darwin
import Foundation

/// 所有任务访问共用固定文件锁，写入只基于锁内读取的最新文档。
final class TaskStorage {
    private let fileURL: URL
    private let legacyFileURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL, legacyFileURL: URL?, fileManager: FileManager) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
        self.fileManager = fileManager
    }

    func access<Result>(
        write: Bool,
        _ operation: (inout TaskDocument) throws -> Result
    ) throws -> (Result, TaskDocument) {
        try withLock {
            let loaded = try readLatest()
            var document = loaded.document
            let result = try operation(&document)
            try document.validate()
            if write || loaded.backup != nil {
                try commit(document, backup: loaded.backup)
            }
            return (result, document)
        }
    }

    /// 拖动受限写入：operation 返回结果与是否提交；拒绝时不做任何写入，包括迁移。
    func access<Result>(
        committing operation: (inout TaskDocument) throws -> (Result, Bool)
    ) throws -> (Result, TaskDocument) {
        try withLock {
            let loaded = try readLatest()
            var document = loaded.document
            let (result, shouldCommit) = try operation(&document)
            try document.validate()
            if shouldCommit {
                try commit(document, backup: loaded.backup)
            }
            return (result, document)
        }
    }

    private func commit(_ document: TaskDocument, backup: (data: Data, fileName: String)?) throws {
        if let backup {
            try preserveBackup(backup.data, fileName: backup.fileName)
        }
        try JSONFile.save(document, to: fileURL, fileManager: fileManager)
    }

    private struct DocumentVersion: Decodable {
        let schemaVersion: Int
    }

    private func readLatest() throws -> (document: TaskDocument, backup: (data: Data, fileName: String)?) {
        let source: URL
        if fileManager.fileExists(atPath: fileURL.path) {
            source = fileURL
        } else if let legacyFileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
            source = legacyFileURL
        } else {
            return (TaskDocument(), nil)
        }
        let data = try Data(contentsOf: source)
        do {
            let root = try JSONSerialization.jsonObject(with: data)
            if root is [Any] {
                let document = try migrateV1(data)
                try document.validate()
                return (document, (data, "todos.v1.backup.json"))
            }
            let decoder = JSONDecoder.ghostPin
            let version = try decoder.decode(DocumentVersion.self, from: data).schemaVersion
            switch version {
            case 2:
                let document = try decoder.decode(LegacyV2TaskDocument.self, from: data).migrated()
                try document.validate()
                return (document, (data, "todos.v2.backup.json"))
            case TaskDocument.currentSchemaVersion:
                let document = try decoder.decode(TaskDocument.self, from: data)
                try document.validate()
                return (document, nil)
            default:
                throw TaskStorageError.invalidDocument("不支持的任务存储版本：\(version)")
            }
        } catch let error as TaskStorageError {
            throw error
        } catch {
            throw TaskStorageError.invalidDocument("无法解析任务文档：\(error)")
        }
    }

    private func migrateV1(_ data: Data) throws -> TaskDocument {
        let legacy = try JSONDecoder.ghostPin.decode([LegacyTodoItem<UUID>].self, from: data)
        guard Set(legacy.map(\.id)).count == legacy.count else {
            throw TaskStorageError.invalidDocument("旧任务 UUID 重复")
        }
        let ordered = legacy.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
        let items = ordered.enumerated().map {
            $0.element.migrated(id: TaskDocument.firstID + Int64($0.offset), group: TaskGroup.defaultName)
        }
        return TaskDocument(nextID: TaskDocument.firstID + Int64(items.count), items: items)
    }

    private func withLock<Result>(_ operation: () throws -> Result) throws -> Result {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".todos.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        var status = flock(descriptor, LOCK_EX)
        while status != 0, errno == EINTR {
            status = flock(descriptor, LOCK_EX)
        }
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func preserveBackup(_ data: Data, fileName: String) throws {
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(fileName)
        let descriptor = Darwin.open(backupURL.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if descriptor < 0 {
            guard errno == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard try Data(contentsOf: backupURL) == data else {
                throw TaskStorageError.backupConflict(backupURL)
            }
            return
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
    }
}
