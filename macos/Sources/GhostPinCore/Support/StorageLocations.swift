import Foundation

public enum StorageLocations {
    public static let appName = "GhostPin"
    public static let legacyAppName = "TodoPin"

    public static func applicationSupportDirectory(
        appName: String = StorageLocations.appName,
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil
    ) throws -> URL {
        let base = try supportRoot(
            fileManager: fileManager,
            applicationSupportRoot: applicationSupportRoot
        )
        let directory = base.appendingPathComponent(appName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func todosURL(
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil
    ) throws -> URL {
        let directory = try applicationSupportDirectory(
            fileManager: fileManager,
            applicationSupportRoot: applicationSupportRoot
        )
        let todosURL = directory.appendingPathComponent("todos.json")
        let legacyURL = try legacyTodosURL(
            fileManager: fileManager,
            applicationSupportRoot: applicationSupportRoot
        )

        guard !fileManager.fileExists(atPath: todosURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return todosURL
        }

        try migrateLegacyTodos(
            from: legacyURL,
            to: todosURL,
            fileManager: fileManager
        )
        return todosURL
    }

    public static func legacyTodosURL(
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil
    ) throws -> URL {
        let base = try supportRoot(
            fileManager: fileManager,
            applicationSupportRoot: applicationSupportRoot
        )
        return base
            .appendingPathComponent(legacyAppName, isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    private static func supportRoot(
        fileManager: FileManager,
        applicationSupportRoot: URL?
    ) throws -> URL {
        if let applicationSupportRoot {
            try fileManager.createDirectory(
                at: applicationSupportRoot,
                withIntermediateDirectories: true
            )
            return applicationSupportRoot
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static func migrateLegacyTodos(
        from legacyURL: URL,
        to todosURL: URL,
        fileManager: FileManager
    ) throws {
        let data = try Data(contentsOf: legacyURL)
        _ = try JSONDecoder.ghostPin.decode([TodoItem].self, from: data)

        let temporaryURL = todosURL
            .deletingLastPathComponent()
            .appendingPathComponent(".todos-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL, options: [.atomic])
        guard !fileManager.fileExists(atPath: todosURL.path) else {
            return
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: todosURL)
        } catch {
            if !fileManager.fileExists(atPath: todosURL.path) {
                throw error
            }
        }
    }
}
