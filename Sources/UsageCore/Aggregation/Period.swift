import Foundation

/// The time windows a displayed value can cover.
public enum Period: String, Sendable, Codable, CaseIterable {
    case today
    case thisWeek
    case thisMonth
    case rolling7
    case rolling30

    public var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .rolling7: "Last 7 Days"
        case .rolling30: "Last 30 Days"
        }
    }
}
