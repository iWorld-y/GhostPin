import Foundation

public enum TodoSource: String, Codable, CaseIterable, Sendable {
    case text
    case voice
}
