import Foundation

public enum Priority: String, Codable, Sendable, Comparable {
    case high
    case medium
    case low

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ priority: Priority) -> Int {
        switch priority {
        case .high:
            return 3
        case .medium:
            return 2
        case .low:
            return 1
        }
    }
}
