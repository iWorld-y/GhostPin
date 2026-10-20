import Foundation

/// 将随包 skill 安装到显式路径，并保护已有目录和符号链接。
public struct SkillInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 完整替换 skill，返回真实目录；失败时抛出包含恢复位置的错误。
    public func install(from source: URL, at destination: URL) throws -> URL {
        var linkCount = 0
        let source = try resolveDirectory(source.path, allowMissing: false, linkCount: &linkCount)
        try validateSource(source)
        let contents = try directoryContents(source)
        linkCount = 0
        let target = try resolveDirectory(destination.path, allowMissing: true, linkCount: &linkCount)
        let replacing = try validateTarget(target)

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let staging = parent.appendingPathComponent(".ghostpin-cli-\(identifier).staging")
        let backup = parent.appendingPathComponent(".ghostpin-cli-\(identifier).backup")
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        try validateSource(staging)
        guard try directoryContents(staging) == contents else {
            throw SkillInstallError("随包 skill 复制不完整，安装目录未替换")
        }
        guard try validateTarget(target) == replacing else {
            throw SkillInstallError("skill 安装目标在复制期间发生变化，拒绝替换: \(target.path)")
        }

        guard replacing else {
            try fileManager.moveItem(at: staging, to: target)
            return target
        }

        try fileManager.moveItem(at: target, to: backup)
        do {
            try fileManager.moveItem(at: staging, to: target)
        } catch {
            let commitError = error.localizedDescription
            do {
                try fileManager.moveItem(at: backup, to: target)
            } catch {
                throw SkillInstallError("skill 替换失败: \(commitError)。旧目录恢复失败，旧副本保留在: \(backup.path)。恢复错误: \(error.localizedDescription)")
            }
            throw SkillInstallError("skill 替换失败，已恢复旧目录: \(target.path)。\(commitError)")
        }
        do {
            try fileManager.removeItem(at: backup)
        } catch {
            throw SkillInstallError("新 skill 已安装到 \(target.path)，但旧副本清理失败，旧副本保留在: \(backup.path)。\(error.localizedDescription)")
        }
        return target
    }

    private func validateTarget(_ directory: URL) throws -> Bool {
        guard let type = try fileType(directory) else { return false }
        guard type == .typeDirectory,
              try fileType(directory.appendingPathComponent("ghostpin-cli")) == .typeRegular else {
            throw SkillInstallError("拒绝覆盖缺少普通文件归属标记 ghostpin-cli 的目录: \(directory.path)")
        }
        return true
    }

    private func validateSource(_ directory: URL) throws {
        guard try fileType(directory) == .typeDirectory,
              try fileType(directory.appendingPathComponent("ghostpin-cli")) == .typeRegular,
              try fileType(directory.appendingPathComponent("SKILL.md")) == .typeRegular,
              try fileType(directory.appendingPathComponent("agents")) == .typeDirectory,
              try fileType(directory.appendingPathComponent("agents/openai.yaml")) == .typeRegular,
              try Data(contentsOf: directory.appendingPathComponent("ghostpin-cli")).isEmpty else {
            throw SkillInstallError("随包 skill 不完整，需要 SKILL.md、agents/openai.yaml 和空普通文件 ghostpin-cli: \(directory.path)")
        }
    }

    // 按文件系统顺序处理链接和 '..'，不能先对原路径做词法规范化。
    private func resolveDirectory(_ path: String, allowMissing: Bool, linkCount: inout Int) throws -> URL {
        var resolved = URL(fileURLWithPath: "/", isDirectory: true)
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                resolved.deleteLastPathComponent()
                continue
            }
            let next = resolved.appendingPathComponent(String(component), isDirectory: true)
            switch try fileType(next) {
            case .typeSymbolicLink:
                linkCount += 1
                guard linkCount <= 40 else {
                    throw SkillInstallError("skill 路径存在符号链接循环或链接层数过多: \(path)")
                }
                let link = try fileManager.destinationOfSymbolicLink(atPath: next.path)
                let linkedPath = link.hasPrefix("/") ? link : resolved.path + "/" + link
                resolved = try resolveDirectory(linkedPath, allowMissing: false, linkCount: &linkCount)
            case .typeDirectory:
                resolved = next
            case nil where allowMissing:
                resolved = next
            case nil:
                throw SkillInstallError("skill 来源不存在或安装路径含断开的符号链接: \(next.path)")
            default:
                throw SkillInstallError("skill 路径必须指向目录: \(next.path)")
            }
        }
        return resolved
    }

    private func fileType(_ url: URL) throws -> FileAttributeType? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return nil
        }
    }

    private enum Entry: Equatable {
        case directory
        case file(Data)
        case symbolicLink(String)
    }

    private func directoryContents(_ directory: URL, prefix: String = "") throws -> [String: Entry] {
        var entries: [String: Entry] = [:]
        for name in try fileManager.contentsOfDirectory(atPath: directory.path) {
            let file = directory.appendingPathComponent(name)
            let relativePath = prefix + name
            switch try fileType(file) {
            case .typeDirectory:
                entries[relativePath] = .directory
                entries.merge(try directoryContents(file, prefix: relativePath + "/")) { _, value in value }
            case .typeRegular:
                entries[relativePath] = .file(try Data(contentsOf: file))
            case .typeSymbolicLink:
                entries[relativePath] = .symbolicLink(try fileManager.destinationOfSymbolicLink(atPath: file.path))
            default:
                throw SkillInstallError("skill 包含不支持的文件类型: \(file.path)")
            }
        }
        return entries
    }
}

private struct SkillInstallError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
