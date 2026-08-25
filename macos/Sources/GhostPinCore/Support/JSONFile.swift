import Foundation

public enum JSONFile {
    public static func load<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder.ghostPin
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
        encoder: JSONEncoder = JSONEncoder.ghostPin
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

extension JSONFile {
    public static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

extension JSONEncoder {
    public static var ghostPin: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var ghostPin: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
