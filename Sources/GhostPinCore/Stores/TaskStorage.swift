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
            if let legacyData = loaded.legacyData {
                try preserveBackup(legacyData)
            }
            if write || loaded.legacyData != nil {
                try JSONFile.save(document, to: fileURL, fileManager: fileManager)
            }
            return (result, document)
        }
    }

    private func readLatest() throws -> (document: TaskDocument, legacyData: Data?) {
        let source: URL
        if fileManager.fileExists(atPath: fileURL.path) {
            source = fileURL
        } else if let legacyFileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
            source = legacyFileURL
        } else {
            return (TaskDocument(), nil)
        }
        let data = try Data(contentsOf: source)
        let root = try JSONSerialization.jsonObject(with: data)
        if root is [Any] {
            let legacy = try JSONDecoder.ghostPin.decode([LegacyTodoItem].self, from: data)
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
                $0.element.migrated(id: TaskDocument.firstID + Int64($0.offset))
            }
            let document = TaskDocument(nextID: TaskDocument.firstID + Int64(items.count), items: items)
            try document.validate()
            return (document, data)
        }
        let document = try JSONDecoder.ghostPin.decode(TaskDocument.self, from: data)
        try document.validate()
        return (document, nil)
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

    private func preserveBackup(_ data: Data) throws {
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("todos.v1.backup.json")
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
