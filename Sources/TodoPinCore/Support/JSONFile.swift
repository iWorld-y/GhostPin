import Foundation

public enum JSONFile {
    public static func load<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder.todoPin
    ) throws -> T {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    public static func save<T: Encodable>(
        _ value: T,
        to url: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder.todoPin
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

extension JSONEncoder {
    public static var todoPin: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var todoPin: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
