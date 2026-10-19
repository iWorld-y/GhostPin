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
        return directory.appendingPathComponent("todos.json")
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
        var root: URL? = applicationSupportRoot
        #if DEBUG
        if root == nil,
           let path = ProcessInfo.processInfo.environment["GHOSTPIN_TEST_SUPPORT_ROOT"],
           !path.isEmpty {
            root = URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        if let root {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            return root
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

}
